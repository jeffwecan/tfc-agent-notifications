#!/usr/bin/env python
import hashlib
import hmac
import json
import logging
import os

import nomad
from flask import Flask, abort, request
from healthcheck import HealthCheck

DISPATCH_JOB_STATES = {
    "pending",
}

app = Flask(__name__)
app.logger.setLevel(logging.DEBUG)

nomad = nomad.Nomad(
    timeout=5,
    verify=True,
)


def assert_payload_signature_valid(request, secret):
    tfe_signature = request.headers.get("X-TFE-Notification-Signature")
    if tfe_signature is None:
        app.logger.warning(
            "no 'X-TFE-Notification-Signature' present in request, unable to validate signature"
        )
        abort(403)

    local_hmac = hmac.new(
        key=bytes(secret, "utf8"),
        msg=request.get_data(),
        digestmod=hashlib.sha512,
    )
    if (local_signature := local_hmac.hexdigest()) != tfe_signature:
        app.logger.warning(f"{local_signature=} != {tfe_signature}")
        abort(403)

    app.logger.debug("notification payload signature valid 🎉")


def process_payload(payload):
    meta = {
        "organization": payload["organization_name"],
        "workspace_id": payload["workspace_id"],
        "workspace_name": payload["workspace_name"],
    }
    job_name = f"tfc-agent-{payload['organization_name']}"

    for notification in payload["notifications"]:
        run_status = notification["run_status"]
        if run_status in DISPATCH_JOB_STATES:
            app.logger.info(f"{run_status=} => dispatching job {job_name} with {meta=}")
            nomad.job.dispatch_job(job_name, meta=meta)
        else:
            app.logger.debug(f"{run_status=} => not doing nothing ")


@app.route("/", methods=["GET", "POST"])
def process_incoming_webhook():
    signing_secret = os.getenv("SIGNING_SECRET")
    if signing_secret is None:
        abort(503)

    if request.method != "POST":
        abort(403)

    assert_payload_signature_valid(request, signing_secret)

    notification_payload = json.loads(request.get_data())
    app.logger.debug(f"{notification_payload=}")
    process_payload(notification_payload)
    return "notification payload processed successfully!"


def is_copacetic():
    if "SIGNING_SECRET" not in os.environ:
        return False, "missing SIGNING_SECRET env var 😭"

    return True, "SIGNING_SECRET 😎"


health = HealthCheck()
health.add_check(is_copacetic)
app.add_url_rule("/healthcheck", "healthcheck", view_func=lambda: health.run())

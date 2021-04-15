FROM ubuntu:20.04

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN \
    apt update --yes \
        && apt install python3-pip --yes --no-install-recommends

ADD requirements.txt /tfc_agent_notifications/
WORKDIR /tfc_agent_notifications

RUN /bin/bash -c "pip3 install --no-cache-dir -r requirements.txt"

RUN /usr/sbin/adduser \
    --home "/tfc_agent_notifications" \
    --no-create-home \
    --shell /bin/bash \
    "tfc_agent_notifications"

RUN /usr/sbin/groupadd --force --system "tfc_agent_notifications"
RUN /usr/sbin/usermod --gid "tfc_agent_notifications" "tfc_agent_notifications"
RUN chown --recursive tfc_agent_notifications:tfc_agent_notifications /tfc_agent_notifications

USER tfc_agent_notifications

ADD ./*.py /tfc_agent_notifications

CMD ddtrace-run \
    gunicorn \
    --bind=0.0.0.0:3000 \
    --worker-class=gevent \
    wsgi:app

variable "datacenters" {
  type = list(string)
  default = [
    "dc1",
  ]
}

job "tfc-agent-notifications" {
  type        = "service"
  datacenters = var.datacenters

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "15m"
    progress_deadline = "20m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "30s"
    healthy_deadline = "5m"
  }

  spread {
    attribute = meta.instance_id
  }

  group "tfc-agent-notifications" {
    count          = 2
    shutdown_delay = "30s"

    network {
      mode = "bridge"
      port "http" {
        to = 3000
      }
    }

    service {
      name = "tfc-agent-notifications"
      port = "http"

      check {
        name     = "alive"
        type     = "http"
        port     = "http"
        path     = "/healthcheck"
        interval = "30s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",

        "traefik.http.routers.tfc-agent-notifications-${NOMAD_ALLOC_ID}.tls=true",

        "traefik.http.middlewares.tfc-agent-notifications-${NOMAD_ALLOC_ID}-retry.retry.attempts=4",
        "traefik.http.routers.tfc-agent-notifications-${NOMAD_ALLOC_ID}.middlewares=tfc-agent-notifications-${NOMAD_ALLOC_ID}-retry",
      ]

      connect {
        sidecar_service {
          # We must set some sort of tags on this sidecard service explictly
          # otherwise it defaults to the surrounding service's tags and thus
          # traefik would balk at having: "Router defined multiple times with
          # different configuration"
          tags = [
            "traefik.enable=false",
          ]

          proxy {
            upstreams {
              destination_name = "datadog-tracing"
              local_bind_port  = 8126
            }
          }
        }
      }
    }

    task "tfc-agent-notifications" {
      driver = "docker"

      config {
        image = "docker.artifactory.hashicorp.engineering/tfc-agent-notifications:latest"
        ports = [
          "http",
        ]
        labels = {
          # Reference: https://docs.datadoghq.com/agent/logs/advanced_log_collection/?tab=docker
          "com.datadoghq.ad.logs" = jsonencode([{
            source = "python"
            service = "tfc-agent-notifications"
          }])
        }
      }

      resources {
        cpu    = 100
        memory = 100
      }

      env {
        DD_ENV            = meta.environment
        DD_SERVICE        = "tfc-agent-notifications"
        DD_LOGS_INJECTION = "true"
      }

      vault {
        policies = [
          "default",
          "tfc-agent",
        ]
      }

      template {
        destination = "secrets/file.env"
        env         = true
        data        = <<-ENVVARS
          SIGNING_SECRET="{{with secret "kv/data/tfc-agent/notifications"}}{{.Data.data.signing_secret}}{{end}}"
          ENVVARS
      }
    }
  }
}

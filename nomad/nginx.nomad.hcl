# Nomad job specification for the containerised NGINX site.
#
# This file replaces the Kubernetes Deployment/Service/HPA manifests from the
# reference application. Deploy it with:
#
#   nomad job run -var="image=ghcr.io/<owner>/<repo>:sha-<sha>" nomad/nginx.nomad.hcl
#
# The job uses host networking with a static host port so that it is
# reproducible on a single-node Nomad development agent without requiring CNI
# plugins. Keep `count = 1` on a single node; a static port cannot be bound by
# more than one allocation.

variable "image" {
  type        = string
  description = "Container image (prefer an immutable tag or digest)."
  default     = "ghcr.io/mdfaizfarooqui/nginx-nomad-pipeline:latest"
}

variable "image_pull_policy" {
  type        = string
  description = "Docker image pull policy: always, if-not-present or never."
  default     = "if-not-present"
}

variable "count" {
  type        = number
  description = "Number of NGINX allocations. Keep at 1 with a static port on one node."
  default     = 1
}

job "nginx" {
  name        = "nginx"
  datacenters = ["dc1"]
  type        = "service"
  priority    = 50

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = true
    stagger           = "10s"
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "web" {
    count          = var.count
    shutdown_delay = "5s"

    network {
      mode = "host"
      port "http" {
        static = 8080
      }
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "10s"
      mode     = "fail"
    }

    ephemeral_disk {
      size    = 100
      migrate = true
    }

    service {
      name     = "nginx"
      port     = "http"
      provider = "nomad"
      tags     = ["web", "nginx", "assessment"]

      check {
        name     = "nginx-healthz"
        type     = "http"
        path     = "/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image             = var.image
        image_pull_policy = var.image_pull_policy
        network_mode      = "host"
        ports             = ["http"]

        # Keep Docker's default json-file logging so Promtail's Docker service
        # discovery can tail the container log. Nomad rotates these files.
        logging {
          type = "json-file"
        }

        labels = {
          "com.example.application" = "nginx-nomad-pipeline"
          "com.example.owner"       = "Md Faiz Farooqui"
        }
      }

      env {
        NGINX_ENTRYPOINT_QUIET_LOGS = "1"
      }

      resources {
        cpu    = 100
        memory = 64
      }

      logs {
        max_files     = 3
        max_file_size = 10
      }
    }
  }
}

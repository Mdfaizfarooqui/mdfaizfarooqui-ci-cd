# Promtail tails the Docker json-file logs of the NGINX task and pushes them
# to Loki. It uses Docker service discovery, so no Nomad allocation path needs
# to be known in advance.
#
# Requires the Nomad client to allow host bind mounts:
#   plugin "docker" { config { volumes { enabled = true } } }
job "promtail" {
  name        = "promtail"
  datacenters = ["dc1"]
  type        = "service"
  priority    = 40

  group "promtail" {
    count = 1

    network {
      mode = "host"
    }

    task "promtail" {
      driver = "docker"
      user   = "0"

      config {
        image        = "grafana/promtail:3.6.11"
        network_mode = "host"
        args         = ["-config.file=/etc/promtail/config.yml"]
        volumes = [
          "local/promtail.yml:/etc/promtail/config.yml",
          "/var/run/docker.sock:/var/run/docker.sock",
          "/var/lib/docker/containers:/var/lib/docker/containers:ro",
        ]
      }

      template {
        destination = "local/promtail.yml"
        change_mode = "restart"
        data        = <<-EOF
          server:
            http_listen_address: 127.0.0.1
            http_listen_port: 9080
            grpc_listen_port: 0

          positions:
            filename: /tmp/positions.yaml

          clients:
            - url: http://127.0.0.1:3100/loki/api/v1/push

          scrape_configs:
            - job_name: nomad-docker
              docker_sd_configs:
                - host: unix:///var/run/docker.sock
                  refresh_interval: 5s
              relabel_configs:
                - source_labels: ['__meta_docker_container_label_com_hashicorp_nomad_job_name']
                  regex: '^nginx$'
                  action: keep
                - source_labels: ['__meta_docker_container_label_com_hashicorp_nomad_job_name']
                  target_label: 'job'
                - source_labels: ['__meta_docker_container_name']
                  regex: '/(.+)'
                  target_label: 'container'
                - source_labels: ['__meta_docker_container_label_com_hashicorp_nomad_task_name']
                  regex: '(.+)'
                  target_label: 'task'
                - source_labels: ['__meta_docker_container_label_com_hashicorp_nomad_alloc_id']
                  regex: '(.+)'
                  target_label: 'alloc_id'
                - source_labels: ['__meta_docker_container_label_com_hashicorp_nomad_namespace']
                  regex: '(.+)'
                  target_label: 'namespace'
              pipeline_stages:
                - json:
                    expressions:
                      output: log
                      stream: stream
                      timestamp: time
                - timestamp:
                    source: timestamp
                    format: RFC3339Nano
                - output:
                    source: output
        EOF
      }

      resources {
        cpu    = 100
        memory = 128
      }

      logs {
        max_files     = 3
        max_file_size = 10
      }
    }
  }
}

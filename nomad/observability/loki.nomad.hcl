# Single-binary Loki instance for the local assessment stack.
# Host networking keeps the single-node stack self-contained (no Consul/CNI).
job "loki" {
  name        = "loki"
  datacenters = ["dc1"]
  type        = "service"
  priority    = 40

  group "loki" {
    count = 1

    network {
      mode = "host"
    }

    ephemeral_disk {
      size    = 500
      migrate = true
    }

    task "loki" {
      driver = "docker"
      user   = "0"

      config {
        image        = "grafana/loki:3.6.19"
        network_mode = "host"
        args         = ["-config.file=/etc/loki/loki-config.yml"]
        volumes = [
          "local/loki-config.yml:/etc/loki/loki-config.yml",
          "local:/loki",
        ]
      }

      template {
        destination = "local/loki-config.yml"
        change_mode = "restart"
        data        = <<-EOF
          auth_enabled: false

          server:
            http_listen_address: 127.0.0.1
            http_listen_port: 3100
            grpc_listen_address: 127.0.0.1
            grpc_listen_port: 9096
            log_level: info

          common:
            instance_addr: 127.0.0.1
            path_prefix: /loki
            storage:
              filesystem:
                chunks_directory: /loki/chunks
                rules_directory: /loki/rules
            replication_factor: 1
            ring:
              kvstore:
                store: inmemory

          schema_config:
            configs:
              - from: 2024-04-01
                store: tsdb
                object_store: filesystem
                schema: v13
                index:
                  prefix: index_
                  period: 24h

          limits_config:
            retention_period: 168h

          compactor:
            working_directory: /loki/compactor
            retention_enabled: true
            delete_request_store: filesystem

          analytics:
            reporting_enabled: false
        EOF
      }

      resources {
        cpu    = 300
        memory = 256
      }

      logs {
        max_files     = 3
        max_file_size = 10
      }
    }
  }
}

# Grafana with provisioned Loki datasource and an NGINX log dashboard.
# Host networking lets Grafana reach Loki on 127.0.0.1:3100.
job "grafana" {
  name        = "grafana"
  datacenters = ["dc1"]
  type        = "service"
  priority    = 40

  group "grafana" {
    count = 1

    network {
      mode = "host"
    }

    task "grafana" {
      driver = "docker"

      config {
        image        = "grafana/grafana:13.0.12"
        network_mode = "host"
        volumes = [
          "local/datasource.yml:/etc/grafana/provisioning/datasources/loki.yml",
          "local/dashboards.yml:/etc/grafana/provisioning/dashboards/provider.yml",
          "local/nginx-dashboard.json:/etc/grafana/provisioning/dashboards/nginx-dashboard.json",
        ]
      }

      template {
        destination = "local/datasource.yml"
        change_mode = "restart"
        data        = <<-EOF
          apiVersion: 1
          datasources:
            - name: Loki
              uid: loki
              type: loki
              access: proxy
              url: http://127.0.0.1:3100
              isDefault: true
              editable: false
        EOF
      }

      template {
        destination = "local/dashboards.yml"
        change_mode = "restart"
        data        = <<-EOF
          apiVersion: 1
          providers:
            - name: nginx
              orgId: 1
              folder: NGINX
              type: file
              disableDeletion: false
              updateIntervalSeconds: 30
              allowUiUpdates: true
              options:
                path: /etc/grafana/provisioning/dashboards
        EOF
      }

      template {
        destination = "local/nginx-dashboard.json"
        change_mode = "restart"
        data        = <<-EOF
          {
            "annotations": { "list": [] },
            "editable": true,
            "fiscalYearStartMonth": 0,
            "graphTooltip": 0,
            "id": null,
            "links": [],
            "panels": [
              {
                "datasource": { "type": "loki", "uid": "loki" },
                "fieldConfig": {
                  "defaults": { "color": { "mode": "palette-classic" }, "custom": {} },
                  "overrides": []
                },
                "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
                "id": 1,
                "options": {
                  "dedup": false,
                  "enableLogDetails": true,
                  "showCommonLabels": false,
                  "showLabels": true,
                  "showTime": true,
                  "sortOrder": "Descending",
                  "wrapLogMessage": true
                },
                "targets": [
                  {
                    "datasource": { "type": "loki", "uid": "loki" },
                    "editorMode": "code",
                    "expr": "{job=\"nginx\"}",
                    "queryType": "range",
                    "refId": "A"
                  }
                ],
                "title": "NGINX container logs",
                "type": "logs"
              },
              {
                "datasource": { "type": "loki", "uid": "loki" },
                "fieldConfig": {
                  "defaults": {
                    "color": { "mode": "palette-classic" },
                    "custom": {
                      "drawStyle": "line",
                      "lineInterpolation": "linear",
                      "fillOpacity": 10,
                      "showPoints": "never"
                    }
                  },
                  "overrides": []
                },
                "gridPos": { "h": 8, "w": 12, "x": 0, "y": 10 },
                "id": 2,
                "options": {
                  "legend": { "displayMode": "list", "placement": "bottom" },
                  "tooltip": { "mode": "single" }
                },
                "targets": [
                  {
                    "datasource": { "type": "loki", "uid": "loki" },
                    "editorMode": "code",
                    "expr": "sum(count_over_time({job=\"nginx\"}[1m]))",
                    "queryType": "range",
                    "refId": "A",
                    "legendFormat": "lines/min"
                  }
                ],
                "title": "NGINX log volume",
                "type": "timeseries"
              }
            ],
            "refresh": "10s",
            "schemaVersion": 39,
            "tags": ["nginx", "nomad", "assessment"],
            "templating": { "list": [] },
            "time": { "from": "now-1h", "to": "now" },
            "timepicker": {},
            "timezone": "browser",
            "title": "NGINX on Nomad",
            "uid": "nginx-nomad",
            "version": 1
          }
        EOF
      }

      env {
        GF_SERVER_HTTP_ADDR            = "127.0.0.1"
        GF_SERVER_HTTP_PORT            = "3000"
        GF_AUTH_ANONYMOUS_ENABLED      = "true"
        GF_AUTH_ANONYMOUS_ORG_ROLE     = "Viewer"
        GF_SECURITY_ADMIN_USER         = "admin"
        GF_SECURITY_ADMIN_PASSWORD     = "admin"
        GF_USERS_ALLOW_SIGN_UP         = "false"
        GF_ANALYTICS_REPORTING_ENABLED = "false"
        GF_ANALYTICS_CHECK_FOR_UPDATES = "false"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      logs {
        max_files     = 3
        max_file_size = 10
      }
    }
  }
}

# Local single-node Nomad development agent.
#
# Start it with:
#   nomad agent -dev -bind=127.0.0.1 -config=nomad/local-agent.hcl
#
# The Docker volume plugin option is required by the Promtail job, which bind
# mounts /var/run/docker.sock and /var/lib/docker/containers. Do the equivalent
# in a production client configuration.

plugin "docker" {
  config {
    volumes {
      enabled = true
    }
  }
}

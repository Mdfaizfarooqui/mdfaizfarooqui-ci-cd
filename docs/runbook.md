# Operations runbook

## Quick reference

| Action | Command |
| --- | --- |
| Build image | `make build` |
| Test image | `make test` |
| Start local stack | `make local-up` |
| Stop local stack | `make local-down` |
| Deploy app | `IMAGE=<ref> make deploy` |
| Smoke-test app | `EXPECTED_BUILD_ID=<id> make smoke` |
| Job status | `nomad job status nginx` |
| Follow logs | `nomad job logs -f nginx` |
| Roll back | `nomad job revert nginx <version>` |

## First-time setup

```bash
# Docker access (required by Nomad's docker driver)
sudo usermod -aG docker "$USER"
# log out and back in
docker info

# Pinned Nomad CLI
make install-nomad
export PATH="$PWD/.tools/bin:$PATH"
nomad version
```

## Deploying a new version

### Through CI (normal path)

1. Open a pull request. The `lint` job builds the image and runs the container
   smoke test; it does not deploy.
2. Merge to `main`. `build-push` pushes
   `ghcr.io/<owner>/<repo>:sha-<short>` and the `deploy` job runs on the
   self-hosted Nomad runner.
3. The deploy job validates the HCL, runs `scripts/deploy.sh`, and verifies the
   build ID reported by the running site.

### Manually

```bash
IMAGE=ghcr.io/<owner>/<repo>:sha-<short> \
IMAGE_PULL_POLICY=always \
./scripts/deploy.sh

EXPECTED_BUILD_ID=<run-id-sha> URL=http://127.0.0.1:8080 \
./scripts/smoke-test.sh
```

To use a local image instead of a registry image:

```bash
make build
IMAGE=nginx-nomad-pipeline:$(git rev-parse --short HEAD) \
IMAGE_PULL_POLICY=never \
./scripts/deploy.sh
```

## Verifying a deployment

```bash
nomad job status nginx
nomad job status nginx | sed -n '/Allocations/,/^$/p'
nomad allocation status <alloc-id>
nomad job logs -s stderr nginx
```

Application checks:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/build-info.json | jq
curl -fsS http://127.0.0.1:8080/ | grep -E "Md Faiz|2026-11-05|Build ID"
```

Expected `/build-info.json` shape:

```json
{
  "build_id": "42-a1b2c3d",
  "git_sha": "a1b2c3d...",
  "build_date": "2026-11-06T00:00:00Z",
  "repository": "owner/repo"
}
```

## Rollback

Nomad keeps job versions. Find the last known-good version and revert:

```bash
nomad job history nginx
nomad job revert nginx <version>
nomad job status nginx
```

A failed deployment also reverts automatically because the job sets
`auto_revert = true` in the `update` stanza.

To redeploy an older image without reverting the job specification:

```bash
nomad job run -var "image=ghcr.io/<owner>/<repo>:sha-<older>" nomad/nginx.nomad.hcl
```

## Observability checks

```bash
curl -fsS http://127.0.0.1:3100/ready
curl -fsS http://127.0.0.1:9080/targets | grep -A5 nginx
curl -fsS http://127.0.0.1:3000/api/health
```

Generate traffic and query Loki:

```bash
for i in $(seq 1 10); do curl -s http://127.0.0.1:8080/ >/dev/null; done
curl -fsS -G http://127.0.0.1:3100/loki/api/v1/query \
  --data-urlencode 'query={job="nginx"}' \
  --data-urlencode 'limit=5' | jq '.data.result | length'
```

In Grafana, open **Dashboards -> NGINX -> NGINX on Nomad**. Set the time range to
**Last 15 minutes**. If the panel is empty:

1. confirm Promtail has a target for the NGINX container;
2. confirm Loki is ready;
3. run `nomad job logs nginx` to confirm the container is writing to stdout;
4. check the Promtail allocation logs:
   `nomad job logs -s stderr promtail`.

## Common failures

### `Cannot connect to the Docker daemon`

The Nomad client and the deploy scripts run as your user. Add the user to the
`docker` group, then start a new login session so the group membership applies:

```bash
sudo usermod -aG docker "$USER"
id -nG
```

### Nomad agent fails to start

Inspect `.nomad-dev.log` in the repository root. Frequent causes are port 4646
already in use, a malformed `local-agent.hcl`, or running as a user without
Docker access.

### Port 8080 already in use

The job uses host networking. Stop the conflicting process or change both the
Nomad `port` and the NGINX `listen` directive in `app/hello.conf` (and the
health/smoke URLs) together.

### Promtail sees no targets

Promtail must mount the Docker socket. The local agent enables bind mounts:

```hcl
plugin "docker" {
  config {
    volumes {
      enabled = true
    }
  }
}
```

If you use a custom Nomad client config, add that block and restart the client.
Also verify `/var/run/docker.sock` exists on the host.

### Deployment stuck in `pending` or `failed`

```bash
nomad job status nginx
nomad deployment status <deployment-id>
nomad allocation status <alloc-id>
nomad job logs -s stderr nginx
```

Common causes: image pull failure (authenticate the Docker daemon to GHCR), no
eligible node with free port 8080, or the health check never becoming healthy.
The deployment fails after `progress_deadline` and auto-reverts.

### CI deploy job cannot reach Nomad

The deploy job runs on a self-hosted runner by design. Confirm the runner has the
labels `self-hosted,linux,nomad`, that it runs on the Nomad node, and that
`NOMAD_ADDR` (if set) is reachable from that runner. For a dev agent the default
`http://127.0.0.1:4646` is correct.

### CI cannot pull the pushed image on the Nomad node

GHCR packages may be private. Authenticate the Docker daemon used by Nomad:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin
```

Use a token with `read:packages` scope. Alternatively make the package public.

## Cleanup

Stop the local application and observability jobs:

```bash
make local-down
```

For a full reset, remove the local Nomad log/pid, the downloaded CLI and the
built image. A `nomad agent -dev` keeps its state in temporary directories, so
stopping the agent discards it:

```bash
rm -rf .nomad-dev.log .nomad-dev.pid .tools
docker image rm nginx-nomad-pipeline:$(git rev-parse --short HEAD) 2>/dev/null || true
```

## Change management

- Update the pinned versions in `Dockerfile`, `nomad/observability/*.nomad.hcl`
  and the README together.
- Run `make fmt` after editing HCL.
- Run `make lint` before opening a pull request (requires shellcheck, hadolint
  and the Nomad CLI).
- Never deploy a mutable `latest` tag to production; use the immutable
  `sha-<short>` tag from CI.

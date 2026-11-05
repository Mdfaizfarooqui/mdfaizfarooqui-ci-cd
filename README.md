# NGINX on Nomad - end-to-end deployment pipeline

A reproducible pipeline for a containerised NGINX site: source control, image
build with injected provenance, automated CI, orchestrated deployment with
HashiCorp Nomad, and centralised logs with Loki, Promtail and Grafana.

| Item | Value |
| --- | --- |
| Author | Md Faiz Farooqui |
| Assessment date | 2026-11-05 |
| Application | Static NGINX page served on port 8080 |
| Orchestrator | HashiCorp Nomad (single-node local target) |
| CI/CD | GitHub Actions, images in GitHub Container Registry (GHCR) |
| Logs | Promtail -> Loki -> Grafana |
| Reference app | [nginxinc/NGINX-Demos `coffee`](https://github.com/nginxinc/NGINX-Demos/tree/master/kubernetes-demo-nginx-ingress-resources/apps/coffee) |

The reference application's Kubernetes manifests have been replaced by
`nomad/nginx.nomad.hcl`. The page shows the author name, assessment date and a
build identifier that is injected at image build time.

## Pipeline at a glance

```
 developer push
      |
      v
 GitHub repository
      |
      v
 GitHub Actions: lint -> build -> smoke-test -> push image to GHCR
      |                                                |
      |                                                v
      +-------------------------------> self-hosted runner on the Nomad node
                                                       |
                                                       v
                                            nomad job run nginx
                                                       |
                                                       v
                                          Docker task: nginx:8080
                                                       |
                                     Docker json-file logs
                                                       |
                                                       v
                                  Promtail --(Loki API)--> Loki --> Grafana
```

Every stage consumes the previous stage's output:

1. The Dockerfile `COPY`s the committed `index.html` and injects `BUILD_ID`,
   `GIT_SHA` and `BUILD_DATE` into it during `docker build`.
2. CI builds and smoke-tests that exact image, then pushes an immutable
   `sha-<short>` tag to GHCR.
3. The deploy job passes that immutable image reference to Nomad.
4. Nomad starts the container; Promtail discovers it through the Docker API and
   ships its logs to Loki; Grafana queries Loki.

## Repository layout

```
.
├── .github/workflows/ci-cd.yml        # lint, build, push, deploy
├── app/
│   ├── Dockerfile                     # image + build-time provenance injection
│   ├── hello.conf                     # NGINX server config, /healthz, /build-info.json
│   └── index.html                     # page with __BUILD_ID__ placeholders
├── nomad/
│   ├── nginx.nomad.hcl                # replaces the Kubernetes manifests
│   ├── local-agent.hcl                # local dev agent (enables Docker volumes)
│   └── observability/
│       ├── loki.nomad.hcl
│       ├── promtail.nomad.hcl
│       └── grafana.nomad.hcl
├── scripts/                           # build, test, deploy, smoke, local up/down
├── docs/                              # architecture and operations runbook
├── Makefile
├── LICENSE                            # Apache-2.0 (upstream)
└── NOTICE                             # upstream attribution and modifications
```

No `.idea/`, `.vscode/` or other IDE metadata is committed; see `.gitignore`.

## Reference application and modifications

The starting point is the Apache-2.0 licensed NGINX demo application:

- Repository: <https://github.com/nginxinc/NGINX-Demos>
- Path: `kubernetes-demo-nginx-ingress-resources/apps/coffee`
- Pinned commit: `611fa05748a4031841e5607cd3069288b0aa9973`
- Upstream files used: `Dockerfile`, `hello.conf`, `index.html`
- Upstream manifests replaced: `k8s/apps.yaml` (Deployment/Service resources)

Changes made for this assessment:

- `index.html` now displays **Md Faiz Farooqui**, **2026-11-05**, the build ID,
  the Git commit and the build timestamp.
- `Dockerfile` takes `BUILD_ID`, `GIT_SHA`, `BUILD_DATE` and
  `BUILD_REPOSITORY` build arguments and bakes them into `index.html` and
  `build-info.json`.
- `hello.conf` adds `/healthz` (Nomad health check) and `/build-info.json`.
- Kubernetes Deployment/Service/HPA manifests removed; a Nomad job replaces
  them.
- CI, local reproduction scripts, log aggregation and dashboards added.

See `NOTICE` for the full attribution and modification list.

## Prerequisites

| Tool | Version used | Purpose |
| --- | --- | --- |
| Docker Engine | 29.x | Nomad `docker` task driver and local image builds |
| Nomad | 2.1.1 | Orchestration |
| curl, jq | recent | Verification scripts |
| GitHub account | - | CI and GHCR |
| Linux host | Fedora 44 tested | Single-node target |

The scripts can build and test the image with Podman (`CONTAINER_ENGINE=podman`),
but the local Nomad deployment requires a working Docker daemon because the job
uses the `docker` task driver. Add your user to the Docker group once:

```bash
sudo usermod -aG docker "$USER"
# log out and back in, then:
docker info
```

Install the pinned Nomad binary into the repository (checksum verified). The
scripts add `.tools/bin` to `PATH` automatically; export it for interactive
`nomad` commands:

```bash
make install-nomad
export PATH="$PWD/.tools/bin:$PATH"
nomad version    # Nomad v2.1.1
```

Alternatively install Nomad from HashiCorp's package repository. The CI workflow
installs the same pinned version.

## Reproduce locally from scratch

### 1. Build and test the image

```bash
make build
make test
```

`make build` prints the injected values. `make test` starts the image on
`127.0.0.1:18080`, then asserts that the page contains the author, the
assessment date and the build ID, and that `/build-info.json` matches.

Inspect the result manually:

```bash
docker run --rm -d --name nginx-demo -p 8080:8080 \
  nginx-nomad-pipeline:$(git rev-parse --short HEAD)
curl -s http://127.0.0.1:8080/ | grep -E "Md Faiz|2026-11-05|Build"
curl -s http://127.0.0.1:8080/build-info.json | jq
docker rm -f nginx-demo
```

### 2. Start the full local stack

```bash
make local-up
```

This command:

1. starts `nomad agent -dev` on `127.0.0.1:4646` (if not already running), using
   `nomad/local-agent.hcl` to enable Docker bind mounts;
2. builds the image with a build ID;
3. deploys `loki`, `promtail` and `grafana`;
4. deploys `nginx` and runs the smoke test.

Endpoints:

| Service | URL |
| --- | --- |
| Application | <http://127.0.0.1:8080> |
| Build provenance | <http://127.0.0.1:8080/build-info.json> |
| Health check | <http://127.0.0.1:8080/healthz> |
| Grafana | <http://127.0.0.1:3000> (anonymous viewer; admin/admin) |
| Loki readiness | <http://127.0.0.1:3100/ready> |
| Promtail targets | <http://127.0.0.1:9080/targets> |
| Nomad UI | <http://127.0.0.1:4646> |

In Grafana open **Dashboards -> NGINX -> NGINX on Nomad**. The provisioned
dashboard shows the live container log stream and log volume. Generate traffic
to see entries:

```bash
for i in $(seq 1 20); do curl -s http://127.0.0.1:8080/ >/dev/null; done
```

Promtail can also be checked directly:

```bash
curl -s http://127.0.0.1:9080/targets | grep -A2 nginx
```

### 3. Tear down

```bash
make local-down
```

This stops the four jobs and the Nomad agent started by `make local-up`.

## How the build identifier is injected

`app/index.html` is committed with placeholders:

```html
<span id="build-id">__BUILD_ID__</span>
<span>__GIT_SHA__</span>
<span>__BUILD_DATE__</span>
```

`app/Dockerfile` receives build arguments and rewrites the copied file inside
the image:

```dockerfile
ARG BUILD_ID=dev
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown

RUN sed -i \
  -e "s|__BUILD_ID__|${BUILD_ID}|g" \
  -e "s|__GIT_SHA__|${GIT_SHA}|g" \
  -e "s|__BUILD_DATE__|${BUILD_DATE}|g" \
  /usr/share/nginx/html/index.html
```

It also writes `/usr/share/nginx/html/build-info.json` and fails the build if the
build ID is not present. The value is therefore part of the image, not the
container environment, and the running deployment can prove exactly which build
it serves:

```bash
curl -s http://127.0.0.1:8080/build-info.json
# {"build_id":"42-a1b2c3d","git_sha":"...","build_date":"...","repository":"..."}
```

Local builds default to the Git short SHA. CI uses
`${GITHUB_RUN_NUMBER}-${GITHUB_SHA::7}`, and the deploy job asserts that the
running page reports the same ID.

## Automated CI/CD (GitHub Actions)

Workflow: `.github/workflows/ci-cd.yml`

| Job | Trigger | What it does |
| --- | --- | --- |
| `lint` | every push and PR | hadolint, actionlint, shellcheck, `nomad fmt -check`, renders all job specs, builds the image, runs the container smoke test |
| `build-push` | push to `main`, tags, manual | builds multi-stage provenance/SBOM image, tags `sha-<short>` and `latest`, pushes to GHCR |
| `deploy` | push to `main`, manual | runs on the self-hosted Nomad runner, validates the job against the live cluster, deploys the immutable image, verifies the reported build ID |

### One-time GitHub setup

1. Push this repository to GitHub. GHCR uses the built-in `GITHUB_TOKEN`; no
   registry secret is required.
2. Register a self-hosted runner on the Nomad node with the labels
   `self-hosted`, `linux` and `nomad` (the workflow's `runs-on` value). The
   runner user must be able to run `docker` and reach the Nomad API.
3. Add repository secrets (Settings -> Secrets and variables -> Actions):

| Secret | Required | Value |
| --- | --- | --- |
| `NOMAD_ADDR` | no | Defaults to `http://127.0.0.1:4646` |
| `NOMAD_TOKEN` | no | Nomad ACL token; leave unset for a dev agent |

The deploy job is intentionally pinned to a self-hosted runner because a
GitHub-hosted runner cannot reach a Nomad API bound to the node's loopback
address. Make the Nomad node the runner, or expose Nomad behind a private
network and adjust `NOMAD_ADDR`.

The Nomad node must be able to pull the private/public GHCR image. Log the
Docker daemon in once, for example with a read-only package token:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin
```

Alternatively configure a Nomad `docker` auth helper; see the Nomad Docker
driver documentation.

### What the deploy job runs

```bash
nomad job validate -var "image=<immutable-tag>" nomad/nginx.nomad.hcl
IMAGE=<immutable-tag> IMAGE_PULL_POLICY=always ./scripts/deploy.sh
EXPECTED_BUILD_ID=<run-id-sha> ./scripts/smoke-test.sh
```

`nomad job run` blocks until the deployment reaches a terminal state. The
`update` stanza has `auto_revert = true`, so a failed deployment is rolled back
to the last stable version automatically.

## Nomad job design

`nomad/nginx.nomad.hcl`:

- `type = "service"`, `datacenters = ["dc1"]`.
- Host networking with static port `8080` so the stack works on a single node
  without CNI plugins. Keep `count = 1` on one node; a static port cannot be
  bound by multiple allocations.
- Nomad-native service registration (`provider = "nomad"`) with an HTTP health
  check on `/healthz`.
- Rolling update with `max_parallel = 1`, `min_healthy_time`, `healthy_deadline`
  and `auto_revert`.
- Docker task using an immutable image supplied through the `image` variable.
- Docker `json-file` logging with Nomad log rotation (`max_files`,
  `max_file_size`), so Promtail has a stable source to tail.
- Resource limits: 100 MHz CPU, 64 MB memory.

Deploy manually:

```bash
IMAGE=ghcr.io/<owner>/<repo>:sha-<short> make deploy
# or
nomad job run -var "image=ghcr.io/<owner>/<repo>:sha-<short>" nomad/nginx.nomad.hcl
```

To scale beyond one allocation, switch the group to bridge networking with CNI
plugins and dynamic ports (or spread allocations across multiple nodes with
unique ports), and put a load balancer or Nomad service consumer in front.

## Log aggregation design

- **Promtail** uses Docker service discovery against `/var/run/docker.sock`,
  keeps containers whose Nomad job label is `nginx`, parses the Docker
  `json-file` envelope, and pushes to Loki.
- **Loki** runs in single-binary mode with filesystem storage, bound to
  `127.0.0.1:3100` on the Nomad host.
- **Grafana** is provisioned with a Loki datasource and the **NGINX on Nomad**
  dashboard. Anonymous viewing is enabled for assessment convenience; change
  `GF_AUTH_ANONYMOUS_*` and the admin password for any shared environment.
- The whole observability stack uses host networking on a single node, so the
  components can reach each other on loopback without Consul or CNI.

The Promtail job requires the Nomad client option:

```hcl
plugin "docker" {
  config {
    volumes {
      enabled = true
    }
  }
}
```

`nomad/local-agent.hcl` provides it for the dev agent. Production clients need
the same option (plus a durable host volume for Loki data if logs must survive
allocation rescheduling).

Useful Loki queries in Grafana:

```logql
{job="nginx"}
{job="nginx"} |= "GET"
sum(count_over_time({job="nginx"}[1m]))
```

## Operations runbook

```bash
# Status of the application and deployments
nomad job status nginx
nomad deployment status <deployment-id>

# Stream logs from Nomad's allocation log
nomad job logs -f nginx

# Roll back to a previous job version (auto_revert also does this on failure)
nomad job history nginx
nomad job revert nginx <version>

# Redeploy a specific image
nomad job run -var "image=ghcr.io/<owner>/<repo>:sha-<short>" nomad/nginx.nomad.hcl

# Stop and purge the application
nomad job stop -purge nginx
```

See `docs/runbook.md` for troubleshooting and `docs/architecture.md` for design
decisions.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Cannot connect to the Docker daemon` | Add the user to the `docker` group and re-login. |
| Nomad dev agent starts but no allocations | Check `docker info` as the same user; inspect `.nomad-dev.log`. |
| `address already in use` on 8080 | Another process is using the static port. Stop it or change the Nomad port and NGINX listen port together. |
| Promtail has no targets | Confirm Docker volume mounting is enabled in the Nomad client config and that `/var/run/docker.sock` exists. Check `http://127.0.0.1:9080/targets`. |
| Grafana dashboard is empty | Generate requests, wait for the Promtail refresh (5s) and Loki ingestion, then use the last 15 minutes. |
| Nomad cannot pull the CI image | Authenticate the Docker daemon to `ghcr.io`, or use a public package. |
| Local image not found by Nomad | Build with Docker, not Podman. Nomad's Docker driver cannot see Podman's image store. |
| `nomad fmt -check` fails | Run `make fmt` and commit the formatted HCL. |

## Assessment checklist

- [x] Reference NGINX application vendored with upstream attribution.
- [x] Kubernetes manifests replaced with a Nomad job specification.
- [x] `index.html` shows name, assessment date and build identifier.
- [x] Build identifier injected at image build time and exposed via
      `/build-info.json`.
- [x] `.gitignore` excludes IDE metadata and local artifacts.
- [x] Automated CI builds, tests, pushes and deploys the image.
- [x] Orchestrated deployment with health checks, rolling update and rollback.
- [x] Centralised log aggregation with Promtail, Loki and Grafana.
- [x] Reproducible local workflow documented end to end.

## Security notes

- The local Grafana instance uses anonymous viewer access and `admin/admin`;
  this is for the assessment only. Set strong credentials and disable anonymous
  access for any shared deployment.
- The Promtail container mounts the Docker socket, which is privileged. Run it
  only on trusted Nomad clients; in production consider a dedicated log shipper
  or the Docker Loki logging driver.
- Never commit Nomad ACL tokens, registry credentials or `.env` files. The
  `.gitignore` covers the usual cases.
- Pin images and Nomad versions (as this repository does) for reproducible
  deployments.

## Tested versions

Fedora Linux 44, Docker 29.8.1, Nomad 2.1.1, nginx 1.29.8-alpine,
Grafana Loki 3.6.19, Promtail 3.6.11, Grafana 13.0.12, GitHub Actions runners
`ubuntu-latest`.

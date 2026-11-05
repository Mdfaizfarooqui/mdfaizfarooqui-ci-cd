# syntax=docker/dockerfile:1.7
#
# Based on the Apache-2.0 licensed NGINX "coffee" demo:
# https://github.com/nginxinc/NGINX-Demos/tree/master/kubernetes-demo-nginx-ingress-resources/apps/coffee
# See ../NOTICE for attribution and the list of modifications.
FROM nginx:1.29.8-alpine

ARG BUILD_ID=dev
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
ARG BUILD_REPOSITORY=local/nginx-nomad-pipeline

LABEL org.opencontainers.image.title="nginx-nomad-pipeline" \
      org.opencontainers.image.description="Static NGINX site deployed with HashiCorp Nomad" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
      com.example.build-id="${BUILD_ID}"

# NGINX runs as the unprivileged nginx user. It needs write access to its
# cache directory and pid file so it can run with a random/rootless UID.
RUN chmod -R a+w /var/cache/nginx/ \
    && touch /var/run/nginx.pid \
    && chmod a+w /var/run/nginx.pid \
    && rm -f /etc/nginx/conf.d/*

COPY hello.conf /etc/nginx/conf.d/hello.conf
COPY index.html /usr/share/nginx/html/index.html

# Inject the build identifier and commit at image build time. These values are
# baked into the image, so the running container can prove which build it serves.
RUN set -eux; \
    sed -i \
      -e "s|__BUILD_ID__|${BUILD_ID}|g" \
      -e "s|__GIT_SHA__|${GIT_SHA}|g" \
      -e "s|__BUILD_DATE__|${BUILD_DATE}|g" \
      /usr/share/nginx/html/index.html; \
    printf '{"build_id":"%s","git_sha":"%s","build_date":"%s","repository":"%s"}\n' \
      "${BUILD_ID}" "${GIT_SHA}" "${BUILD_DATE}" "${BUILD_REPOSITORY}" \
      > /usr/share/nginx/html/build-info.json; \
    grep -Fq "${BUILD_ID}" /usr/share/nginx/html/index.html; \
    grep -Fq "${BUILD_ID}" /usr/share/nginx/html/build-info.json

EXPOSE 8080

USER nginx

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1

STOPSIGNAL SIGQUIT

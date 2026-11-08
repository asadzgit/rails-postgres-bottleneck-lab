# syntax=docker/dockerfile:1
FROM postgres:17-bookworm@sha256:665dc7b37ac52a17e298511414c21d23ffa4e6a6ef6225b3e5d59c7afb35e994
ARG PGBOUNCER_VERSION=1.26.1-1.pgdg12+1
# Official signed PostgreSQL APT package; keep TLS and APT signature verification enabled.
RUN --mount=type=secret,id=proxy_ca,required=true \
    apt-get -o Acquire::https::CaInfo=/run/secrets/proxy_ca update && \
    apt-get -o Acquire::https::CaInfo=/run/secrets/proxy_ca install -y --no-install-recommends "pgbouncer=${PGBOUNCER_VERSION}" && \
    rm -rf /var/lib/apt/lists/*
USER postgres
ENTRYPOINT ["/bin/bash", "/etc/pgbouncer/start.sh"]

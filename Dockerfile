
FROM alpine:3.22

RUN apk add --no-cache \
    bash \
    docker-cli \
    openssh-client \
    tar \
    gzip \
    coreutils \
    dcron \
    tzdata

COPY backup.sh /usr/local/bin/backup.sh

RUN chmod 700 /usr/local/bin/backup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 700 /usr/local/bin/entrypoint.sh

ARG VERSION=0.1.0

LABEL org.opencontainers.image.title="Docker Backup" \
      org.opencontainers.image.description="Lightweight Docker container backup with SSH-based remote storage" \
      org.opencontainers.image.source="https://github.com/thwcz/docker-backup" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.version="${VERSION}"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


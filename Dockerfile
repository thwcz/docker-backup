
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

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


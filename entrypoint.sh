#!/bin/bash

set -Eeuo pipefail

: "${BACKUP_CRON_EXPRESSION:=0 2 * * *}"

mkdir -p /var/log/backup

echo "$BACKUP_CRON_EXPRESSION /usr/local/bin/backup.sh >> /var/log/backup/backup.log 2>&1" \
  > /etc/crontabs/root

echo "Backup schedule: $BACKUP_CRON_EXPRESSION"

exec crond -f -l notice


# Docker Backup

A lightweight Docker container backup solution with SSH-based offsite storage.

Docker Backup creates individual archives for selected containers, including
Docker metadata and user-defined host paths.

## Features

- Individual backup archives per container
- Optional container shutdown during backup
- Immediate container restart after local archive creation
- SSH/SCP-based remote storage
- Configurable retention period
- Cron-based scheduling
- Configurable backup paths
- Docker container metadata included in every archive
- Lightweight Alpine Linux base image

## Requirements

- Docker Engine
- Docker Compose
- Linux host
- SSH access to a remote backup destination

## Docker Image

The official image is hosted on GitHub Container Registry:

`ghcr.io/thwcz/docker-backup`

Available tags:

| Tag | Description |
|---|---|
| `latest` | Latest published release |
| `0.1.0` | Initial release |
| `0.1.1` | Release with OCI image metadata |

Currently published for **Linux ARM64 (aarch64)**.

The image is publicly available and does not require authentication to pull.

## Installation

1. Download the example Compose file:

   `curl -O https://raw.githubusercontent.com/thwcz/docker-backup/main/compose.example.yaml`

2. Rename it to `compose.yaml`:

   `mv compose.example.yaml compose.yaml`

3. Adapt the configuration to your environment.
4. Make sure the required host paths and SSH credentials are mounted into the container.
5. Pull the image and start the service:

   ```bash
   docker compose pull
   docker compose up -d
   ```

## Updating

To update to the latest published image:

```bash
docker compose pull
docker compose up -d
```

For reproducible deployments, use a fixed version tag instead of `latest`.

Change the image reference in your Compose file, for example:

`ghcr.io/thwcz/docker-backup:0.1.1`

Then pull and recreate the container.

## Configuration

### Environment variables

| Variable | Required | Default |
|---|---|---|
| BACKUP_JOBS | Yes | - |
| SSH_HOST | Yes | - |
| SSH_USER | Yes | - |
| SSH_REMOTE_PATH | Yes | - |
| SSH_PORT | No | 22 |
| SSH_KEY | No | /root/.ssh/id_rsa |
| SSH_KNOWN_HOSTS | No | /root/.ssh/known_hosts |
| BACKUP_RETENTION_DAYS | No | 14 |
| BACKUP_PREFIX | No | pidocker |
| BACKUP_CRON_EXPRESSION | No | 0 2 * * * |

### BACKUP_JOBS

Each line defines one container backup:

`container-name|stop|path1,path2,path3`

- `container-name`: Docker container name
- `stop`: Stop the container during backup (`true` or `false`)
- `paths`: Comma-separated absolute paths

Example:

    BACKUP_JOBS: |
      pihole|true|/opt/stacks/pihole/compose.yaml,/opt/stacks/pihole/.env,/opt/stacks/pihole/etc-pihole
      watchtower|false|

All selected host paths must be mounted into the backup container at their
original absolute paths.

An empty path field means that only Docker metadata is archived.
Paths containing commas are not supported.

### Container shutdown behavior

When `stop` is `true`:

1. The container is stopped.
2. Selected paths and Docker metadata are archived locally.
3. The container is restarted immediately after archive creation.
4. The archive is uploaded to the remote destination.

When `stop` is `false`, the container remains running. Files may change
during backup, so the archive may not represent a fully consistent state.

Containers that were already stopped are not started automatically.

## Backup archives

Each container gets its own archive, for example:

`pidocker-pihole-2026-10-31_02-00-00.tar.gz`

Archives contain:

- Selected host paths
- Docker inspect metadata (`inspect.json`)
- A list of selected paths (`backup-paths.txt`)

## Retention

Old archives matching the configured backup prefix are deleted from the
remote destination after the configured retention period.

## Security considerations

- The Docker socket grants extensive control over the Docker host.
- Docker inspect metadata may contain passwords, tokens and other secrets.
- Backup archives should be stored securely.
- Use SSH keys and strict host key verification.
- Consider encrypting backup archives before storing them remotely.
- Never commit private keys, credentials or backup archives to this repository.

## Limitations

This project currently creates and transfers backups.
A dedicated automated restore function is not included yet.

## License

GNU General Public License v3.0.
See the LICENSE file for details.

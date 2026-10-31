#!/bin/bash

set -Eeuo pipefail

: "${BACKUP_JOBS:?Missing BACKUP_JOBS}"
: "${SSH_HOST:?Missing SSH_HOST}"
: "${SSH_USER:?Missing SSH_USER}"
: "${SSH_REMOTE_PATH:?Missing SSH_REMOTE_PATH}"

SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_rsa}"
SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-/root/.ssh/known_hosts}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_PREFIX="${BACKUP_PREFIX:-pidocker}"

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

SSH_OPTS=(
  -i "$SSH_KEY"
  -p "$SSH_PORT"
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="$SSH_KNOWN_HOSTS"
)

SCP_OPTS=(
  -i "$SSH_KEY"
  -P "$SSH_PORT"
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="$SSH_KNOWN_HOSTS"
)

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Validate all jobs before starting any backup.
validate_jobs() {
  local line container stop mounts extra path
  local -a paths

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")

    [[ -z "$line" || "$line" == \#* ]] && continue

    IFS='|' read -r container stop mounts extra <<< "$line"

    container=$(trim "${container:-}")
    stop=$(trim "${stop:-}")
    mounts=$(trim "${mounts:-}")

    if [[ -z "$container" || -n "${extra:-}" ]]; then
      echo "ERROR: Invalid BACKUP_JOBS entry: $line"
      return 1
    fi

    if [[ "$stop" != "true" && "$stop" != "false" ]]; then
      echo "ERROR: Invalid stop setting for $container: $stop"
      return 1
    fi

    docker inspect "$container" >/dev/null || {
      echo "ERROR: Container not found: $container"
      return 1
    }

    if [[ -n "$mounts" ]]; then
      IFS=',' read -ra paths <<< "$mounts"

      for path in "${paths[@]}"; do
        path=$(trim "$path")

        if [[ "$path" != /* || "$path" == *"/../"* || "$path" == */.. ]]; then
          echo "ERROR: Invalid absolute mount path for $container: $path"
          return 1
        fi

        if [[ ! -e "$path" && ! -L "$path" ]]; then
          echo "ERROR: Mount path not accessible: $path"
          return 1
        fi
      done
    fi

  done <<< "$BACKUP_JOBS"
}

backup_container() (
  local container="$1"
  local stop_container="$2"
  shift 2
  local -a paths=("$@")

  local was_running=false
  local state
  local workdir
  local archive
  local path
  local rc

  local safe_name="${container//[^a-zA-Z0-9_.-]/_}"

  workdir=$(mktemp -d /tmp/backup.XXXXXX)
  archive="/tmp/${BACKUP_PREFIX}-${safe_name}-${TIMESTAMP}.tar.gz"

  cleanup() {
    rc=$?
    trap - EXIT

    if [[ "$was_running" == true ]]; then
      echo "Restarting $container after backup..."

      if ! docker start "$container"; then
        echo "ERROR: Could not restart $container!"
        rc=1
      fi
    fi

    rm -rf "$workdir"
    rm -f "$archive"

    exit "$rc"
  }

  trap cleanup EXIT

  echo
  echo "========================================"
  echo "Backing up: $container"
  echo "========================================"

  state=$(docker inspect --format '{{.State.Running}}' "$container")

  # Save container metadata.
  docker inspect "$container" > "$workdir/inspect.json"

  # Save the selected paths in a manifest.
  printf '%s\n' "${paths[@]}" > "$workdir/backup-paths.txt"

  if [[ "$stop_container" == "true" && "$state" == "true" ]]; then
    echo "Stopping $container..."
    docker stop --timeout 30 "$container"
    was_running=true
  elif [[ "$stop_container" == "false" && "$state" == "true" ]]; then
    echo "Keeping $container running."
    echo "WARNING: Files may change during backup."
  else
    echo "$container is already stopped."
  fi

  # Build tar arguments.
  local -a tar_args
  tar_args=(-czf "$archive" -C /)

  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && continue

    echo "Adding: $path"
    tar_args+=("${path#/}")
  done

  # Include metadata and manifest.
  tar_args+=(-C "$workdir" inspect.json backup-paths.txt)

  echo "Creating archive..."
  tar "${tar_args[@]}"

  echo "Archive created: $archive"

  # Restart immediately after local archive creation.
  if [[ "$was_running" == true ]]; then
    echo "Starting $container..."
    docker start "$container"
    was_running=false
  fi

  # Upload while the container is running.
  echo "Uploading archive..."
  scp "${SCP_OPTS[@]}" \
    "$archive" \
    "${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_PATH}/${archive##*/}"

  echo "Backup completed: $container"
)

echo "Validating backup configuration..."
validate_jobs

# Create remote destination.
ssh "${SSH_OPTS[@]}" \
  "${SSH_USER}@${SSH_HOST}" \
  "mkdir -p '$SSH_REMOTE_PATH'"

# Process all jobs sequentially.
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(trim "$line")

  [[ -z "$line" || "$line" == \#* ]] && continue

  IFS='|' read -r container stop_container mounts <<< "$line"

  container=$(trim "$container")
  stop_container=$(trim "$stop_container")
  mounts=$(trim "${mounts:-}")

  paths=()

  if [[ -n "$mounts" ]]; then
    IFS=',' read -ra paths <<< "$mounts"

    for i in "${!paths[@]}"; do
      paths[$i]=$(trim "${paths[$i]}")
    done
  fi

  backup_container "$container" "$stop_container" "${paths[@]}"

done <<< "$BACKUP_JOBS"

# Remove old backups.
ssh "${SSH_OPTS[@]}" \
  "${SSH_USER}@${SSH_HOST}" \
  "find '$SSH_REMOTE_PATH' -maxdepth 1 -type f \
   -name '${BACKUP_PREFIX}-*.tar.gz' \
   -mmin +$((BACKUP_RETENTION_DAYS * 1440)) -delete"

echo
echo "All backups completed successfully."


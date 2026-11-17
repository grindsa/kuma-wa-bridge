#!/usr/bin/env sh
set -eu

# Weekly config backup for Uptime Kuma + kuma-wa-bridge on the Pi.
# Packs stack dirs, .env files, and Kuma data; optional SCP upload + retention.
# Reports success/failure via kuma-wa-bridge WhatsApp webhook.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
APP_NAME="${APP_NAME:-kuma}"
BACKUP_ROOT="${BACKUP_ROOT:-${TMPDIR:-/tmp}/kuma-backups}"
TMP_ROOT="${TMP_ROOT:-${TMPDIR:-/tmp}}"
LOCAL_KEEP="${LOCAL_KEEP:-}"
REMOTE_KEEP="${REMOTE_KEEP:-}"
REMOTE_TARGET="${REMOTE_TARGET:-}"
REMOTE_DIR="${REMOTE_DIR:-}"
SSH_KEY="${SSH_KEY:-}"
WA_BRIDGE_URL="${WA_BRIDGE_URL:-}"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"
LOG_FILE="${LOG_FILE:-$PROJECT_DIR/logs/backup.log}"
CHECK_CONFIG=0

# host paths (override via env / .env)
STACK_KUMA_WA_BRIDGE="${STACK_KUMA_WA_BRIDGE:-/srv/stacks/kuma-wa-bridge}"
STACK_KUMA="${STACK_KUMA:-/srv/stacks/kuma}"
DATA_KUMA="${DATA_KUMA:-/srv/data/kuma}"

now_utc="$(date -u +%Y%m%d-%H%M%S)"
run_id="${APP_NAME}-backup-${now_utc}"
work_dir="$TMP_ROOT/$run_id"
out_dir="$BACKUP_ROOT"
final_archive="$out_dir/${run_id}.tar.gz"

if [ "${1:-}" = "--check-config" ]; then
  CHECK_CONFIG=1
  shift
fi

if [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--check-config]" >&2
  exit 1
fi

log() {
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

read_env_value() {
  key="$1"
  file="$2"
  awk -v k="$key" '
    {
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) next

      if (line ~ "^" k "[[:space:]]*=") {
        sub("^" k "[[:space:]]*=[[:space:]]*", "", line)
      } else if (line ~ "^" k "[[:space:]]*:") {
        sub("^" k "[[:space:]]*:[[:space:]]*", "", line)
      } else {
        next
      }

      gsub(/^["\047]|["\047]$/, "", line)
      print line
      exit
    }
  ' "$file"
}

notify_backup_result() {
  exit_code="$1"

  if [ -z "$WEBHOOK_TOKEN" ]; then
    log "WA bridge notify skipped (WEBHOOK_TOKEN not set)"
    return 0
  fi

  result="successful"
  if [ "$exit_code" -ne 0 ]; then
    result="failed"
  fi

  wa_msg="$(date +%d.%m.%Y) ${APP_NAME} backup ${result}. run_id:${run_id}"
  payload="$(MSG="$wa_msg" python3 -c 'import json, os; print(json.dumps({"msg": os.environ["MSG"]}))')"

  set +e
  wa_output="$(curl -fsS -m 60 -X POST "$WA_BRIDGE_URL" \
    -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1)"
  wa_status=$?
  set -e

  if [ "$wa_status" -eq 0 ]; then
    log "WA bridge notification sent"
  else
    log "WARN: WA bridge notification failed"
    if [ -n "$wa_output" ]; then
      log "WARN: WA bridge output: $wa_output"
    fi
  fi
}

finalize() {
  exit_code="$1"
  if [ "$CHECK_CONFIG" -eq 0 ]; then
    notify_backup_result "$exit_code"
  fi
  rm -rf "$work_dir"
}
trap 'finalize $?' EXIT

cd "$PROJECT_DIR"

env_file="$PROJECT_DIR/.env"
if [ ! -f "$env_file" ]; then
  echo "ERROR: missing $PROJECT_DIR/.env" >&2
  exit 1
fi

load_env_key() {
  var_name="$1"
  eval "current=\${$var_name:-}"
  if [ -z "$current" ]; then
    value="$(read_env_value "$var_name" "$env_file")"
    if [ -n "$value" ]; then
      eval "$var_name=\"\$value\""
    fi
  fi
}

load_env_key BACKUP_ROOT
load_env_key TMP_ROOT
load_env_key REMOTE_TARGET
load_env_key REMOTE_DIR
load_env_key SSH_KEY
load_env_key LOCAL_KEEP
load_env_key REMOTE_KEEP
load_env_key STACK_KUMA_WA_BRIDGE
load_env_key STACK_KUMA
load_env_key DATA_KUMA
load_env_key LOG_FILE
load_env_key WA_BRIDGE_URL
load_env_key WEBHOOK_TOKEN
load_env_key HOST_PORT

LOCAL_KEEP="${LOCAL_KEEP:-4}"
REMOTE_KEEP="${REMOTE_KEEP:-12}"
BACKUP_ROOT="${BACKUP_ROOT:-${TMPDIR:-/tmp}/kuma-backups}"
TMP_ROOT="${TMP_ROOT:-${TMPDIR:-/tmp}}"
REMOTE_DIR="${REMOTE_DIR:-/public/Backups/pi-dns/kuma}"
LOG_FILE="${LOG_FILE:-$PROJECT_DIR/logs/backup.log}"
HOST_PORT="${HOST_PORT:-8089}"
WA_BRIDGE_URL="${WA_BRIDGE_URL:-http://127.0.0.1:${HOST_PORT}/webhook}"

out_dir="$BACKUP_ROOT"
work_dir="$TMP_ROOT/$run_id"
final_archive="$out_dir/${run_id}.tar.gz"

REMOTE_DIR_NORM="${REMOTE_DIR%/}"
if [ -z "$REMOTE_DIR_NORM" ]; then
  REMOTE_DIR_NORM="/"
fi

ssh_opts=""
if [ -n "$SSH_KEY" ]; then
  if [ ! -f "$SSH_KEY" ]; then
    log "ERROR: SSH_KEY file not found: $SSH_KEY"
    exit 1
  fi
  ssh_opts="-i $SSH_KEY"
fi

if [ "$CHECK_CONFIG" -eq 1 ]; then
  if [ -n "$REMOTE_TARGET" ]; then
    remote_upload="enabled"
  else
    remote_upload="disabled"
  fi
  if [ -n "$WEBHOOK_TOKEN" ]; then
    wa_notify="enabled"
  else
    wa_notify="disabled"
  fi

  echo "backup config check"
  echo "project_dir=$PROJECT_DIR"
  echo "env_file=$env_file"
  echo "app_name=$APP_NAME"
  echo "backup_root=$BACKUP_ROOT"
  echo "tmp_root=$TMP_ROOT"
  echo "local_keep=$LOCAL_KEEP"
  echo "remote_keep=$REMOTE_KEEP"
  echo "remote_target=${REMOTE_TARGET:-<empty>}"
  echo "remote_dir=$REMOTE_DIR_NORM"
  echo "ssh_key=${SSH_KEY:-<empty>}"
  echo "stack_kuma_wa_bridge=$STACK_KUMA_WA_BRIDGE"
  echo "stack_kuma=$STACK_KUMA"
  echo "data_kuma=$DATA_KUMA"
  echo "wa_bridge_url=$WA_BRIDGE_URL"
  echo "webhook_token=$([ -n "$WEBHOOK_TOKEN" ] && echo set || echo empty)"
  echo "remote_upload=$remote_upload"
  echo "wa_notification=$wa_notify"
  echo "result=ok"
  exit 0
fi

mkdir -p "$out_dir" "$(dirname "$LOG_FILE")" "$work_dir/trees"

log "Starting backup run $run_id"

copy_tree() {
  label="$1"
  src="$2"
  dest="$work_dir/trees/$label"

  if [ ! -e "$src" ]; then
    log "WARN: missing $src (skipping $label)"
    return 0
  fi

  mkdir -p "$dest"
  # Preserve relative layout; include hidden files such as .env
  tar -C "$src" -cf - . | tar -C "$dest" -xf -
  log "Included $label from $src"
}

copy_tree "stacks-kuma-wa-bridge" "$STACK_KUMA_WA_BRIDGE"
copy_tree "stacks-kuma" "$STACK_KUMA"
copy_tree "data-kuma" "$DATA_KUMA"

meta_txt="$work_dir/meta.txt"
cat > "$meta_txt" <<EOF
run_id=$run_id
timestamp_utc=$now_utc
project_dir=$PROJECT_DIR
stack_kuma_wa_bridge=$STACK_KUMA_WA_BRIDGE
stack_kuma=$STACK_KUMA
data_kuma=$DATA_KUMA
hostname=$(hostname 2>/dev/null || echo unknown)
EOF

log "Writing checksum manifest"
(
  cd "$work_dir"
  find trees -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum > manifest.sha256
  sha256sum meta.txt >> manifest.sha256
)

log "Creating final archive $final_archive"
tar -czf "$final_archive" -C "$work_dir" trees meta.txt manifest.sha256

log "Pruning local backups (keep=$LOCAL_KEEP)"
# shellcheck disable=SC2086
ls -1dt "$out_dir"/${APP_NAME}-backup-*.tar.gz 2>/dev/null | awk "NR>$LOCAL_KEEP" | xargs -r rm -f

if [ -n "$REMOTE_TARGET" ]; then
  remote_dir_use="$REMOTE_DIR_NORM"
  remote_file="$remote_dir_use/$(basename "$final_archive")"
  log "Backup server: $REMOTE_TARGET"
  log "Remote backup directory: $remote_dir_use"
  log "Uploading backup to $remote_file"
  # shellcheck disable=SC2086
  echo "Uploading backup $final_archive to $REMOTE_TARGET:$remote_file"
  # shellcheck disable=SC2086
  scp $ssh_opts "$final_archive" "$REMOTE_TARGET:$remote_file"

  log "Pruning remote backups (keep=$REMOTE_KEEP)"
  # shellcheck disable=SC2086
  ssh $ssh_opts "$REMOTE_TARGET" "ls -1dt '$remote_dir_use'/${APP_NAME}-backup-*.tar.gz 2>/dev/null | awk 'NR>$REMOTE_KEEP' | xargs -r rm -f"
else
  log "REMOTE_TARGET not set; skipping remote upload"
fi

log "Backup complete: $final_archive"

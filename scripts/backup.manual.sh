#!/usr/bin/env sh
set -eu

# Manual backup wrapper (same knobs as scripts/backup.cron.example).
# Configure REMOTE_* / KEEP values in .env, then:
#   ./scripts/backup.manual.sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"

cd "$PROJECT_DIR"
PROJECT_DIR="$PROJECT_DIR" ./scripts/backup.sh "$@"

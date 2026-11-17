#!/usr/bin/env bash
# Pull latest commits from GitHub, rebuild the image, and restart kuma-wa-bridge.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

if [[ ! -f docker-compose.yml ]]; then
  echo "error: docker-compose.yml not found in $STACK_DIR" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "error: .env missing in $STACK_DIR (copy from .env.example first)" >&2
  exit 1
fi

if [[ ! -d .git ]]; then
  echo "error: $STACK_DIR is not a git checkout; clone the repo to use deploy.sh" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has local changes; commit/stash them before upgrading" >&2
  git status --short
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "==> fetching origin/$BRANCH"
git fetch origin

BEFORE="$(git rev-parse HEAD)"
git pull --ff-only origin "$BRANCH"
AFTER="$(git rev-parse HEAD)"

if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "==> already up to date ($AFTER)"
else
  echo "==> updated $BEFORE -> $AFTER"
  git --no-pager log --oneline "${BEFORE}..${AFTER}"
fi

COMPOSE=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
fi

# Prefer sudo when the current user cannot talk to the daemon.
if ! docker info >/dev/null 2>&1; then
  COMPOSE=(sudo "${COMPOSE[@]}")
fi

echo "==> rebuilding image locally and recreating stack"
"${COMPOSE[@]}" up -d --build --remove-orphans

echo "==> status"
"${COMPOSE[@]}" ps
echo "==> health"
curl -fsS "http://127.0.0.1:${HOST_PORT:-8089}/health" || \
  curl -fsS "http://127.0.0.1:8089/health" || \
  echo "warning: health check failed (is the publish port reachable?)"
echo
echo "deploy done."

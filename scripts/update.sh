#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_dir}"

if [[ ! -f .env ]]; then
  printf 'Missing %s/.env.\n' "${project_dir}" >&2
  exit 1
fi

password="$(awk -F= '$1 == "LAVALINK_SERVER_PASSWORD" { sub(/^[^=]*=/, ""); print; exit }' .env)"
if [[ ! "${password}" =~ ^[[:xdigit:]]{64}$ ]]; then
  printf 'LAVALINK_SERVER_PASSWORD must be a 64-character hex secret (generate with: openssl rand -hex 32).\n' >&2
  exit 1
fi

docker compose config --quiet
docker compose pull lavalink
docker compose up -d lavalink

for attempt in {1..60}; do
  if bash scripts/healthcheck.sh >/dev/null 2>&1; then
    printf 'Update completed; Lavalink is responding to authenticated health checks.\n'
    exit 0
  fi
  sleep 3
done

printf 'Updated Lavalink did not become healthy within 180 seconds. Recent logs follow:\n' >&2
docker compose logs --tail=100 lavalink >&2
exit 1

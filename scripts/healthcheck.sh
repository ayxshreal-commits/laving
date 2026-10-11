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

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required; install it with: sudo apt-get install curl\n' >&2
  exit 1
fi

if printf 'header = "Authorization: %s"\n' "${password}" \
  | curl --config - --fail --silent --show-error --max-time 8 \
    http://127.0.0.1:2333/v4/info >/dev/null; then
  printf 'Lavalink REST API is reachable at 127.0.0.1:2333 and authentication succeeded.\n'
else
  printf 'Lavalink health check failed. Inspect logs with: docker compose logs --tail=100 lavalink\n' >&2
  exit 1
fi

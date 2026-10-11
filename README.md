# Self-hosted Lavalink v4 on AWS EC2

Private-by-default, single-node Lavalink deployment for an existing Discord music bot. This repository contains the Lavalink service only; it does not contain a Discord bot or implement bot commands/player logic.

## Verified upstream components

Versions checked against upstream release records and Maven metadata on 2026-10-11:

- Lavalink latest stable release: **4.2.2**; the official project requires Java 17 or newer.
- Official container: `ghcr.io/lavalink-devs/lavalink:4-alpine`, the upstream-documented Alpine/Java 17 v4 image tag.
- YouTube source plugin: **1.18.2**, `dev.lavalink.youtube:youtube-plugin`.
- LavaSrc: **4.8.3**, `com.github.topi314.lavasrc:lavasrc-plugin`.

The server image tag follows the upstream v4 image channel rather than an immutable digest; pulling it during a deliberate update can change the image. Pin `LAVALINK_IMAGE` to a reviewed digest in `.env` when immutable deployments are required. Plugin coordinates and versions are pinned in [application.yml](./application.yml).

Lavalink's built-in YouTube manager is disabled in favor of the maintained YouTube source plugin. LavaSrc resolves Spotify URLs/search into track metadata and uses configured providers (YouTube by default here) to find playable audio. Spotify does **not** provide playable audio through this setup. Providers may change, rate-limit, or restrict requests, so playback cannot be guaranteed for every track.

## Quick start

Requirements: Docker Engine, Docker Compose v2, and a protected `.env` file. On a fresh Ubuntu EC2 instance, follow the complete [AWS EC2 runbook](./docs/aws-ec2.md).

```bash
cp .env.example .env
openssl rand -hex 32
# Put the generated value in LAVALINK_SERVER_PASSWORD in .env.
chmod 600 .env
sudo ./scripts/deploy.sh
sudo ./scripts/healthcheck.sh
```

The only published host port is `127.0.0.1:2333`; there is no public Lavalink port. The service is also reachable by trusted containers attached to the Docker network `lavalink-private`, using hostname `lavalink` and port `2333`. Add no EC2 security-group ingress rule for port 2333.

Optional Spotify credentials (`SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET`) belong in `.env`, never in source control. They enable Spotify search features supported by LavaSrc; Spotify URL metadata may still be subject to changes or provider availability.

## Runtime behavior

- REST API and WebSocket API are served on port 2333 and require the configured Lavalink password.
- Lavalink filters (including equalizer, timescale, tremolo, vibrato, distortion, rotation, channel mix, and low-pass) are enabled.
- HTTP and local-file sources are disabled to avoid exposing the node to untrusted URLs/filesystem access.
- The service restarts after process or host failure. Active players and queues are in memory; a bot must reconnect and restore its own state.
- Logs are available with `sudo docker compose logs -f lavalink`. Docker's `json-file` driver wraps each Lavalink log line with timestamp and stream metadata; Lavalink's message body remains categorized text. Request/header/payload logging is disabled to avoid recording sensitive request data, and both Docker and Lavalink log retention are bounded.
- The Compose resource cap is 1.75 CPU and 3 GiB memory; Java heap is capped at 2 GiB.

## Capacity guidance

Start with 2 vCPU and 4 GiB RAM (for example, a burstable `t3a.medium`) for light/moderate concurrency, not as a guarantee for a particular guild count. Measure active voice players, source resolution rates, CPU credits/CPU utilization, memory, and playback failures at peak. Use a larger non-burstable instance when encoding load is sustained. Scale up memory and CPU limits together; use additional Lavalink nodes with bot-side node selection/failover when single-host capacity or availability is insufficient. One EC2 instance is a single point of failure.

## Bot connectivity and event handling

The workspace was empty before this deployment was added, so no existing Discord.js version, Lavalink client library, environment naming, or playback implementation could be identified. No bot behavior or commands have been changed.

- Bot container on the same Docker host: attach it to `lavalink-private`; use `lavalink:2333`.
- Bot process on the EC2 host: use `127.0.0.1:2333`.
- Bot on another host: use private VPN connectivity. If that is not available, front Lavalink with a TLS reverse proxy that supports WebSocket upgrades, enforce strong authentication and source restrictions, and keep the Lavalink port itself private.

The bot's Lavalink v4 client must authenticate with the same password, handle track-end/stuck/exception events, reconnect after node restarts, and restore its own queues. For client options, see the official [Lavalink client list](https://lavalink.dev/clients).

## Maintenance

```bash
sudo ./scripts/update.sh
sudo docker compose logs --tail=150 lavalink
```

Review [docs/aws-ec2.md](./docs/aws-ec2.md) for AWS security-group setup, Docker installation, private connectivity, sizing, backups, health checks, update/rollback guidance, and troubleshooting.

## Upstream references

- [Lavalink documentation](https://lavalink.dev/)
- [Lavalink latest release](https://github.com/lavalink-devs/Lavalink/releases/latest)
- [Official Lavalink Docker guide](https://lavalink.dev/getting-started/docker)
- [Lavalink plugins guide](https://lavalink.dev/plugins.html)
- [YouTube source plugin](https://github.com/lavalink-devs/youtube-source)
- [LavaSrc](https://github.com/topi314/LavaSrc)

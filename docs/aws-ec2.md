# AWS EC2 installation

This runbook deploys the Lavalink service on one Ubuntu EC2 instance. The Lavalink REST/WebSocket port is not open to the internet: Compose publishes it only on the instance loopback interface and makes it available to trusted containers on a Docker bridge network.

## 1. Create the EC2 instance

- Use Ubuntu Server 24.04 LTS, x86_64, and an instance with at least 2 vCPU and 4 GiB RAM. `t3a.medium` is a reasonable low-cost starting point for light/moderate playback; it is burstable, so monitor CPU credit balance and CPU utilization. For sustained encoding load, test a non-burstable 2-vCPU instance such as `c7a.large`, or increase instance size based on measurements.
- Configure an encrypted 20 GiB gp3 root volume as a starting point. Increase it if logs, other services, or operating-system updates need more room.
- Attach a security group that allows inbound TCP 22 only from your trusted public IP as `/32`. Do not add inbound TCP 2333. Keep outbound access available for Discord, source providers, and package/image updates.
- Require IMDSv2. An instance profile is not required for Lavalink; optionally attach `AmazonSSMManagedInstanceCore` and use Systems Manager Session Manager instead of exposing SSH.
- Do not install the Discord bot on this host unless the instance is sized for both workloads. Store no bot token in this project's `.env`.

Guild count is not a capacity measure by itself. Active voice players and the source/encoding workload determine CPU and memory demand. The Compose configuration limits Lavalink to 1.75 CPU and 3 GiB RAM with a 2 GiB Java heap. Watch `docker stats`, EC2 CPU, memory, CPU credits (for burstable instances), and playback error rates during representative peak traffic. Raise the instance and container limits together if memory or CPU remains constrained; add nodes and configure client-side node selection/failover when one instance cannot meet availability or capacity targets. A single EC2 host remains a single point of failure.

## 2. Install Docker Engine and Compose

Connect using SSH restricted to your trusted IP or Session Manager. Copy this project onto the instance (or clone the repository after you have pushed it), then run:

```bash
cd /path/to/lava
sudo bash scripts/install-docker.sh
```

The installer configures Docker's official Ubuntu apt repository and installs Docker Engine and the Compose plugin. Membership in the `docker` group grants root-equivalent access; prefer running the provided commands with `sudo` unless you deliberately accept that privilege.

## 3. Configure the secret and deploy

```bash
cd /path/to/lava
cp .env.example .env
openssl rand -hex 32
# Paste the generated value into LAVALINK_SERVER_PASSWORD in .env.
${EDITOR:-nano} .env
chmod 600 .env
sudo ./scripts/deploy.sh
sudo ./scripts/healthcheck.sh
```

If you use Spotify search, create an application in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard/) and add its client ID and client secret to `.env`. Keep `.env` out of source control and restrict filesystem access. The Spotify credentials are only for metadata/search resolution; audio is matched through YouTube in the provided configuration, not streamed from Spotify. Leave those values blank if Spotify is not needed.

The host-side health check sends the Lavalink password over loopback to `GET /v4/info` and does not publish that credential in the curl command line. Inspect startup and plugin resolution with:

```bash
sudo docker compose logs --tail=150 lavalink
sudo docker stats lavalink
```

## 4. Connect the Discord bot

- **Bot in a Docker container on this instance:** attach the bot service to the external Compose network named `lavalink-private`; configure its Lavalink host as `lavalink` (the service name), port `2333`, and password from the same protected secret store. Do not put the secret in an image or source file. A separately managed bot Compose project can declare `networks: { lavalink-private: { external: true } }` and attach that network to its bot service.
- **Bot process on the EC2 host:** connect to `127.0.0.1:2333`.
- **Bot on another host:** prefer a private network such as a VPN and permit only that private source in the EC2 security group. Do not expose bare TCP 2333 to the public internet. If private connectivity is unavailable, use a TLS reverse proxy with WebSocket upgrade support, strong Lavalink authentication, and source-IP restrictions; expose only the proxy's TLS port and keep 2333 private. Lavalink itself is configured here for HTTP/WebSocket, not native TLS.

The repository contains no Discord bot source, so no Discord.js version, Lavalink client library, commands, player code, or event handlers could be inspected or changed. Use a Lavalink v4-compatible client. The bot should handle track-end, track-stuck, and track-exception events, reconnect after node restarts, and restore queues/player state itself: Lavalink player state is in memory and is not durable across a process or instance restart.

## 5. Updates and recovery

Review upstream release notes before running:

```bash
sudo ./scripts/update.sh
sudo docker compose logs --tail=150 lavalink
```

The configured official `4-alpine` tag is the upstream-documented moving Lavalink v4 image tag; an explicit pull/redeploy picks up the image published for that tag. Plugin dependencies are pinned to releases in `application.yml`. For strict repeatability, set `LAVALINK_IMAGE` in `.env` to a reviewed immutable image digest and deliberately update it. Keep a tested prior digest for rollback.

Configuration is in `application.yml` and `.env`; player queues and active playback are not persisted. Back up the configuration and secrets using a private, encrypted method. Docker's restart policy restarts Lavalink after process/host reboot, while the bot must reconnect and restore its own queues. Keep the instance patched and ensure the Docker service is enabled at boot.

## Troubleshooting

- **Container exits during startup:** inspect `sudo docker compose logs --tail=200 lavalink`. Check plugin downloads and ensure outbound HTTPS works.
- **401/403 from the bot or health check:** ensure the bot and `.env` use the same `LAVALINK_SERVER_PASSWORD`; recreate the service after changing `.env` with `sudo docker compose up -d --force-recreate lavalink`.
- **Host bot cannot connect:** use `127.0.0.1:2333`, not the EC2 public address. Confirm the container is running and `sudo ./scripts/healthcheck.sh` passes.
- **Containerized bot cannot connect:** confirm it is attached to the `lavalink-private` network and uses `lavalink:2333`; Docker network names are case-sensitive.
- **No audio / search failures:** provider APIs can change, rate-limit, or block requests. Check Lavalink and plugin logs; try a different supported query/source, and do not assume every YouTube item or Spotify entry is playable.
- **Out of memory or repeated pauses:** compare container/host memory and CPU metrics with active player counts. Increase EC2 size and Java/container limits together; do not set the JVM heap equal to all host memory.
- **Disk/log growth:** application file logs roll at 20 MiB with seven retained files, and Docker's JSON log driver is capped at three 10 MiB files. Check remaining EBS space and avoid placing unrelated data on the instance.

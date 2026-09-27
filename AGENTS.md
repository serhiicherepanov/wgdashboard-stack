# AGENTS.md — wgdashboard-stack

Guidance for AI agents and humans working in this repo.

## What this is

A standalone Docker Compose stack: WireGuard VPN managed by
[WGDashboard](https://github.com/WGDashboard/WGDashboard), fronted by Traefik.
It is a sibling of `../wireguard-ui-stack` (same layout, same `.env` conventions, same Traefik
overlay) but uses the official WGDashboard image, which bundles WireGuard, AmneziaWG and the
web UI in one container. Upstream docker docs:
<https://github.com/WGDashboard/WGDashboard/blob/main/docker/README.md>.

## Files

- `docker-compose.yaml` — base stack, no reverse proxy. Always required.
- `docker-compose.traefik.yaml` — optional overlay adding Traefik and the routing labels.
  Enabled via `COMPOSE_FILE=docker-compose.yaml:docker-compose.traefik.yaml` in `.env`.
- `.env` / `.env.example` — all configuration.
- `scripts/migrate-from-wireguard-ui.sh` — one-shot import of `wg0.conf` from
  `../wireguard-ui-stack` (rewrites peer name comments into WGDashboard's `#Name# =` form,
  which must sit right after `[Peer]`). Run before the first `up`; refuses to overwrite.

Services:

| Service       | Image                              | File    | Role |
|---------------|------------------------------------|---------|------|
| `wgdashboard` | `ghcr.io/wgdashboard/wgdashboard`  | base    | WireGuard interface(s) **and** the web UI (gunicorn on 10086) in one container. Publishes `$WG_PORT/udp` and the UI on `$WGD_BIND:$WGD_PORT` (default localhost only). |
| `traefik`     | `traefik:v3.6`                     | overlay | Reverse proxy on host network, :80 → :443 redirect, TLS via Let's Encrypt (HTTP-01 challenge on the `unsecure` entrypoint). Exposes its dashboard under `/traefik/dashboard/` behind basic auth. |

## Non-obvious design decisions — do not "fix" these

- **Single container.** Unlike `../wireguard-ui-stack` there is no separate VPN container,
  no `network_mode: service:` trick and no ofelia. The image's `entrypoint.sh` generates
  `wg0.conf` on first boot (only if `/etc/wireguard` is empty), writes `wg-dashboard.ini`
  from env vars and starts gunicorn. Traefik labels therefore live directly on `wgdashboard`.
- **No sync/route script.** WGDashboard applies peer changes live (`wg set` + `wg-quick save`)
  and can `wg-quick down/up` an interface from the UI, so the `wg-sync.sh` from the sibling
  stack is not needed. Known gap, same as upstream: a *server-side* peer whose AllowedIPs
  contains an extra subnet gets no kernel route until the interface is toggled in the UI.
  If that ever matters, port the route-adding part of `../wireguard-ui-stack/scripts/wg-sync.sh`.
- **`WG_PORT` is not pushed into the container.** The image has no env var for the WireGuard
  port; `ListenPort` lives in `wgdashboard/conf/wg0.conf` (template default 51820). `.env`
  only controls the published port, so keep the two in sync by hand.
- **Env var names are lowercase** (`public_ip`, `global_dns`, `username`, `password`,
  `wg_autostart`, `enable_totp`) because that is what `entrypoint.sh` reads. `TZ` is uppercase
  (Alpine tzdata); the upstream table lists `tz` but the entrypoint never reads it.
- **`public_ip=${WG_HOST}`.** Despite the name it accepts a hostname; it becomes
  `remote_endpoint` in `wg-dashboard.ini`, i.e. the `Endpoint` in generated client configs.
  Leaving it empty makes the container call `ifconfig.me` on every start.
- **`dynamic_config` is left at the image default (`true`)**, so every non-empty env var is
  re-applied on each container start and overrides what was changed in the UI. That is why
  `WGD_USERNAME`/`WGD_PASSWORD`/`WGD_ENABLE_TOTP` default to empty in `.env.example`.
- **The container-internal UI port stays 10086.** `wgd_port` is not set; `$WGD_PORT` only
  changes the host-side mapping, and the Traefik service label points at 10086.
- **`sysctls` are set explicitly** (`ip_forward`, `src_valid_mark`) even though the upstream
  compose omits them: peer-to-LAN forwarding inside the container netns depends on them.
- **`SYS_MODULE` is commented out.** Modern kernels ship the module; add it only if
  `wg-quick up` fails with "Unknown device type".
- **Traefik uses `network_mode: host`.** That is why there is no `ports:` section on it. The host
  can reach the compose bridge network, so the docker provider still works. Do not add `ports:`.
- Bind mounts instead of the named volumes from the upstream example, so state is next to
  the compose file like in the sibling stack.
- The `dynamic/` file provider from the original project was intentionally left out. Everything
  is configured via docker labels.

## Configuration

All configuration is in `.env` (gitignored). `.env.example` lists every variable.

- `WG_HOST` — client-config endpoint (`public_ip`) and the Traefik `Host()` rule.
- `WG_PORT` — published UDP port. Must equal `ListenPort` in `wgdashboard/conf/wg0.conf`.
- `WGD_BIND` / `WGD_PORT` — where the UI is published without Traefik. Do not set
  `WGD_BIND=0.0.0.0` on a public host when the traefik overlay is active.
- `WGD_GLOBAL_DNS` — DNS pushed to peers (`peer_global_dns`).
- `WGD_AUTOSTART` — interface name(s) started with the container.
- `WGD_USERNAME` / `WGD_PASSWORD` / `WGD_ENABLE_TOTP` — initial admin account, see above.
- `ACME_EMAIL` — Let's Encrypt account email. Certificates are issued via HTTP-01, so port 80
  must be publicly reachable and `WG_HOST` must resolve to this host. Wildcards are not possible
  with HTTP-01; switch to a DNS challenge if that is ever needed.
- `TRAEFIK_DASHBOARD_USERS` — htpasswd line. If using bcrypt/md5, escape `$` as `$$`.
- `WGD_CPU_LIMIT` / `WGD_MEM_LIMIT` / `WGD_MEM_RESERVE` and the `TRAEFIK_*` equivalents —
  `deploy.resources` for each container. Upstream gives no sizing guidance; the defaults
  (1 CPU / 512M for WGDashboard, 0.5 CPU / 256M for Traefik) are generous for a small VPN.
  Raise `WGD_MEM_LIMIT` first if the container gets OOM-killed with many peers.

Email/SMTP and external database settings from the upstream table are not wired; add them to
both compose `environment` and `.env.example` if needed.

## Migrating from ../wireguard-ui-stack

`wg0.conf` carries everything the kernel needs (server key, port, address, peers, PSKs,
AllowedIPs), so clients keep working unchanged after `scripts/migrate-from-wireguard-ui.sh`
as long as `WG_PORT` stays the same. What does not carry over: client private keys (paste
into each peer in the dashboard to enable QR/config download), dashboard users (first-run
wizard), the Telegram bot (no equivalent), and the default client AllowedIPs
(`WGUI_DEFAULT_CLIENT_ALLOWED_IPS` → Settings → Peer default settings → Endpoint Allowed IPs).

## State on disk (all gitignored)

- `wgdashboard/conf/` — `wg0.conf` including the server private key, plus extra interfaces.
  Losing this means all peers must be re-issued.
- `wgdashboard/aconf/` — AmneziaWG interfaces.
- `wgdashboard/data/` — `wg-dashboard.ini`, `db/` (sqlite), `wg-dashboard-oidc-providers.json`.
- `letsencrypt/acme.json` — certificates. Must be mode `600` or Traefik refuses to start.

`wgdashboard/` and `letsencrypt/` each carry their own `.gitignore` (`*` + `!.gitignore`)
so the directories exist after a clone while their contents stay untracked. Do not add a
placeholder file under `wgdashboard/conf/`: the image generates `wg0.conf` only when that
directory is empty.

## Common tasks

```
docker compose -f docker-compose.yaml config -q   # base only
docker compose config -q                          # base + traefik (COMPOSE_FILE from .env)
docker compose up -d
docker compose logs -f traefik wgdashboard
docker compose exec wgdashboard wg show
```

## Rules for agents

- After touching either compose file, validate both variants:
  `docker compose -f docker-compose.yaml config -q` and `docker compose config -q`.
- Never commit `.env`, `wgdashboard/`, or `letsencrypt/`. Never print secret values from `.env`
  into chat, logs, or commit messages.
- Do not change service names, `container_name`s, or volume paths without a migration note:
  the dashboard DB and the WireGuard config are path-bound.
- Keep new settings in `.env` + `.env.example`, not hardcoded in compose.
- This stack, `../wireguard-ui-stack` and `../docker-compose-openvpn-admin` all run Traefik on
  the host network. Only one of them can run on a machine at a time.

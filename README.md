# WGDashboard + Traefik

Two compose files:

- `docker-compose.yaml` — base: `ghcr.io/wgdashboard/wgdashboard`. One container that runs
  both the WireGuard interface(s) and the web UI. UI is bound to `$WGD_BIND:$WGD_PORT`
  (default `127.0.0.1:10086`).
- `docker-compose.traefik.yaml` — optional overlay: Traefik on host network, :80/:443,
  Let's Encrypt via HTTP-01 challenge, routes `https://$WG_HOST` to the dashboard.

Sibling of `../wireguard-ui-stack` (linuxserver/wireguard + wireguard-ui). Same layout and
`.env` conventions; different UI.

## Run

```
cp .env.example .env   # fill in values
docker compose up -d   # COMPOSE_FILE in .env includes the traefik overlay
```

Without Traefik: drop `docker-compose.traefik.yaml` from `COMPOSE_FILE` in `.env`, or run
`docker compose -f docker-compose.yaml up -d`.

- Dashboard: `https://$WG_HOST` (with traefik) or `http://127.0.0.1:10086` (without)
- Traefik dashboard: `https://$WG_HOST/traefik/dashboard/` (basic auth from `TRAEFIK_DASHBOARD_USERS`)
- WireGuard: `$WG_HOST:$WG_PORT/udp`

## First boot

On the first start the image generates `wgdashboard/conf/wg0.conf` from its template:
`Address = 10.0.0.1/24`, `ListenPort = 51820`, NAT via `PostUp`/`PreDown` iptables rules,
`SaveConfig = true`. To change the subnet or port, edit the raw config in the dashboard
(Configuration Settings → Edit Raw Configuration File) and keep `WG_PORT` in `.env` in sync.

If `WGD_USERNAME`/`WGD_PASSWORD` are empty the first visit opens the welcome wizard to create
the admin account. If set, they are applied on every container start.

Peers, AllowedIPs and interface settings are applied live by the dashboard; there is no cron
or sync script in this stack. Toggling the interface off/on in the UI is equivalent to
`wg-quick down/up`.

HTTP-01 requires port 80 to be reachable from the internet on this host and `$WG_HOST` to
resolve to it. No DNS provider credentials are needed.

## Migrating from wireguard-ui-stack

```
docker compose -f ../wireguard-ui-stack/docker-compose.yaml down   # frees :80/:443/:$WG_PORT
sh scripts/migrate-from-wireguard-ui.sh                            # copies + converts wg0.conf
docker compose up -d
```

Server key, port, subnet, peers and PSKs are kept, so existing client configs keep working.
Peer names are imported; client private keys, dashboard users and the Telegram bot are not.

## State

- `wgdashboard/conf` — `wg0.conf` (server key inside) and any extra interfaces
- `wgdashboard/aconf` — AmneziaWG interfaces, if any
- `wgdashboard/data` — `wg-dashboard.ini`, sqlite DB (`db/`), OIDC providers
- `letsencrypt/acme.json` — certificates (must be mode 600)

All of these are gitignored.

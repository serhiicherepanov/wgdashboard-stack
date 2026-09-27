#!/bin/sh
# One-shot migration of the WireGuard server config from ../wireguard-ui-stack.
#
# Copies wg_confs/wg0.conf into wgdashboard/conf/ and rewrites the wireguard-ui peer
# comments ("# Name:  foo") into the form WGDashboard imports ("#Name# = foo").
# Server private key, ListenPort, Address, peers, preshared keys and AllowedIPs are kept
# as-is, so existing client configs keep working without re-issuing.
#
# Not migrated (WGDashboard has no import for them):
#   - client private keys  -> paste per peer in the dashboard if you want QR/config download
#   - dashboard users      -> create via the first-run wizard
#   - Telegram bot         -> no equivalent
#
# Usage (from wgdashboard-stack, BEFORE the first `docker compose up`):
#   sh scripts/migrate-from-wireguard-ui.sh [path/to/wireguard-ui-stack]
set -eu

SRC_STACK=${1:-../wireguard-ui-stack}
SRC="$SRC_STACK/wireguard/config/wg_confs/wg0.conf"
DST_DIR=wgdashboard/conf
DST="$DST_DIR/wg0.conf"

[ -f "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }
if [ -e "$DST" ]; then
  echo "refusing to overwrite existing $DST" >&2
  exit 1
fi
if docker compose ps -q wgdashboard 2>/dev/null | grep -q .; then
  echo "wgdashboard container exists; stop/remove it first (docker compose down)" >&2
  exit 1
fi

mkdir -p "$DST_DIR"
umask 077
# wireguard-ui puts "# Name:  foo" BEFORE [Peer]; WGDashboard only reads "#Name# = foo"
# AFTER [Peer]. Carry the name over and drop wireguard-ui's bookkeeping comments.
awk '
  /^# Name:[[:space:]]*/ { sub(/^# Name:[[:space:]]*/, ""); name=$0; next }
  /^# (ID|Email|Telegram|Created at|Update at|Address updated at|Private Key updated at):/ { next }
  /^# (This file was generated using wireguard-ui|Please don.t modify it manually)/ { next }
  /^\[Peer\]$/ { print; if (name != "") print "#Name# = " name; name=""; next }
  { print }
' "$SRC" > "$DST"
chmod 600 "$DST"

echo "wrote $DST:"
printf '  peers:      %s\n' "$(grep -c '^\[Peer\]' "$DST")"
printf '  ListenPort: %s\n' "$(sed -nE 's/^ListenPort\s*=\s*//p' "$DST")"
echo "make sure WG_PORT in .env equals ListenPort, then: docker compose up -d"

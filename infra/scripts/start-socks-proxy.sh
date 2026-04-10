#!/usr/bin/env bash
# start-socks-proxy.sh — Start a SOCKS5 proxy inside the dev container so that
# Windows applications (browser, etc.) can route traffic through the VPN tunnel.
#
# VS Code Dev Containers automatically forward container ports to localhost on
# the Windows host, so configure your browser to use:
#   SOCKS5  localhost:1080
#
# Usage:
#   bash ./infra/scripts/start-socks-proxy.sh          # starts on default port 1080
#   SOCKS_PORT=8080 bash ./infra/scripts/start-socks-proxy.sh
set -euo pipefail

SOCKS_PORT="${SOCKS_PORT:-1080}"

# ── install microsocks if not present ─────────────────────────────────────────
if ! command -v microsocks >/dev/null 2>&1; then
  echo "Installing microsocks..."
  sudo apt-get update -y -qq
  sudo apt-get install -y -qq microsocks
fi

# ── kill any previous instance ────────────────────────────────────────────────
if pgrep -x microsocks >/dev/null 2>&1; then
  echo "Stopping existing microsocks instance..."
  sudo pkill -x microsocks || true
  sleep 1
fi

# ── start proxy ───────────────────────────────────────────────────────────────
echo "Starting SOCKS5 proxy on 0.0.0.0:${SOCKS_PORT} ..."
sudo microsocks -p "${SOCKS_PORT}" &
PROXY_PID=$!
sleep 1

if ! kill -0 "${PROXY_PID}" 2>/dev/null; then
  echo "ERROR: microsocks failed to start." >&2
  exit 1
fi

echo ""
echo "SOCKS5 proxy running (PID ${PROXY_PID}) on port ${SOCKS_PORT}."
echo ""
echo "Next steps on Windows:"
echo "  1. In VS Code Ports panel, forward port ${SOCKS_PORT} (it may auto-appear)."
echo "     Or run in a local terminal: ssh -L ${SOCKS_PORT}:localhost:${SOCKS_PORT} <devcontainer-ssh>"
echo ""
echo "  2. Configure your browser to use SOCKS5:"
echo "       Firefox : Settings → Network → Manual proxy → SOCKS5 localhost:${SOCKS_PORT}"
echo "       Chrome  : \"C:\Program Files\Google\Chrome\Application\chrome.exe\" --proxy-server=\"socks5://localhost:${SOCKS_PORT}\""
echo "       Edge    : \"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe\" --proxy-server=\"socks5://localhost:${SOCKS_PORT}\" --user-data-dir=\"%TEMP%\edge-vpn-profile\""
echo "                 (--user-data-dir is required to open a separate Edge instance alongside an existing one)"
echo "       System  : Windows Settings → Proxy → Manual → SOCKS localhost ${SOCKS_PORT}"
echo ""
echo "  3. To stop:  sudo pkill microsocks"

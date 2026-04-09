#!/usr/bin/env bash
set -euo pipefail

echo "[install-openvpn] Installing packages..."
sudo apt-get update -y
# Ubuntu docs: "sudo apt install openvpn easy-rsa" [2](https://ubuntu.com/server/docs/how-to/security/install-openvpn/)
sudo apt-get install -y --no-install-recommends \
  openvpn easy-rsa iproute2 iptables ca-certificates curl

echo "[install-openvpn] Ensuring /dev/net/tun exists..."
# In some container setups, /dev/net/tun isn't present unless passed from host.
# If the device is missing here, OpenVPN will fail at runtime. [1](https://arstech.net/fix-cannot-open-tun-tap-dev-dev-net-tun/)
if [[ ! -c /dev/net/tun ]]; then
  echo "  - /dev/net/tun not found in container."
  echo "  - If you didn't add --device=/dev/net/tun and NET_ADMIN in devcontainer.json, OpenVPN won't run. [1](https://arstech.net/fix-cannot-open-tun-tap-dev-dev-net-tun/)"
else
  ls -l /dev/net/tun || true
fi

echo "[install-openvpn] Installed OpenVPN version:"
openvpn --version | head -n 2

echo "[install-openvpn] Done."

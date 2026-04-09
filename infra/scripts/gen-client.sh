#!/usr/bin/env bash
# gen-client.sh — Generate an OpenVPN client profile (.ovpn)
# Run as root on the OpenVPN gateway VM.
#
# Usage: sudo bash gen-client.sh <client-name>
#   client-name  Unique identifier for this client (e.g. laptop1, user-alice).
#                Will be the EasyRSA Common Name and output filename.
#
# Output: /etc/openvpn/clients/<client-name>.ovpn
set -euo pipefail

EASYRSA_DIR="/etc/openvpn/easy-rsa"
PKI_DIR="${EASYRSA_DIR}/pki"
SERVER_CA="${PKI_DIR}/ca.crt"
TA_KEY="/etc/openvpn/server/ta.key"
OUTPUT_DIR="/etc/openvpn/clients"

VPN_PORT="${VPN_PORT:-1194}"
VPN_PROTO="${VPN_PROTO:-udp}"

# ── helpers ────────────────────────────────────────────────────────────────────
log() { echo "[$(date -Is)] $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2; exit 1
  fi
}

detect_public_ip() {
  # Azure instance metadata service (IMDS) — preferred on Azure VMs
  local ip
  ip=$(curl -sf -H "Metadata:true" \
    "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null) \
    || ip=$(curl -sf https://api.ipify.org 2>/dev/null) \
    || ip=$(curl -sf https://checkip.amazonaws.com 2>/dev/null)
  echo "${ip}"
}

# ── main ───────────────────────────────────────────────────────────────────────
require_root

CLIENT="${1:-}"
if [[ -z "${CLIENT}" ]]; then
  echo "Usage: sudo bash $0 <client-name>" >&2; exit 1
fi

if [[ ! -f "${SERVER_CA}" ]]; then
  echo "CA not found at ${SERVER_CA}. Run install.sh first." >&2; exit 1
fi

# Generate client key + certificate (skip if already exists)
pushd "${EASYRSA_DIR}" >/dev/null
if [[ ! -f "${PKI_DIR}/issued/${CLIENT}.crt" ]]; then
  log "Generating keypair for '${CLIENT}'"
  ./easyrsa --batch gen-req "${CLIENT}" nopass
  log "Signing certificate as client (clientAuth EKU)"
  ./easyrsa --batch sign-req client "${CLIENT}"
else
  log "Certificate for '${CLIENT}' already exists, reusing"
fi
popd >/dev/null

CLIENT_CERT="${PKI_DIR}/issued/${CLIENT}.crt"
CLIENT_KEY="${PKI_DIR}/private/${CLIENT}.key"

SERVER_IP="${SERVER_IP:-$(detect_public_ip)}"
if [[ -z "${SERVER_IP}" ]]; then
  echo "Could not detect public IP. Set SERVER_IP env var and retry." >&2; exit 1
fi

mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

OUTFILE="${OUTPUT_DIR}/${CLIENT}.ovpn"

log "Writing client profile to ${OUTFILE}"
cat >"${OUTFILE}" <<EOF
client
dev tun
proto ${VPN_PROTO}
remote ${SERVER_IP} ${VPN_PORT}

resolv-retry infinite
nobind
persist-key
persist-tun

# tls-auth direction: server=0, client=1
tls-auth [inline]
key-direction 1

cipher AES-256-GCM
auth SHA256

<ca>
$(cat "${SERVER_CA}")
</ca>

<cert>
$(openssl x509 -in "${CLIENT_CERT}")
</cert>

<key>
$(cat "${CLIENT_KEY}")
</key>

<tls-auth>
$(cat "${TA_KEY}")
</tls-auth>

verb 3
EOF

chmod 600 "${OUTFILE}"
log "Done: ${OUTFILE}"
log "Transfer with: scp root@<server>:${OUTFILE} ./${CLIENT}.ovpn"

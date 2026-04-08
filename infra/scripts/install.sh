#!/usr/bin/env bash
set -euo pipefail

# ========= User-tunable settings =========
VPN_PORT="${VPN_PORT:-1194}"
VPN_PROTO="${VPN_PROTO:-udp}"              # udp or tcp
VPN_POOL_CIDR="${VPN_POOL_CIDR:-10.10.0.0/24}"
# Routes to push to clients (space-separated CIDRs). Example: "10.0.0.0/8 172.16.0.0/12"
PUSH_ROUTES="${PUSH_ROUTES:-10.0.0.0/8}"

# DNS server IP to push to VPN clients (should be THIS VM's private IP in Azure)
DNS_LISTEN_IP="${DNS_LISTEN_IP:-10.0.0.4}"

# Bind forwarder for Azure VNets / Private DNS
AZURE_DNS_FORWARDER="${AZURE_DNS_FORWARDER:-168.63.129.16}"

# PKI names
EASYRSA_DIR="/etc/openvpn/easy-rsa"
PKI_DIR="${EASYRSA_DIR}/pki"
SERVER_CN="${SERVER_CN:-server}"

# ========= Helpers =========
log() { echo "[$(date -Is)] $*"; }

# Temporarily override DNS to Azure's built-in resolver so apt can reach
# package repos before bind9 is installed. The VNet DHCP points to this VM
# itself (10.13.4.22) which has no DNS yet at this stage.
bootstrap_dns() {
  log "Bootstrapping DNS: pointing /etc/resolv.conf to Azure DNS (168.63.129.16)"
  # Disable systemd-resolved stub so we can write resolv.conf directly
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    systemctl stop systemd-resolved || true
  fi
  echo "nameserver 168.63.129.16" > /etc/resolv.conf
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2
    exit 1
  fi
}

cidr_to_netmask() {
  # Only supports /0-/32 IPv4 CIDR
  local cidr="$1"
  local bits="${cidr#*/}"
  local mask=$(( 0xffffffff << (32 - bits) & 0xffffffff ))
  printf "%d.%d.%d.%d" \
    $(( (mask >> 24) & 255 )) \
    $(( (mask >> 16) & 255 )) \
    $(( (mask >> 8) & 255 )) \
    $(( mask & 255 ))
}

cidr_network() {
  local cidr="$1"
  local ip="${cidr%/*}"
  local bits="${cidr#*/}"

  IFS=. read -r a b c d <<<"$ip"
  local ip_int=$(( (a<<24) + (b<<16) + (c<<8) + d ))
  local mask=$(( 0xffffffff << (32 - bits) & 0xffffffff ))
  local net_int=$(( ip_int & mask ))

  printf "%d.%d.%d.%d" \
    $(( (net_int >> 24) & 255 )) \
    $(( (net_int >> 16) & 255 )) \
    $(( (net_int >> 8) & 255 )) \
    $(( net_int & 255 ))
}

enable_ip_forwarding() {
  log "Enabling IPv4 forwarding"
  echo "net.ipv4.ip_forward=1" >/etc/sysctl.d/99-openvpn.conf
  sysctl --system >/dev/null
}

detect_default_nic() {
  ip route show default 0.0.0.0/0 | awk '{print $5; exit}'
}

configure_ufw_or_iptables() {
  local nic="$1"
  local vpn_net
  vpn_net="$(cidr_network "$VPN_POOL_CIDR")"
  local vpn_mask
  vpn_mask="$(cidr_to_netmask "$VPN_POOL_CIDR")"

  log "Configuring firewall/NAT (interface=${nic}, vpn=${vpn_net}/${VPN_POOL_CIDR#*/})"

  if command -v ufw >/dev/null 2>&1; then
    # Allow OpenVPN port
    ufw allow "${VPN_PORT}/${VPN_PROTO}" || true
    # Allow DNS only from VNet/VPN (you can tighten later)
    ufw allow 53/udp || true
    ufw allow 53/tcp || true
    ufw allow OpenSSH || true

    # Add NAT rules to /etc/ufw/before.rules if not present
    local before="/etc/ufw/before.rules"
    if ! grep -q "OPENVPN_NAT_${VPN_POOL_CIDR}" "$before"; then
      cat >>"$before" <<EOF

# OPENVPN_NAT_${VPN_POOL_CIDR}
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${vpn_net}/${VPN_POOL_CIDR#*/} -o ${nic} -j MASQUERADE
COMMIT

EOF
    fi

    # Ensure UFW forwarding policy allows routed traffic
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    ufw --force enable
    systemctl restart ufw
  else
    # Fallback to iptables
    iptables -t nat -C POSTROUTING -s "${vpn_net}/${VPN_POOL_CIDR#*/}" -o "${nic}" -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s "${vpn_net}/${VPN_POOL_CIDR#*/}" -o "${nic}" -j MASQUERADE

    iptables -C INPUT -p "${VPN_PROTO}" --dport "${VPN_PORT}" -j ACCEPT 2>/dev/null \
      || iptables -A INPUT -p "${VPN_PROTO}" --dport "${VPN_PORT}" -j ACCEPT

    iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -C INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 53 -j ACCEPT
  fi
}

install_packages() {
  log "Installing packages: openvpn + easy-rsa + bind9 + dnsutils"
  apt-get update -y
  apt-get install -y openvpn easy-rsa bind9 dnsutils
  # OpenVPN install guidance: apt install openvpn easy-rsa [4](https://ubuntu.com/server/docs/how-to/security/install-openvpn/)
  # BIND9 install guidance: apt install bind9 [2](https://ubuntu.com/server/docs/how-to/networking/install-dns/)
}

setup_easyrsa_pki() {
  log "Creating Easy-RSA directory at ${EASYRSA_DIR}"
  mkdir -p /etc/openvpn

  if [[ ! -d "${EASYRSA_DIR}" ]]; then
    # Ubuntu docs recommend: sudo make-cadir /etc/openvpn/easy-rsa [4](https://ubuntu.com/server/docs/how-to/security/install-openvpn/)
    make-cadir "${EASYRSA_DIR}"
  fi

  pushd "${EASYRSA_DIR}" >/dev/null

  if [[ ! -d "${PKI_DIR}" ]]; then
    log "Initializing PKI"
    ./easyrsa init-pki
  fi

  if [[ ! -f "${PKI_DIR}/ca.crt" ]]; then
    log "Building CA (nopass)"
    ./easyrsa --batch build-ca nopass
  fi

  if [[ ! -f "${PKI_DIR}/issued/${SERVER_CN}.crt" ]]; then
    log "Generating server keypair and certificate (${SERVER_CN})"
    ./easyrsa --batch gen-req "${SERVER_CN}" nopass
    ./easyrsa --batch sign-req server "${SERVER_CN}"
  fi

  # TLS auth key (ta.key)
  if [[ ! -f "${PKI_DIR}/ta.key" ]]; then
    log "Generating ta.key"
    openvpn --genkey secret "${PKI_DIR}/ta.key"
  fi

  popd >/dev/null

  log "Installing server credentials into /etc/openvpn/server"
  mkdir -p /etc/openvpn/server
  install -m 0644 "${PKI_DIR}/ca.crt" "/etc/openvpn/server/ca.crt"
  install -m 0644 "${PKI_DIR}/issued/${SERVER_CN}.crt" "/etc/openvpn/server/server.crt"
  install -m 0600 "${PKI_DIR}/private/${SERVER_CN}.key" "/etc/openvpn/server/server.key"
  install -m 0600 "${PKI_DIR}/ta.key" "/etc/openvpn/server/ta.key"
}

write_openvpn_server_conf() {
  log "Writing OpenVPN server config: /etc/openvpn/server/server.conf"

  local vpn_net
  vpn_net="$(cidr_network "$VPN_POOL_CIDR")"
  local vpn_mask
  vpn_mask="$(cidr_to_netmask "$VPN_POOL_CIDR")"

  cat >/etc/openvpn/server/server.conf <<EOF
# OpenVPN server config (Azure VM)
# Sample configs exist under /usr/share/doc/openvpn/... and are recommended as a starting point. [5](https://openvpn.net/community-docs/creating-configuration-files-for-server-and-clients.html)
port ${VPN_PORT}
proto ${VPN_PROTO}
dev tun
topology subnet

server ${vpn_net} ${vpn_mask}
ifconfig-pool-persist /var/log/openvpn/ipp.txt

# PKI
ca   /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key  /etc/openvpn/server/server.key

# Extra TLS protection key
tls-auth /etc/openvpn/server/ta.key 0

# Push routes to clients (Azure VNet, etc.)
EOF

  for r in ${PUSH_ROUTES}; do
    local rn rm
    rn="$(cidr_network "$r")"
    rm="$(cidr_to_netmask "$r")"
    echo "push \"route ${rn} ${rm}\"" >>/etc/openvpn/server/server.conf
  done

  cat >>/etc/openvpn/server/server.conf <<EOF

# Push DNS (Bind9 on this VM)
push "dhcp-option DNS ${DNS_LISTEN_IP}"

# Security hardening
user nobody
group nogroup
persist-key
persist-tun

# Client connectivity
client-to-client

# Keepalive
keepalive 10 60
explicit-exit-notify 1

# Logs
status /var/log/openvpn/openvpn-status.log
verb 3
EOF
}

write_bind9_forwarder_conf() {
  log "Writing BIND9 forwarder config: /etc/bind/named.conf.options"

  # This follows the Ubuntu DNS doc pattern of adding "forwarders { ... }" to named.conf.options [2](https://ubuntu.com/server/docs/how-to/networking/install-dns/)
  # And matches your internal email snippet using forwarder 168.63.129.16 for Azure DNS [1](https://outlook.office365.com/owa/?ItemID=AAMkADE4NjM3ZjQ4LWFkNzItNGI5ZS04NjA4LTc0ZjE1N2MxZmZkNQBGAAAAAACoiMDyGZlvRJPpcu%2bvRChuBwANcynRUefSEZneAAjHM5VrAAAAy5B%2bAABZarbCjLDhSa1l8rbZPEM3AAUg7LhAAAA%3d&exvsurl=1&viewmodel=ReadMessageItem)[3](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16)
  cat >/etc/bind/named.conf.options <<EOF
acl vpn_clients {
  localhost;
  ${VPN_POOL_CIDR};
  10.0.0.0/8;
};

options {
  directory "/var/cache/bind";

  recursion yes;
  allow-query { vpn_clients; };
  allow-recursion { vpn_clients; };

  forwarders {
    ${AZURE_DNS_FORWARDER};
  };

  dnssec-validation auto;
  auth-nxdomain no; # conform to RFC1035
  listen-on-v6 { any; };
};
EOF

  named-checkconf >/dev/null
}

restart_services() {
  log "Restarting BIND9"
  systemctl enable --now named
  systemctl restart named

  log "Starting OpenVPN server instance (systemd unit openvpn-server@server)"
  systemctl enable --now openvpn-server@server
  systemctl restart openvpn-server@server
}

smoke_tests() {
  log "Smoke test: bind9 local query via dnsutils"
  # dnsutils recommended for testing in Ubuntu DNS docs [2](https://ubuntu.com/server/docs/how-to/networking/install-dns/)
  nslookup microsoft.com 127.0.0.1 >/dev/null || true

  log "Smoke test: OpenVPN status"
  systemctl --no-pager --full status openvpn-server@server || true
  systemctl --no-pager --full status named || true

  log "DONE. Next: ensure Azure NSG allows ${VPN_PROTO}/${VPN_PORT} to this VM and TCP/UDP 53 only from your trusted ranges."
}

main() {
  require_root
  bootstrap_dns
  install_packages
  setup_easyrsa_pki
  write_openvpn_server_conf
  write_bind9_forwarder_conf
  enable_ip_forwarding

  local nic
  nic="$(detect_default_nic)"
  configure_ufw_or_iptables "${nic}"

  restart_services
  smoke_tests

  cat <<EOF

================================================================================
Client profile creation:
- Create client certs in ${EASYRSA_DIR} (./easyrsa gen-req + sign-req client ...)
- Build a .ovpn profile that references ca.crt, client cert/key, and ta.key
OpenVPN provides sample server/client configs as starting points. [5](https://openvpn.net/community-docs/creating-configuration-files-for-server-and-clients.html)
================================================================================

EOF
}

main "$@"

#!/bin/bash
# =============================================================================
# FW_CLIENT - Règles iptables (équivalent IPv4 Policy FortiGate)
# =============================================================================
# Interfaces résolues dynamiquement à partir des IPs statiques définies dans
# docker-compose.yml pour éviter toute dépendance à l'ordre des cartes réseau.
# =============================================================================

set -e
. /usr/local/lib/lab-net.sh

echo "[FW_CLIENT] Application des règles iptables..."

require_if_by_ip LAN_IF 192.168.10.1
require_if_by_ip MGMT_IF 192.168.99.10
require_if_by_ip WAN_IF 10.10.0.2
log_if_assignment LAN "$LAN_IF" 192.168.10.1
log_if_assignment MGMT "$MGMT_IF" 192.168.99.10
log_if_assignment WAN "$WAN_IF" 10.10.0.2

iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# Politiques par défaut DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Loopback + connexions établies
iptables -A INPUT  -i lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# ICMP
iptables -A INPUT   -p icmp -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT

# Management : SSH/HTTPS uniquement depuis mgmt_net
iptables -A INPUT -i "$MGMT_IF" -p tcp --dport 22  -j ACCEPT
iptables -A INPUT -i "$MGMT_IF" -p tcp --dport 443 -j ACCEPT

# DNS et DHCP côté LAN
iptables -A INPUT -i "$LAN_IF" -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 3128 -j ACCEPT  # Squid proxy

# IPsec : ports IKE et NAT-T
iptables -A INPUT -p udp --dport 500  -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT

# --- Forwarding LAN_CLIENT -> Internet (via FW_ISP) ---
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -s 192.168.10.0/24 -j ACCEPT

# --- DNS/NTP du LAN vers FW_ISP via le réseau de management ---
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.10.0/24 -d 192.168.99.1 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.10.0/24 -d 192.168.99.1 -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.10.0/24 -d 192.168.99.1 -p udp --dport 123 -j ACCEPT

# --- Forwarding LAN_CLIENT -> LAN_SERVER (via tunnel VPN) ---
# strongSwan utilise XFRM, le trafic passera donc par les politiques IPsec
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -j ACCEPT
iptables -A FORWARD -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT

# --- NAT pour Internet uniquement (PAS pour le tunnel VPN) ---
# Important : on exclut 192.168.20.0/24 (LAN distant) du NAT
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -d 192.168.20.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o "$WAN_IF" -j MASQUERADE

# Logs
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "[FW_CLIENT-IN-DROP] "
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "[FW_CLIENT-FWD-DROP] "

echo "[FW_CLIENT] Règles appliquées."
iptables -L -n -v --line-numbers
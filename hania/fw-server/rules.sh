#!/bin/bash
# =============================================================================
# FW_SERVER - Règles iptables
# =============================================================================

set -euo pipefail
. /usr/local/lib/lab-net.sh

NODE_MGMT_IP=${NODE_MGMT_IP:-192.168.99.20}
NODE_WAN_IP=${NODE_WAN_IP:-10.20.0.2}
NODE_LAN_IP=${NODE_LAN_IP:-192.168.20.1}
NODE_DMZ_IP=${NODE_DMZ_IP:-192.168.50.1}
UPSTREAM_WAN_GW=${UPSTREAM_WAN_GW:-10.20.0.1}
UPSTREAM_WAN_NET=${UPSTREAM_WAN_NET:-10.20.0.0/24}
UPSTREAM_MGMT_DNS=${UPSTREAM_MGMT_DNS:-192.168.99.1}
PEER_WAN_NODE_IP=${PEER_WAN_NODE_IP:-}
PEER_LAN_NODE_IP=${PEER_LAN_NODE_IP:-}
PEER_DMZ_NODE_IP=${PEER_DMZ_NODE_IP:-}
PEER_MGMT_NODE_IP=${PEER_MGMT_NODE_IP:-}
CONNTRACKD_PEER_IP=${CONNTRACKD_PEER_IP:-}

echo "[FW_SERVER] Application des règles iptables..."

require_if_by_ip MGMT_IF "$NODE_MGMT_IP"
require_if_by_ip WAN_IF "$NODE_WAN_IP"
require_if_by_ip LAN_IF "$NODE_LAN_IP"
require_if_by_ip DMZ_IF "$NODE_DMZ_IP"
log_if_assignment MGMT "$MGMT_IF" "$NODE_MGMT_IP"
log_if_assignment WAN "$WAN_IF" "$NODE_WAN_IP"
log_if_assignment LAN "$LAN_IF" "$NODE_LAN_IP"
log_if_assignment DMZ "$DMZ_IF" "$NODE_DMZ_IP"

iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT  -i lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -A INPUT   -p icmp -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT

# Management
iptables -A INPUT -i "$MGMT_IF" -p tcp --dport 22  -j ACCEPT
iptables -A INPUT -i "$MGMT_IF" -p tcp --dport 443 -j ACCEPT

# NTP côté LAN
iptables -A INPUT -i "$LAN_IF" -p udp --dport 123 -j ACCEPT

# IPsec
iptables -A INPUT -p udp --dport 500  -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT

if [ -n "$PEER_WAN_NODE_IP" ]; then
	iptables -A INPUT -i "$WAN_IF" -p 112 -s "$PEER_WAN_NODE_IP" -j ACCEPT
fi
if [ -n "$PEER_LAN_NODE_IP" ]; then
	iptables -A INPUT -i "$LAN_IF" -p 112 -s "$PEER_LAN_NODE_IP" -j ACCEPT
fi
if [ -n "$PEER_DMZ_NODE_IP" ]; then
	iptables -A INPUT -i "$DMZ_IF" -p 112 -s "$PEER_DMZ_NODE_IP" -j ACCEPT
fi
if [ -n "$PEER_MGMT_NODE_IP" ]; then
	iptables -A INPUT -i "$MGMT_IF" -p 112 -s "$PEER_MGMT_NODE_IP" -j ACCEPT
fi
if [ -n "$CONNTRACKD_PEER_IP" ]; then
	iptables -A INPUT -i "$MGMT_IF" -p udp -s "$CONNTRACKD_PEER_IP" --dport 3780 -j ACCEPT
fi

# USERS -> SERVERS : HTTP/HTTPS/SSH uniquement
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -p tcp -m multiport --dports 22,80,443 -j ACCEPT
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -j DROP

# USERS -> DMZ : HTTP/HTTPS uniquement
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.50.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.50.0/24 -j DROP

# Internet simule -> DMZ : HTTP/HTTPS uniquement
iptables -A FORWARD -s 200.0.0.0/24 -d 192.168.50.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -s 200.0.0.0/24 -d 192.168.20.0/24 -j DROP

# FW_ISP -> SERVERS : backend HAProxy public depuis les deux noeuds ISP HA
iptables -A FORWARD -s "$UPSTREAM_WAN_NET" -d 192.168.20.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT

# --- Forwarding LAN_SERVER -> Internet ---
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -s 192.168.20.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -s 192.168.20.0/24 -d "$UPSTREAM_WAN_GW" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -s 192.168.20.0/24 -d "$UPSTREAM_WAN_GW" -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -s 192.168.20.0/24 -d "$UPSTREAM_WAN_GW" -p udp --dport 123 -j ACCEPT

# DMZ -> Internet : web + resolution
iptables -A FORWARD -i "$DMZ_IF" -o "$WAN_IF" -s 192.168.50.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -i "$DMZ_IF" -o "$WAN_IF" -s 192.168.50.0/24 -d "$UPSTREAM_WAN_GW" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$DMZ_IF" -o "$WAN_IF" -s 192.168.50.0/24 -d "$UPSTREAM_WAN_GW" -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$DMZ_IF" -o "$WAN_IF" -s 192.168.50.0/24 -d "$UPSTREAM_WAN_GW" -p udp --dport 123 -j ACCEPT

# --- DNS/NTP du LAN vers FW_ISP via le réseau de management ---
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.20.0/24 -d "$UPSTREAM_MGMT_DNS" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.20.0/24 -d "$UPSTREAM_MGMT_DNS" -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.20.0/24 -d "$UPSTREAM_MGMT_DNS" -p udp --dport 123 -j ACCEPT

# --- Flux retour VPN ---
iptables -A FORWARD -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT
iptables -A FORWARD -s 192.168.50.0/24 -d 192.168.10.0/24 -j ACCEPT

# --- NAT ---
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -o "$WAN_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o "$WAN_IF" -j MASQUERADE

# Logs
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "[FW_SERVER-IN-DROP] "
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "[FW_SERVER-FWD-DROP] "

echo "[FW_SERVER] Règles appliquées."
iptables -L -n -v --line-numbers
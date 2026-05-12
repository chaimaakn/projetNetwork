#!/bin/bash
# =============================================================================
# FW_SERVER - Règles iptables
# =============================================================================
# Topologie :
#   - eth0 / wan_server_net : 10.20.0.2  (vers FW_ISP)
#   - eth1 / lan_server_net : 192.168.20.1
#   - eth2 / mgmt_net       : 192.168.99.20
# =============================================================================

set -e
echo "[FW_SERVER] Application des règles iptables..."

get_if_by_ip() {
	ip -o -4 addr show | awk -v target="$1" '$4 ~ ("^" target "/") { print $2; exit }'
}

MGMT_IF=$(get_if_by_ip 192.168.99.20)
WAN_IF=$(get_if_by_ip 10.20.0.2)
LAN_IF=$(get_if_by_ip 192.168.20.1)

for pair in \
	"MGMT_IF:192.168.99.20" \
	"WAN_IF:10.20.0.2" \
	"LAN_IF:192.168.20.1"
do
	var_name=${pair%%:*}
	var_ip=${pair##*:}
	if [ -z "${!var_name}" ]; then
		echo "[FW_SERVER] Interface introuvable pour ${var_ip}" >&2
		exit 1
	fi
done

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

# --- Forwarding LAN_SERVER -> Internet ---
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -s 192.168.20.0/24 -j ACCEPT

# --- DNS/NTP du LAN vers FW_ISP via le réseau de management ---
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.20.0/24 -d 192.168.99.1 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.20.0/24 -d 192.168.99.1 -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.20.0/24 -d 192.168.99.1 -p udp --dport 123 -j ACCEPT

# --- Forwarding via VPN ---
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -j ACCEPT
iptables -A FORWARD -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT

# --- Accès aux services serveurs depuis le LAN_CLIENT (via VPN) ---
# HTTP/HTTPS sur webserver
iptables -A FORWARD -d 192.168.20.10 -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -d 192.168.20.10 -p tcp --dport 443 -j ACCEPT
# SSH sur sshserver (sera l'objet du brute-force en Phase 3)
iptables -A FORWARD -d 192.168.20.11 -p tcp --dport 22 -j ACCEPT

# --- NAT ---
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -o "$WAN_IF" -j MASQUERADE

# Logs
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "[FW_SERVER-IN-DROP] "
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "[FW_SERVER-FWD-DROP] "

echo "[FW_SERVER] Règles appliquées."
iptables -L -n -v --line-numbers
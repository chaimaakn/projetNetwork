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
require_if_by_ip VOIP_IF 192.168.30.1
require_if_by_ip GUEST_IF 192.168.40.1
require_if_by_ip MGMT_IF 192.168.99.10
require_if_by_ip WAN_IF 10.10.0.2
log_if_assignment LAN "$LAN_IF" 192.168.10.1
log_if_assignment VOIP "$VOIP_IF" 192.168.30.1
log_if_assignment GUEST "$GUEST_IF" 192.168.40.1
log_if_assignment MGMT "$MGMT_IF" 192.168.99.10
log_if_assignment WAN "$WAN_IF" 10.10.0.2

create_or_reset_netset() {
	local set_name=$1
	ipset create "$set_name" hash:net family inet -exist
	ipset flush "$set_name"
}

create_or_reset_portset() {
	local set_name=$1
	ipset create "$set_name" bitmap:port range 0-65535 -exist
	ipset flush "$set_name"
}

create_or_reset_netset users_net
ipset add users_net 192.168.10.0/24

create_or_reset_netset voip_net
ipset add voip_net 192.168.30.0/24

create_or_reset_netset guest_net
ipset add guest_net 192.168.40.0/24

create_or_reset_netset servers_net
ipset add servers_net 192.168.20.0/24

create_or_reset_netset dmz_net
ipset add dmz_net 192.168.50.0/24

create_or_reset_netset mgmt_net
ipset add mgmt_net 192.168.99.0/24

create_or_reset_netset blocked_external
for cidr in 0.0.0.0/8 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4 240.0.0.0/4; do
	ipset add blocked_external "$cidr"
done

create_or_reset_portset web_ports
for port in 80 443 8080; do
	ipset add web_ports "$port"
done

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

# Anti-spoofing des segments locaux
iptables -A FORWARD -i "$LAN_IF" ! -s 192.168.10.0/24 -j DROP
iptables -A FORWARD -i "$VOIP_IF" ! -s 192.168.30.0/24 -j DROP
iptables -A FORWARD -i "$GUEST_IF" ! -s 192.168.40.0/24 -j DROP

# Objets d'adresses: bloquer les destinations bogons avant les autorisations WAN
iptables -A FORWARD -o "$WAN_IF" -m set --match-set blocked_external dst -j DROP

# USERS -> SERVERS via VPN : HTTP/HTTPS/SSH uniquement
iptables -A FORWARD -m set --match-set users_net src -m set --match-set servers_net dst -p tcp -m set --match-set web_ports dst -j ACCEPT
iptables -A FORWARD -m set --match-set users_net src -m set --match-set servers_net dst -p tcp --dport 22 -j ACCEPT
iptables -A FORWARD -m set --match-set users_net src -m set --match-set servers_net dst -j DROP

# USERS -> DMZ via VPN : HTTP/HTTPS uniquement
iptables -A FORWARD -m set --match-set users_net src -m set --match-set dmz_net dst -p tcp -m set --match-set web_ports dst -j ACCEPT
iptables -A FORWARD -m set --match-set users_net src -m set --match-set dmz_net dst -j DROP

# USERS -> autres VLANs locaux : interdits
iptables -A FORWARD -m set --match-set users_net src -m set --match-set voip_net dst -j DROP
iptables -A FORWARD -m set --match-set users_net src -m set --match-set guest_net dst -j DROP

# VOIP : DNS + SIP + RTP vers l'exterieur uniquement
iptables -A FORWARD -i "$VOIP_IF" -o "$WAN_IF" -s 192.168.30.0/24 -d 10.10.0.1 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$VOIP_IF" -o "$WAN_IF" -s 192.168.30.0/24 -d 10.10.0.1 -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$VOIP_IF" -o "$WAN_IF" -s 192.168.30.0/24 -p udp --dport 5060 -j ACCEPT
iptables -A FORWARD -i "$VOIP_IF" -o "$WAN_IF" -s 192.168.30.0/24 -p udp --dport 10000:20000 -j ACCEPT
iptables -A FORWARD -i "$VOIP_IF" -s 192.168.30.0/24 -d 192.168.0.0/16 -j DROP

# GUEST : Internet HTTP/HTTPS + DNS uniquement, jamais l'interne
iptables -A FORWARD -i "$GUEST_IF" -s 192.168.40.0/24 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i "$GUEST_IF" -o "$WAN_IF" -s 192.168.40.0/24 -d 10.10.0.1 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$GUEST_IF" -o "$WAN_IF" -s 192.168.40.0/24 -d 10.10.0.1 -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$GUEST_IF" -o "$WAN_IF" -s 192.168.40.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT

# --- DNS/NTP du LAN vers FW_ISP via le réseau de management ---
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.10.0/24 -d 192.168.99.1 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.10.0/24 -d 192.168.99.1 -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$MGMT_IF" -s 192.168.10.0/24 -d 192.168.99.1 -p udp --dport 123 -j ACCEPT

# Sortie Internet generale pour USERS
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -m set --match-set users_net src -j ACCEPT

# Flux retour VPN/DMZ autorises
iptables -A FORWARD -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT
iptables -A FORWARD -s 192.168.50.0/24 -d 192.168.10.0/24 -j ACCEPT

# --- NAT pour Internet uniquement (PAS pour le tunnel VPN) ---
# Important : on exclut les sous-reseaux distants atteints via IPsec du NAT
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -d 192.168.20.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -d 192.168.50.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o "$WAN_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.30.0/24 -o "$WAN_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.40.0/24 -o "$WAN_IF" -j MASQUERADE

# Logs
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "[FW_CLIENT-IN-DROP] "
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "[FW_CLIENT-FWD-DROP] "

echo "[FW_CLIENT] Règles appliquées."
iptables -L -n -v --line-numbers
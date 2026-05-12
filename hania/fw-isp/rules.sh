#!/bin/bash
# =============================================================================
# FW_ISP - Règles iptables (équivalent Rules WAN/LAN sur pfSense)
# =============================================================================
# Interfaces résolues dynamiquement à partir des IPs statiques définies dans
# docker-compose.yml pour éviter toute dépendance à l'ordre des cartes réseau.
# =============================================================================

set -e
. /usr/local/lib/lab-net.sh

echo "[FW_ISP] Application des règles iptables..."

require_if_by_ip MGMT_IF 192.168.99.1
require_if_by_ip WAN_CLIENT_IF 10.10.0.1
require_if_by_ip WAN_SERVER_IF 10.20.0.1
require_if_by_ip INTERNET_IF 200.0.0.10
log_if_assignment MGMT "$MGMT_IF" 192.168.99.1
log_if_assignment WAN_CLIENT "$WAN_CLIENT_IF" 10.10.0.1
log_if_assignment WAN_SERVER "$WAN_SERVER_IF" 10.20.0.1
log_if_assignment INTERNET "$INTERNET_IF" 200.0.0.10

# --- Reset complet des règles ---
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# --- Politiques par défaut : DROP (principe du moindre privilège) ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT     # On laisse sortir le firewall lui-même

# --- Boucle locale et sessions établies ---
iptables -A INPUT  -i lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- ICMP autorisé (pour diagnostics) ---
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT

# --- DNS depuis les LANs vers FW_ISP ---
iptables -A INPUT -p udp --dport 53 -s 10.10.0.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -s 10.10.0.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 10.20.0.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -s 10.20.0.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 192.168.10.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -s 192.168.10.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 192.168.20.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -s 192.168.20.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 192.168.99.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -s 192.168.99.0/24 -j ACCEPT

# --- NTP depuis les LANs ---
iptables -A INPUT -p udp --dport 123 -s 10.10.0.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -s 10.20.0.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -s 192.168.10.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -s 192.168.20.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -s 192.168.99.0/24 -j ACCEPT

# --- Management : SSH/HTTPS uniquement depuis le réseau de management ---
iptables -A INPUT -p tcp --dport 22  -s 192.168.99.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -s 192.168.99.0/24 -j ACCEPT

# --- Forwarding LAN_CLIENT -> Internet ---
iptables -A FORWARD -s 192.168.10.0/24 -o "$INTERNET_IF" -j ACCEPT
# --- Forwarding LAN_SERVER -> Internet ---
iptables -A FORWARD -s 192.168.20.0/24 -o "$INTERNET_IF" -j ACCEPT

# --- Egress minimal des firewalls de site vers Internet ---
# Nécessaire pour les services locaux comme Squid, curl/apt et les synchronisations.
iptables -A FORWARD -s 10.10.0.0/24 -o "$INTERNET_IF" -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -s 10.10.0.0/24 -o "$INTERNET_IF" -p udp --dport 123 -j ACCEPT
iptables -A FORWARD -s 10.20.0.0/24 -o "$INTERNET_IF" -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -s 10.20.0.0/24 -o "$INTERNET_IF" -p udp --dport 123 -j ACCEPT

# --- Tunnel VPN IPsec : autoriser trafic chiffré entre les sites ---
# UDP 500 (IKE) et UDP 4500 (NAT-T) entre FW_CLIENT et FW_SERVER via FW_ISP
iptables -A FORWARD -p udp --dport 500  -j ACCEPT
iptables -A FORWARD -p udp --dport 4500 -j ACCEPT
iptables -A FORWARD -p esp -j ACCEPT

# --- NAT (équivalent Outbound NAT pfSense, mode automatique) ---
# Tout le trafic sortant depuis les LANs est SNATé vers l'IP "Internet"
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o "$INTERNET_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -o "$INTERNET_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.10.0.0/24    -o "$INTERNET_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.20.0.0/24    -o "$INTERNET_IF" -j MASQUERADE

# --- Logging (équivalent du log par règle pfSense) ---
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "[FW_ISP-IN-DROP] "  --log-level 4
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "[FW_ISP-FWD-DROP] " --log-level 4

echo "[FW_ISP] Règles appliquées avec succès."
iptables -L -n -v --line-numbers
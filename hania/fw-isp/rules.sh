#!/bin/bash
# =============================================================================
# FW_ISP - Règles iptables (équivalent Rules WAN/LAN sur pfSense)
# =============================================================================
# Topologie :
#   - eth0 / internet_net  -> 200.0.0.10  (WAN simulé Internet)
#   - eth1 / wan_client_net -> 10.10.0.1  (vers FW_CLIENT)
#   - eth2 / wan_server_net -> 10.20.0.1  (vers FW_SERVER)
#   - eth3 / mgmt_net      -> 192.168.99.1
# =============================================================================

set -e
echo "[FW_ISP] Application des règles iptables..."

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
iptables -A INPUT -p udp --dport 53 -s 192.168.20.0/24 -j ACCEPT

# --- NTP depuis les LANs ---
iptables -A INPUT -p udp --dport 123 -s 10.10.0.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -s 10.20.0.0/24 -j ACCEPT

# --- Management : SSH/HTTPS uniquement depuis le réseau de management ---
iptables -A INPUT -p tcp --dport 22  -s 192.168.99.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -s 192.168.99.0/24 -j ACCEPT

# --- Forwarding LAN_CLIENT -> Internet ---
iptables -A FORWARD -s 192.168.10.0/24 -o eth0 -j ACCEPT
# --- Forwarding LAN_SERVER -> Internet ---
iptables -A FORWARD -s 192.168.20.0/24 -o eth0 -j ACCEPT

# --- Tunnel VPN IPsec : autoriser trafic chiffré entre les sites ---
# UDP 500 (IKE) et UDP 4500 (NAT-T) entre FW_CLIENT et FW_SERVER via FW_ISP
iptables -A FORWARD -p udp --dport 500  -j ACCEPT
iptables -A FORWARD -p udp --dport 4500 -j ACCEPT
iptables -A FORWARD -p esp -j ACCEPT

# --- NAT (équivalent Outbound NAT pfSense, mode automatique) ---
# Tout le trafic sortant depuis les LANs est SNATé vers l'IP "Internet"
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.10.0.0/24    -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.20.0.0/24    -o eth0 -j MASQUERADE

# --- Logging (équivalent du log par règle pfSense) ---
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "[FW_ISP-IN-DROP] "  --log-level 4
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "[FW_ISP-FWD-DROP] " --log-level 4

echo "[FW_ISP] Règles appliquées avec succès."
iptables -L -n -v --line-numbers
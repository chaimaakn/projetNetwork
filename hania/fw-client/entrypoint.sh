#!/bin/bash
# =============================================================================
# FW_CLIENT - Démarrage
# =============================================================================

set -e
LOG=/var/log/fw/startup.log
mkdir -p /var/log/fw
echo "[$(date)] === Démarrage FW_CLIENT ===" | tee -a $LOG

echo 1 > /proc/sys/net/ipv4/ip_forward

get_if_by_ip() {
	ip -o -4 addr show | awk -v target="$1" '$4 ~ ("^" target "/") { print $2; exit }'
}

LAN_IF=$(get_if_by_ip 192.168.10.1)

if [ -z "$LAN_IF" ]; then
	echo "[$(date)] Interface LAN introuvable pour FW_CLIENT" | tee -a $LOG
	exit 1
fi

# Route par défaut via FW_ISP
ip route del default 2>/dev/null || true
ip route add default via 10.10.0.1 || true

# Règles iptables
/usr/local/bin/rules.sh | tee -a $LOG

rsyslogd || true

# DHCP Serveur (dnsmasq) sur le LAN_CLIENT
echo "[$(date)] Démarrage de dnsmasq (DHCP LAN_CLIENT)..." | tee -a $LOG
sed "s/__LAN_IF__/${LAN_IF}/g" /etc/dnsmasq.conf > /tmp/dnsmasq.conf
dnsmasq -k -C /tmp/dnsmasq.conf &

# Squid (proxy + filtrage web)
echo "[$(date)] Démarrage de Squid (proxy/filtrage)..." | tee -a $LOG
: > /etc/squid/blocked_domains.txt
squid -N -f /etc/squid/squid.conf &

# IPsec (strongSwan)
echo "[$(date)] Démarrage IPsec strongSwan..." | tee -a $LOG
ipsec start --nofork &
IPSEC_PID=$!

sleep 5
ipsec statusall || true

echo "[$(date)] === FW_CLIENT opérationnel ===" | tee -a $LOG

# Attendre IPsec
wait $IPSEC_PID
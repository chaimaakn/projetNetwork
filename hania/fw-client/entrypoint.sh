#!/bin/bash
# =============================================================================
# FW_CLIENT - Démarrage
# =============================================================================

set -e
LOG=/var/log/fw/startup.log
. /usr/local/lib/lab-net.sh

mkdir -p /var/log/fw
echo "[$(date)] === Démarrage FW_CLIENT ===" | tee -a $LOG

echo 1 > /proc/sys/net/ipv4/ip_forward

require_if_by_ip LAN_IF 192.168.10.1
log_if_assignment LAN "$LAN_IF" 192.168.10.1 | tee -a "$LOG"

# Route par défaut via FW_ISP
replace_default_route 10.10.0.1

# Résolution DNS du firewall via le résolveur interne du lab.
configure_resolver 192.168.99.1 labcyber.local

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
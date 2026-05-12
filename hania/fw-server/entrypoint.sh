#!/bin/bash
# =============================================================================
# FW_SERVER - Démarrage
# =============================================================================

set -e
LOG=/var/log/fw/startup.log
. /usr/local/lib/lab-net.sh

mkdir -p /var/log/fw
echo "[$(date)] === Démarrage FW_SERVER ===" | tee -a $LOG

echo 1 > /proc/sys/net/ipv4/ip_forward

require_if_by_ip LAN_IF 192.168.20.1
require_if_by_ip DMZ_IF 192.168.50.1
require_if_by_ip WAN_IF 10.20.0.2
require_if_by_ip MGMT_IF 192.168.99.20
log_if_assignment LAN "$LAN_IF" 192.168.20.1 | tee -a "$LOG"
log_if_assignment DMZ "$DMZ_IF" 192.168.50.1 | tee -a "$LOG"
log_if_assignment WAN "$WAN_IF" 10.20.0.2 | tee -a "$LOG"
log_if_assignment MGMT "$MGMT_IF" 192.168.99.20 | tee -a "$LOG"

# Route par défaut via FW_ISP
replace_default_route 10.20.0.1

# Résolution DNS du firewall via le résolveur interne du lab.
configure_resolver 192.168.99.1 labcyber.local

# Règles iptables
/usr/local/bin/rules.sh | tee -a $LOG

rsyslogd || true

# Chrony en serveur NTP local
echo "[$(date)] Démarrage chrony (NTP serveur)..." | tee -a $LOG
chronyd -d -f /etc/chrony/chrony.conf &

# IPsec
echo "[$(date)] Démarrage IPsec strongSwan..." | tee -a $LOG
ipsec start --nofork &
IPSEC_PID=$!

sleep 5
ipsec statusall || true

echo "[$(date)] === FW_SERVER opérationnel ===" | tee -a $LOG

wait $IPSEC_PID
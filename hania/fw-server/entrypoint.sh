#!/bin/bash
# =============================================================================
# FW_SERVER - Démarrage
# =============================================================================

set -e
LOG=/var/log/fw/startup.log
mkdir -p /var/log/fw
echo "[$(date)] === Démarrage FW_SERVER ===" | tee -a $LOG

echo 1 > /proc/sys/net/ipv4/ip_forward

# Route par défaut via FW_ISP
ip route del default 2>/dev/null || true
ip route add default via 10.20.0.1 || true

# Règles iptables
/usr/local/bin/rules.sh | tee -a $LOG

service rsyslog start || true

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
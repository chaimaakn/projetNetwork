#!/bin/bash
# =============================================================================
# FW_ISP - Script de démarrage
# Équivalent du boot pfSense : applique les règles + lance les services
# =============================================================================

set -e
LOG=/var/log/fw/startup.log
mkdir -p /var/log/fw
echo "[$(date)] === Démarrage FW_ISP ===" | tee -a $LOG

# Active l'IP forwarding (équivalent System > Advanced > Networking sur pfSense)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Applique les règles iptables
/usr/local/bin/rules.sh | tee -a $LOG

# Démarre rsyslog pour le logging
service rsyslog start || true

# Démarre chrony (NTP)
echo "[$(date)] Démarrage de chrony (NTP)..." | tee -a $LOG
chronyd -d -f /etc/chrony/chrony.conf &

# Démarre dnsmasq (DNS + DHCP)
echo "[$(date)] Démarrage de dnsmasq (DNS/DHCP)..." | tee -a $LOG
dnsmasq -k -C /etc/dnsmasq.conf &

# Démarre HAProxy (load balancer applicatif)
echo "[$(date)] Démarrage de HAProxy..." | tee -a $LOG
haproxy -f /etc/haproxy/haproxy.cfg -D || echo "HAProxy non démarré (config par défaut)"

echo "[$(date)] === FW_ISP opérationnel ===" | tee -a $LOG

# Garde le conteneur actif
tail -f /var/log/fw/startup.log
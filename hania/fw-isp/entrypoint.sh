#!/bin/bash
# =============================================================================
# FW_ISP - Script de démarrage
# Équivalent du boot pfSense : applique les règles + lance les services
# =============================================================================

set -e
LOG=/var/log/fw/startup.log
. /usr/local/lib/lab-net.sh

mkdir -p /var/log/fw
echo "[$(date)] === Démarrage FW_ISP ===" | tee -a $LOG

# Active l'IP forwarding (équivalent System > Advanced > Networking sur pfSense)
echo 1 > /proc/sys/net/ipv4/ip_forward

require_if_by_ip INTERNET_IF 200.0.0.10
require_if_by_ip WAN_CLIENT_IF 10.10.0.1
require_if_by_ip WAN_SERVER_IF 10.20.0.1
require_if_by_ip MGMT_IF 192.168.99.1
log_if_assignment INTERNET "$INTERNET_IF" 200.0.0.10 | tee -a "$LOG"
log_if_assignment WAN_CLIENT "$WAN_CLIENT_IF" 10.10.0.1 | tee -a "$LOG"
log_if_assignment WAN_SERVER "$WAN_SERVER_IF" 10.20.0.1 | tee -a "$LOG"
log_if_assignment MGMT "$MGMT_IF" 192.168.99.1 | tee -a "$LOG"

# Routes statiques vers les LANs derrière les firewalls sites.
replace_static_route 192.168.10.0/24 10.10.0.2
replace_static_route 192.168.20.0/24 10.20.0.2

# Applique les règles iptables
/usr/local/bin/rules.sh | tee -a $LOG

# Démarre rsyslog pour le logging
rsyslogd || true

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
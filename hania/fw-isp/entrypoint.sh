#!/bin/bash
# =============================================================================
# FW_ISP - Script de démarrage
# =============================================================================

set -euo pipefail

LOG=/var/log/fw/startup.log
. /usr/local/lib/lab-net.sh

HA_ENABLED=${HA_ENABLED:-0}
HA_STATE=${HA_STATE:-MASTER}
HA_PRIORITY=${HA_PRIORITY:-200}
HA_AUTH_PASS=${HA_AUTH_PASS:-ispvr42}

NODE_INTERNET_IP=${NODE_INTERNET_IP:-200.0.0.10}
NODE_WAN_CLIENT_IP=${NODE_WAN_CLIENT_IP:-10.10.0.1}
NODE_WAN_SERVER_IP=${NODE_WAN_SERVER_IP:-10.20.0.1}
NODE_MGMT_IP=${NODE_MGMT_IP:-192.168.99.1}

VIP_INTERNET_IP=${VIP_INTERNET_IP:-200.0.0.10}
VIP_WAN_CLIENT_IP=${VIP_WAN_CLIENT_IP:-10.10.0.1}
VIP_WAN_SERVER_IP=${VIP_WAN_SERVER_IP:-10.20.0.1}
VIP_MGMT_IP=${VIP_MGMT_IP:-192.168.99.1}

PEER_INTERNET_NODE_IP=${PEER_INTERNET_NODE_IP:-$NODE_INTERNET_IP}
PEER_WAN_CLIENT_NODE_IP=${PEER_WAN_CLIENT_NODE_IP:-$NODE_WAN_CLIENT_IP}
PEER_WAN_SERVER_NODE_IP=${PEER_WAN_SERVER_NODE_IP:-$NODE_WAN_SERVER_IP}
PEER_MGMT_NODE_IP=${PEER_MGMT_NODE_IP:-$NODE_MGMT_IP}

CLIENT_WAN_VIP=${CLIENT_WAN_VIP:-10.10.0.2}
SERVER_WAN_VIP=${SERVER_WAN_VIP:-10.20.0.2}
CLIENT_MGMT_VIP=${CLIENT_MGMT_VIP:-192.168.99.10}
SERVER_MGMT_VIP=${SERVER_MGMT_VIP:-192.168.99.20}
REMOTE_SYSLOG_HOST=${REMOTE_SYSLOG_HOST:-}
REMOTE_SYSLOG_PORT=${REMOTE_SYSLOG_PORT:-514}
REMOTE_SYSLOG_PROTOCOL=${REMOTE_SYSLOG_PROTOCOL:-tcp}

mkdir -p /var/log/fw /var/log/chrony
install -d -o _chrony -g _chrony -m 750 /run/chrony
echo "[$(date)] === Démarrage FW_ISP ===" | tee -a "$LOG"

rm -f /run/keepalived.pid /var/run/keepalived.pid /run/vrrp.pid /var/run/vrrp.pid \
	/run/chrony/chronyd.pid /var/run/chrony/chronyd.pid \
	/run/chrony/chronyd.sock /var/run/chrony/chronyd.sock

echo 1 > /proc/sys/net/ipv4/ip_forward

require_if_by_ip INTERNET_IF "$NODE_INTERNET_IP"
require_if_by_ip WAN_CLIENT_IF "$NODE_WAN_CLIENT_IP"
require_if_by_ip WAN_SERVER_IF "$NODE_WAN_SERVER_IP"
require_if_by_ip MGMT_IF "$NODE_MGMT_IP"
log_if_assignment INTERNET "$INTERNET_IF" "$NODE_INTERNET_IP" | tee -a "$LOG"
log_if_assignment WAN_CLIENT "$WAN_CLIENT_IF" "$NODE_WAN_CLIENT_IP" | tee -a "$LOG"
log_if_assignment WAN_SERVER "$WAN_SERVER_IF" "$NODE_WAN_SERVER_IP" | tee -a "$LOG"
log_if_assignment MGMT "$MGMT_IF" "$NODE_MGMT_IP" | tee -a "$LOG"

render_template /opt/lab/dnsmasq.conf.tmpl /etc/dnsmasq.conf \
	VIP_MGMT_IP "$VIP_MGMT_IP" \
	CLIENT_MGMT_VIP "$CLIENT_MGMT_VIP" \
	SERVER_MGMT_VIP "$SERVER_MGMT_VIP" \
	WAN_CLIENT_IF "$WAN_CLIENT_IF" \
	WAN_SERVER_IF "$WAN_SERVER_IF" \
	MGMT_IF "$MGMT_IF" \
	INTERNET_IF "$INTERNET_IF"

render_template /opt/lab/haproxy.cfg.tmpl /etc/haproxy/haproxy.cfg \
	VIP_INTERNET_IP "$VIP_INTERNET_IP" \
	VIP_MGMT_IP "$VIP_MGMT_IP"

if [ "$HA_ENABLED" = "1" ]; then
	render_template /opt/lab/keepalived.conf.tmpl /etc/keepalived/keepalived.conf \
		STATE "$HA_STATE" \
		PRIORITY "$HA_PRIORITY" \
		AUTH_PASS "$HA_AUTH_PASS" \
		NODE_INTERNET_IP "$NODE_INTERNET_IP" \
		NODE_WAN_CLIENT_IP "$NODE_WAN_CLIENT_IP" \
		NODE_WAN_SERVER_IP "$NODE_WAN_SERVER_IP" \
		NODE_MGMT_IP "$NODE_MGMT_IP" \
		PEER_INTERNET_NODE_IP "$PEER_INTERNET_NODE_IP" \
		PEER_WAN_CLIENT_NODE_IP "$PEER_WAN_CLIENT_NODE_IP" \
		PEER_WAN_SERVER_NODE_IP "$PEER_WAN_SERVER_NODE_IP" \
		PEER_MGMT_NODE_IP "$PEER_MGMT_NODE_IP" \
		VIP_INTERNET_IP "$VIP_INTERNET_IP" \
		VIP_WAN_CLIENT_IP "$VIP_WAN_CLIENT_IP" \
		VIP_WAN_SERVER_IP "$VIP_WAN_SERVER_IP" \
		VIP_MGMT_IP "$VIP_MGMT_IP" \
		INTERNET_IF "$INTERNET_IF" \
		WAN_CLIENT_IF "$WAN_CLIENT_IF" \
		WAN_SERVER_IF "$WAN_SERVER_IF" \
		MGMT_IF "$MGMT_IF" \
		ROUTER_ID "FW_ISP_${HOSTNAME^^}"
fi

replace_static_route 192.168.10.0/24 "$CLIENT_WAN_VIP"
replace_static_route 192.168.30.0/24 "$CLIENT_WAN_VIP"
replace_static_route 192.168.40.0/24 "$CLIENT_WAN_VIP"
replace_static_route 192.168.20.0/24 "$SERVER_WAN_VIP"
replace_static_route 192.168.50.0/24 "$SERVER_WAN_VIP"

/usr/local/bin/rules.sh | tee -a "$LOG"

configure_remote_syslog "$REMOTE_SYSLOG_HOST" "$REMOTE_SYSLOG_PORT" "$REMOTE_SYSLOG_PROTOCOL"
rsyslogd || true

echo "[$(date)] Démarrage de chrony (NTP)..." | tee -a "$LOG"
chronyd -x -d -f /etc/chrony/chrony.conf >> /var/log/chrony/chronyd.log 2>&1 &

echo "[$(date)] Démarrage de dnsmasq (DNS/DHCP)..." | tee -a "$LOG"
dnsmasq -k -C /etc/dnsmasq.conf &

echo "[$(date)] Démarrage de HAProxy..." | tee -a "$LOG"
haproxy -f /etc/haproxy/haproxy.cfg -D || echo "HAProxy non démarré (config par défaut)" | tee -a "$LOG"

if [ "$HA_ENABLED" = "1" ]; then
	echo "[$(date)] Démarrage de keepalived..." | tee -a "$LOG"
	keepalived -f /etc/keepalived/keepalived.conf -D || echo "keepalived non démarré" | tee -a "$LOG"
fi

echo "[$(date)] === FW_ISP opérationnel ===" | tee -a "$LOG"
tail -F /var/log/fw/startup.log
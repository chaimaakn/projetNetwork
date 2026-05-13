#!/bin/bash
# =============================================================================
# FW_CLIENT - Démarrage
# =============================================================================

set -euo pipefail

LOG=/var/log/fw/startup.log
. /usr/local/lib/lab-net.sh

HA_ENABLED=${HA_ENABLED:-0}
HA_STATE=${HA_STATE:-MASTER}
HA_PRIORITY=${HA_PRIORITY:-200}
HA_AUTH_PASS=${HA_AUTH_PASS:-clivr42}

NODE_LAN_IP=${NODE_LAN_IP:-192.168.10.1}
NODE_VOIP_IP=${NODE_VOIP_IP:-192.168.30.1}
NODE_GUEST_IP=${NODE_GUEST_IP:-192.168.40.1}
NODE_MGMT_IP=${NODE_MGMT_IP:-192.168.99.10}
NODE_WAN_IP=${NODE_WAN_IP:-10.10.0.2}

VIP_LAN_IP=${VIP_LAN_IP:-192.168.10.1}
VIP_VOIP_IP=${VIP_VOIP_IP:-192.168.30.1}
VIP_GUEST_IP=${VIP_GUEST_IP:-192.168.40.1}
VIP_MGMT_IP=${VIP_MGMT_IP:-192.168.99.10}
VIP_WAN_IP=${VIP_WAN_IP:-10.10.0.2}

PEER_LAN_NODE_IP=${PEER_LAN_NODE_IP:-$NODE_LAN_IP}
PEER_VOIP_NODE_IP=${PEER_VOIP_NODE_IP:-$NODE_VOIP_IP}
PEER_GUEST_NODE_IP=${PEER_GUEST_NODE_IP:-$NODE_GUEST_IP}
PEER_MGMT_NODE_IP=${PEER_MGMT_NODE_IP:-$NODE_MGMT_IP}
PEER_WAN_NODE_IP=${PEER_WAN_NODE_IP:-$NODE_WAN_IP}

UPSTREAM_WAN_GW=${UPSTREAM_WAN_GW:-10.10.0.1}
UPSTREAM_MGMT_DNS=${UPSTREAM_MGMT_DNS:-192.168.99.1}
PEER_VPN_WAN_IP=${PEER_VPN_WAN_IP:-10.20.0.2}

CONNTRACKD_LOCAL_IP=${CONNTRACKD_LOCAL_IP:-$NODE_MGMT_IP}
CONNTRACKD_PEER_IP=${CONNTRACKD_PEER_IP:-$PEER_MGMT_NODE_IP}
REMOTE_SYSLOG_HOST=${REMOTE_SYSLOG_HOST:-}
REMOTE_SYSLOG_PORT=${REMOTE_SYSLOG_PORT:-514}
REMOTE_SYSLOG_PROTOCOL=${REMOTE_SYSLOG_PROTOCOL:-tcp}

mkdir -p /var/log/fw /var/log/fw/suricata
touch /var/log/fw/ha-state.log
echo "[$(date)] === Démarrage FW_CLIENT ===" | tee -a "$LOG"

rm -f /run/keepalived.pid /var/run/keepalived.pid /run/vrrp.pid /var/run/vrrp.pid \
	/run/squid.pid /var/run/squid.pid \
	/run/conntrackd.pid /var/run/conntrackd.pid \
	/var/lock/conntrack.lock \
	/var/run/suricata.pid

echo 1 > /proc/sys/net/ipv4/ip_forward

require_if_by_ip LAN_IF "$NODE_LAN_IP"
require_if_by_ip VOIP_IF "$NODE_VOIP_IP"
require_if_by_ip GUEST_IF "$NODE_GUEST_IP"
require_if_by_ip MGMT_IF "$NODE_MGMT_IP"
require_if_by_ip WAN_IF "$NODE_WAN_IP"
log_if_assignment LAN "$LAN_IF" "$NODE_LAN_IP" | tee -a "$LOG"
log_if_assignment VOIP "$VOIP_IF" "$NODE_VOIP_IP" | tee -a "$LOG"
log_if_assignment GUEST "$GUEST_IF" "$NODE_GUEST_IP" | tee -a "$LOG"
log_if_assignment MGMT "$MGMT_IF" "$NODE_MGMT_IP" | tee -a "$LOG"
log_if_assignment WAN "$WAN_IF" "$NODE_WAN_IP" | tee -a "$LOG"

replace_default_route "$UPSTREAM_WAN_GW"
configure_resolver "$UPSTREAM_MGMT_DNS" labcyber.local

render_template /opt/lab/ipsec.conf.tmpl /etc/ipsec.conf \
	LOCAL_WAN_IP "$VIP_WAN_IP" \
	REMOTE_WAN_IP "$PEER_VPN_WAN_IP"

if [ "$HA_ENABLED" = "1" ]; then
	render_template /opt/lab/keepalived.conf.tmpl /etc/keepalived/keepalived.conf \
		STATE "$HA_STATE" \
		PRIORITY "$HA_PRIORITY" \
		AUTH_PASS "$HA_AUTH_PASS" \
		NODE_WAN_IP "$NODE_WAN_IP" \
		NODE_LAN_IP "$NODE_LAN_IP" \
		NODE_VOIP_IP "$NODE_VOIP_IP" \
		NODE_GUEST_IP "$NODE_GUEST_IP" \
		NODE_MGMT_IP "$NODE_MGMT_IP" \
		PEER_WAN_NODE_IP "$PEER_WAN_NODE_IP" \
		PEER_LAN_NODE_IP "$PEER_LAN_NODE_IP" \
		PEER_VOIP_NODE_IP "$PEER_VOIP_NODE_IP" \
		PEER_GUEST_NODE_IP "$PEER_GUEST_NODE_IP" \
		PEER_MGMT_NODE_IP "$PEER_MGMT_NODE_IP" \
		VIP_WAN_IP "$VIP_WAN_IP" \
		VIP_LAN_IP "$VIP_LAN_IP" \
		VIP_VOIP_IP "$VIP_VOIP_IP" \
		VIP_GUEST_IP "$VIP_GUEST_IP" \
		VIP_MGMT_IP "$VIP_MGMT_IP" \
		WAN_IF "$WAN_IF" \
		LAN_IF "$LAN_IF" \
		VOIP_IF "$VOIP_IF" \
		GUEST_IF "$GUEST_IF" \
		MGMT_IF "$MGMT_IF" \
		ROUTER_ID "FW_CLIENT_${HOSTNAME^^}"

	render_template /opt/lab/conntrackd.conf.tmpl /etc/conntrackd/conntrackd.conf \
		LOCAL_SYNC_IP "$CONNTRACKD_LOCAL_IP" \
		PEER_SYNC_IP "$CONNTRACKD_PEER_IP" \
		SYNC_IF "$MGMT_IF"

	cat > /etc/lab-ha.env <<EOF
VIP_WAN_IP=${VIP_WAN_IP}
FW_DNSMASQ_CONFIG=/tmp/dnsmasq.conf
CONNTRACKD_CONF=/etc/conntrackd/conntrackd.conf
EOF
fi

/usr/local/bin/rules.sh | tee -a "$LOG"

configure_remote_syslog "$REMOTE_SYSLOG_HOST" "$REMOTE_SYSLOG_PORT" "$REMOTE_SYSLOG_PROTOCOL"
rsyslogd || true

echo "[$(date)] Preparation de dnsmasq (DHCP LAN_CLIENT)..." | tee -a "$LOG"
sed "s/__LAN_IF__/${LAN_IF}/g" /etc/dnsmasq.conf > /tmp/dnsmasq.conf

echo "[$(date)] Démarrage de Squid (proxy/filtrage)..." | tee -a "$LOG"
touch /etc/squid/blocked_domains.txt
squid -N -f /etc/squid/squid.conf &

echo "[$(date)] Validation et démarrage de Suricata (IDS)..." | tee -a "$LOG"
suricata -T -k none -i "$LAN_IF" -c /etc/suricata/suricata.yaml -S /etc/suricata/lab.rules >> "$LOG" 2>&1
suricata -D -k none -i "$LAN_IF" -c /etc/suricata/suricata.yaml -S /etc/suricata/lab.rules -l /var/log/fw/suricata

if [ "$HA_ENABLED" = "1" ]; then
	echo "[$(date)] Démarrage de conntrackd..." | tee -a "$LOG"
	conntrackd -C /etc/conntrackd/conntrackd.conf -d || true

	echo "[$(date)] Démarrage de keepalived..." | tee -a "$LOG"
	keepalived -f /etc/keepalived/keepalived.conf -D || true

	if [ "$HA_STATE" = "MASTER" ]; then
		wait_for_ip_assignment "$VIP_WAN_IP" 20 1 || true
		/usr/local/bin/ha-state.sh master || true
	else
		/usr/local/bin/ha-state.sh backup || true
	fi
else
	echo "[$(date)] Démarrage de dnsmasq (DHCP LAN_CLIENT)..." | tee -a "$LOG"
	dnsmasq -k -C /tmp/dnsmasq.conf &
	echo "[$(date)] Démarrage IPsec strongSwan..." | tee -a "$LOG"
	ipsec start || true
	sleep 5
	ipsec statusall || true
fi

echo "[$(date)] === FW_CLIENT opérationnel ===" | tee -a "$LOG"
tail -F /var/log/fw/startup.log /var/log/fw/ha-state.log
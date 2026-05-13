#!/bin/bash
# =============================================================================
# FW_SERVER - Démarrage
# =============================================================================

set -euo pipefail

LOG=/var/log/fw/startup.log
. /usr/local/lib/lab-net.sh

HA_ENABLED=${HA_ENABLED:-0}
HA_STATE=${HA_STATE:-MASTER}
HA_PRIORITY=${HA_PRIORITY:-200}
HA_AUTH_PASS=${HA_AUTH_PASS:-srvvr42}

NODE_LAN_IP=${NODE_LAN_IP:-192.168.20.1}
NODE_DMZ_IP=${NODE_DMZ_IP:-192.168.50.1}
NODE_WAN_IP=${NODE_WAN_IP:-10.20.0.2}
NODE_MGMT_IP=${NODE_MGMT_IP:-192.168.99.20}

VIP_LAN_IP=${VIP_LAN_IP:-192.168.20.1}
VIP_DMZ_IP=${VIP_DMZ_IP:-192.168.50.1}
VIP_WAN_IP=${VIP_WAN_IP:-10.20.0.2}
VIP_MGMT_IP=${VIP_MGMT_IP:-192.168.99.20}

PEER_LAN_NODE_IP=${PEER_LAN_NODE_IP:-$NODE_LAN_IP}
PEER_DMZ_NODE_IP=${PEER_DMZ_NODE_IP:-$NODE_DMZ_IP}
PEER_WAN_NODE_IP=${PEER_WAN_NODE_IP:-$NODE_WAN_IP}
PEER_MGMT_NODE_IP=${PEER_MGMT_NODE_IP:-$NODE_MGMT_IP}

UPSTREAM_WAN_GW=${UPSTREAM_WAN_GW:-10.20.0.1}
UPSTREAM_MGMT_DNS=${UPSTREAM_MGMT_DNS:-192.168.99.1}
PEER_VPN_WAN_IP=${PEER_VPN_WAN_IP:-10.10.0.2}

CONNTRACKD_LOCAL_IP=${CONNTRACKD_LOCAL_IP:-$NODE_MGMT_IP}
CONNTRACKD_PEER_IP=${CONNTRACKD_PEER_IP:-$PEER_MGMT_NODE_IP}

mkdir -p /var/log/fw /var/log/chrony
install -d -o _chrony -g _chrony -m 750 /run/chrony
touch /var/log/fw/ha-state.log
echo "[$(date)] === Démarrage FW_SERVER ===" | tee -a "$LOG"

rm -f /run/keepalived.pid /var/run/keepalived.pid /run/vrrp.pid /var/run/vrrp.pid \
	/run/conntrackd.pid /var/run/conntrackd.pid \
	/var/lock/conntrack.lock \
	/run/chrony/chronyd.pid /var/run/chrony/chronyd.pid \
	/run/chrony/chronyd.sock /var/run/chrony/chronyd.sock

echo 1 > /proc/sys/net/ipv4/ip_forward

require_if_by_ip LAN_IF "$NODE_LAN_IP"
require_if_by_ip DMZ_IF "$NODE_DMZ_IP"
require_if_by_ip WAN_IF "$NODE_WAN_IP"
require_if_by_ip MGMT_IF "$NODE_MGMT_IP"
log_if_assignment LAN "$LAN_IF" "$NODE_LAN_IP" | tee -a "$LOG"
log_if_assignment DMZ "$DMZ_IF" "$NODE_DMZ_IP" | tee -a "$LOG"
log_if_assignment WAN "$WAN_IF" "$NODE_WAN_IP" | tee -a "$LOG"
log_if_assignment MGMT "$MGMT_IF" "$NODE_MGMT_IP" | tee -a "$LOG"

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
		NODE_DMZ_IP "$NODE_DMZ_IP" \
		NODE_MGMT_IP "$NODE_MGMT_IP" \
		PEER_WAN_NODE_IP "$PEER_WAN_NODE_IP" \
		PEER_LAN_NODE_IP "$PEER_LAN_NODE_IP" \
		PEER_DMZ_NODE_IP "$PEER_DMZ_NODE_IP" \
		PEER_MGMT_NODE_IP "$PEER_MGMT_NODE_IP" \
		VIP_WAN_IP "$VIP_WAN_IP" \
		VIP_LAN_IP "$VIP_LAN_IP" \
		VIP_DMZ_IP "$VIP_DMZ_IP" \
		VIP_MGMT_IP "$VIP_MGMT_IP" \
		WAN_IF "$WAN_IF" \
		LAN_IF "$LAN_IF" \
		DMZ_IF "$DMZ_IF" \
		MGMT_IF "$MGMT_IF" \
		ROUTER_ID "FW_SERVER_${HOSTNAME^^}"

	render_template /opt/lab/conntrackd.conf.tmpl /etc/conntrackd/conntrackd.conf \
		LOCAL_SYNC_IP "$CONNTRACKD_LOCAL_IP" \
		PEER_SYNC_IP "$CONNTRACKD_PEER_IP" \
		SYNC_IF "$MGMT_IF"

	cat > /etc/lab-ha.env <<EOF
VIP_WAN_IP=${VIP_WAN_IP}
CONNTRACKD_CONF=/etc/conntrackd/conntrackd.conf
EOF
fi

/usr/local/bin/rules.sh | tee -a "$LOG"

rsyslogd || true

echo "[$(date)] Démarrage chrony (NTP serveur)..." | tee -a "$LOG"
chronyd -x -d -f /etc/chrony/chrony.conf >> /var/log/chrony/chronyd.log 2>&1 &

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
	echo "[$(date)] Démarrage IPsec strongSwan..." | tee -a "$LOG"
	ipsec start || true
	sleep 5
	ipsec statusall || true
fi

echo "[$(date)] === FW_SERVER opérationnel ===" | tee -a "$LOG"
tail -F /var/log/fw/startup.log /var/log/fw/ha-state.log
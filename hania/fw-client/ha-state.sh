#!/bin/bash

set -euo pipefail

STATE=${1:-unknown}
LOG=/var/log/fw/ha-state.log
. /usr/local/lib/lab-net.sh

if [ -f /etc/lab-ha.env ]; then
	# shellcheck disable=SC1091
	. /etc/lab-ha.env
fi

FW_DNSMASQ_CONFIG=${FW_DNSMASQ_CONFIG:-/tmp/dnsmasq.conf}
CONNTRACKD_CONF=${CONNTRACKD_CONF:-/etc/conntrackd/conntrackd.conf}

log() {
	echo "[$(date)] [HA] $1" | tee -a "$LOG"
}

start_dnsmasq() {
	if ! pgrep -f "dnsmasq -k -C ${FW_DNSMASQ_CONFIG}" >/dev/null 2>&1; then
		log "Demarrage de dnsmasq sur le noeud maitre"
		dnsmasq -k -C "$FW_DNSMASQ_CONFIG" >/var/log/fw/dnsmasq-foreground.log 2>&1 &
	fi
}

stop_dnsmasq() {
	pkill -f "dnsmasq -k -C ${FW_DNSMASQ_CONFIG}" >/dev/null 2>&1 || true
}

start_ipsec() {
	log "Activation d'IPsec"
	ipsec stop >/dev/null 2>&1 || true
	ip xfrm state flush >/dev/null 2>&1 || true
	ip xfrm policy flush >/dev/null 2>&1 || true
	ipsec start >/dev/null 2>&1 || true
	sleep 5
	ipsec statusall >> "$LOG" 2>&1 || true
}

stop_ipsec() {
	log "Arret d'IPsec"
	ipsec stop >/dev/null 2>&1 || true
	ip xfrm state flush >/dev/null 2>&1 || true
	ip xfrm policy flush >/dev/null 2>&1 || true
}

case "$STATE" in
	master)
		log "Transition MASTER"
		wait_for_ip_assignment "${VIP_WAN_IP:-}" 20 1 || true
		conntrackd -C "$CONNTRACKD_CONF" -c >/dev/null 2>&1 || true
		conntrackd -C "$CONNTRACKD_CONF" -n >/dev/null 2>&1 || true
		start_dnsmasq
		start_ipsec
		;;
	backup|fault)
		log "Transition ${STATE^^}"
		stop_dnsmasq
		stop_ipsec
		;;
	*)
		log "Etat HA inconnu: $STATE"
		;;
esac
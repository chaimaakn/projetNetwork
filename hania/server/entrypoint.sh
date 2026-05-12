#!/bin/bash

set -e

GATEWAY_IP=${GATEWAY_IP:-192.168.20.1}
DNS_SERVER=${DNS_SERVER:-192.168.99.1}
SEARCH_DOMAIN=${SEARCH_DOMAIN:-labcyber.local}

ip route del default 2>/dev/null || true
ip route add default via "$GATEWAY_IP" || true

if [ -n "$DNS_SERVER" ]; then
	echo "nameserver ${DNS_SERVER}" > /etc/resolv.conf
	if [ -n "$SEARCH_DOMAIN" ]; then
		echo "search ${SEARCH_DOMAIN}" >> /etc/resolv.conf
	fi
fi

# Démarrer SSH
service ssh start

# Démarrer Nginx au premier plan
echo "[SERVER] Web + SSH démarrés sur $(hostname -I)"
echo "[SERVER] Comptes (à durcir Phase 3) : admin/admin123, test/test, root/toor"

nginx -g "daemon off;"
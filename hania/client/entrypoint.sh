#!/bin/bash

set -e

GATEWAY_IP=${GATEWAY_IP:-192.168.10.1}
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

echo "[CLIENT] Démarré - IP: $(hostname -I) - GW: ${GATEWAY_IP}"
echo "[CLIENT] Utilisez: docker exec -it client1 bash"

# Garde le conteneur actif
tail -f /dev/null
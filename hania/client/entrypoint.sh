#!/bin/bash
# Force la passerelle vers FW_CLIENT (192.168.10.1)
ip route del default 2>/dev/null || true
ip route add default via 192.168.10.1 || true

echo "nameserver 192.168.99.1" > /etc/resolv.conf
echo "search labcyber.local" >> /etc/resolv.conf

echo "[CLIENT] Démarré - IP: $(hostname -I) - GW: 192.168.10.1"
echo "[CLIENT] Utilisez: docker exec -it client1 bash"

# Garde le conteneur actif
tail -f /dev/null
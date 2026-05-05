#!/bin/bash
ip route del default 2>/dev/null || true
ip route add default via 192.168.20.1 || true

echo "nameserver 192.168.99.1" > /etc/resolv.conf
echo "search labcyber.local" >> /etc/resolv.conf

# Démarrer SSH
service ssh start

# Démarrer Nginx au premier plan
echo "[SERVER] Web + SSH démarrés sur $(hostname -I)"
echo "[SERVER] Comptes (à durcir Phase 3) : admin/admin123, test/test, root/toor"

nginx -g "daemon off;"
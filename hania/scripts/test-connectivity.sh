#!/bin/bash
# =============================================================================
# Script de tests de connectivite - Phase 1 (Jour 1)
# Verifie que l'architecture est fonctionnelle
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YEL='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YEL}[..]${NC}   $1"; }

ping_check() {
    local from=$1
    local to=$2
    local desc=$3

    info "Ping depuis $from vers $to ($desc)"
    if docker exec "$from" ping -c 2 -W 3 "$to" >/dev/null 2>&1; then
        ok "$from -> $to ($desc)"
    else
        fail "$from -> $to ($desc)"
    fi
}

echo "=========================================="
echo "  Tests de connectivite - LabCyber Docker  "
echo "=========================================="

echo ""
echo "--- Tests intra-LAN ---"
ping_check client1   192.168.10.11 "client1 -> client2"
ping_check client1   192.168.10.1  "client1 -> FW_CLIENT (gateway)"

echo ""
echo "--- Tests vers les firewalls ---"
ping_check client1   10.10.0.1     "client1 -> FW_ISP (WAN client)"
ping_check webserver 192.168.20.1  "webserver -> FW_SERVER (gateway)"

echo ""
echo "--- Tests cross-LAN via VPN IPsec ---"
ping_check client1   192.168.20.10 "client1 -> webserver (via VPN)"
ping_check client1   192.168.20.11 "client1 -> sshserver (via VPN)"

echo ""
echo "--- Tests Internet (NAT) ---"
ping_check client1   8.8.8.8       "client1 -> Internet (8.8.8.8)"

echo ""
echo "--- Tests DNS ---"
info "Resolution DNS depuis client1"
if docker exec client1 nslookup web.labcyber.local 192.168.99.1 2>&1 | grep -q "192.168.20.10"; then
    ok "DNS resolution OK"
else
    fail "DNS resolution KO"
fi

echo ""
echo "--- Statut VPN IPsec ---"
docker exec fw-client ipsec statusall 2>/dev/null | grep -E "site-to-site|ESTABLISHED|INSTALLED" || \
    fail "VPN non etabli - verifier ipsec.conf"

echo ""
echo "=========================================="
echo "Pour aller plus loin :"
echo "  docker exec -it client1 bash"
echo "  docker exec -it kali bash"
echo "  docker logs fw-client | tail -50"
echo "=========================================="
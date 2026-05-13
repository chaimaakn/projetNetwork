#!/bin/bash
# =============================================================================
# Script de tests de connectivite - Phase 1 (Jour 1)
# Verifie que l'architecture est fonctionnelle
# =============================================================================

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

cd "$PROJECT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YEL='\033[1;33m'
NC='\033[0m'

FAILURES=0

ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILURES=$((FAILURES + 1))
}
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

wait_for_container_shell() {
    local description=$1
    local container_name=$2
    local shell_command=$3
    local max_attempts=${4:-10}
    local delay_seconds=${5:-2}
    local attempt=1

    info "$description"
    while [ "$attempt" -le "$max_attempts" ]; do
        if docker exec "$container_name" bash -lc "$shell_command" >/dev/null 2>&1; then
            ok "$description"
            return 0
        fi

        sleep "$delay_seconds"
        attempt=$((attempt + 1))
    done

    fail "$description"
    return 1
}

wait_for_vpn() {
    local max_attempts=${1:-15}
    local delay_seconds=${2:-2}
    local attempt=1

    info "Attente de l'etablissement du tunnel IPsec"
    while [ "$attempt" -le "$max_attempts" ]; do
        if docker exec fw-client bash -lc "ipsec statusall | grep -Eq 'ESTABLISHED|INSTALLED'" >/dev/null 2>&1; then
            ok "Tunnel IPsec operationnel"
            return 0
        fi

        sleep "$delay_seconds"
        attempt=$((attempt + 1))
    done

    fail "Tunnel IPsec indisponible"
    return 1
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
if wait_for_vpn; then
    docker exec client1 bash -lc "ip neigh flush all >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    wait_for_container_shell "HTTP depuis client1 vers webserver (via VPN)" "client1" "curl -fsS http://192.168.20.10 >/dev/null" 10 2
    wait_for_container_shell "SSH depuis client1 vers sshserver (via VPN)" "client1" "nc -zw 3 192.168.20.11 22 >/dev/null" 10 2
fi

echo ""
echo "--- Tests Internet (NAT) ---"
ping_check client1   8.8.8.8       "client1 -> Internet (8.8.8.8)"

echo ""
echo "--- Tests DNS ---"
info "Resolution DNS depuis client1"
if docker exec client1 getent hosts web.labcyber.local 2>/dev/null | grep -q "192.168.20.10"; then
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

if [ "$FAILURES" -gt 0 ]; then
    echo "${FAILURES} test(s) ont echoue."
    exit 1
fi
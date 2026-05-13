#!/bin/bash

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

check_command() {
	local description=$1
	shift

	if "$@" >/dev/null 2>&1; then
		ok "$description"
	else
		fail "$description"
	fi
}

check_running_service() {
	local service_name=$1
	if docker compose ps --services --status running | grep -qx "$service_name"; then
		ok "Service compose actif: $service_name"
	else
		fail "Service compose inactif: $service_name"
	fi
}

check_container_command() {
	local description=$1
	local container_name=$2
	shift 2

	if docker exec "$container_name" "$@" >/dev/null 2>&1; then
		ok "$description"
	else
		fail "$description"
	fi
}

check_container_shell() {
	local description=$1
	local container_name=$2
	local shell_command=$3

	if docker exec "$container_name" bash -lc "$shell_command" >/dev/null 2>&1; then
		ok "$description"
	else
		fail "$description"
	fi
}

wait_for_container_shell() {
	local description=$1
	local container_name=$2
	local shell_command=$3
	local max_attempts=${4:-10}
	local delay_seconds=${5:-2}
	local attempt=1

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

echo "=========================================="
echo "   Tests exhaustifs - LabCyber Docker     "
echo "=========================================="

echo ""
echo "--- Smoke test ---"
if bash ./scripts/test-connectivity.sh; then
	ok "Smoke test global"
else
	fail "Smoke test global"
fi

echo ""
echo "--- Matrice de flux Phase 2 ---"
if bash ./scripts/test-vlan-matrix.sh; then
	ok "Matrice de flux Phase 2"
else
	fail "Matrice de flux Phase 2"
fi

echo ""
echo "--- Hardening avance ---"
if bash ./scripts/test-policy-hardening.sh; then
	ok "Hardening avance"
else
	fail "Hardening avance"
fi

echo ""
echo "--- IDS / Suricata ---"
if bash ./scripts/test-suricata.sh; then
	ok "Suricata IDS"
else
	fail "Suricata IDS"
fi

echo ""
echo "--- Haute disponibilite ---"
if bash ./scripts/test-ha.sh; then
	ok "Haute disponibilite"
else
	fail "Haute disponibilite"
fi

echo ""
echo "--- Etat des services Docker ---"
for service_name in fw-isp fw-isp-2 fw-client fw-client-2 fw-server fw-server-2 client1 client2 voip1 guest1 webserver sshserver dmz-web kali internet-probe uptime-kuma; do
	check_running_service "$service_name"
done

echo ""
echo "--- Daemons principaux ---"
check_container_shell "fw-client: dnsmasq actif" "fw-client" "pgrep -x 'dnsmasq'"
check_container_shell "fw-client: squid actif" "fw-client" "pgrep -x 'squid'"
wait_for_container_shell "fw-client: suricata actif" "fw-client" "pidof suricata >/dev/null || pgrep -f 'suricata -D' >/dev/null" 10 2
check_container_shell "fw-client: strongSwan actif" "fw-client" "pgrep -f 'charon|starter'"
check_container_shell "fw-client: keepalived actif" "fw-client" "pgrep -x 'keepalived'"
check_container_shell "fw-client: conntrackd actif" "fw-client" "pgrep -x 'conntrackd'"
check_container_shell "fw-client-2: keepalived actif" "fw-client-2" "pgrep -x 'keepalived'"
check_container_shell "fw-client-2: conntrackd actif" "fw-client-2" "pgrep -x 'conntrackd'"
wait_for_container_shell "fw-server: chronyd actif" "fw-server" "pgrep -f 'chronyd'" 15 2
check_container_shell "fw-server: strongSwan actif" "fw-server" "pgrep -f 'charon|starter'"
check_container_shell "fw-server: keepalived actif" "fw-server" "pgrep -x 'keepalived'"
check_container_shell "fw-server: conntrackd actif" "fw-server" "pgrep -x 'conntrackd'"
check_container_shell "fw-server-2: keepalived actif" "fw-server-2" "pgrep -x 'keepalived'"
check_container_shell "fw-server-2: conntrackd actif" "fw-server-2" "pgrep -x 'conntrackd'"
check_container_shell "fw-isp: dnsmasq actif" "fw-isp" "pgrep -f 'dnsmasq'"
wait_for_container_shell "fw-isp: chronyd actif" "fw-isp" "pgrep -f 'chronyd'" 15 2
check_container_shell "fw-isp: haproxy actif" "fw-isp" "pgrep -f 'haproxy'"
check_container_shell "fw-isp: keepalived actif" "fw-isp" "pgrep -x 'keepalived'"
check_container_shell "fw-isp-2: keepalived actif" "fw-isp-2" "pgrep -x 'keepalived'"

echo ""
echo "--- DNS et routage ---"
check_container_shell "client1: route par defaut via fw-client" "client1" "ip route | grep -q '^default via 192.168.10.1'"
check_container_shell "webserver: route par defaut via fw-server" "webserver" "ip route | grep -q '^default via 192.168.20.1'"
check_container_shell "DNS interne web.labcyber.local" "client1" "getent hosts web.labcyber.local | grep -q '192.168.20.10'"
check_container_shell "DNS externe example.com" "client1" "getent hosts example.com >/dev/null"

echo ""
echo "--- Chemins applicatifs ---"
docker exec client1 bash -lc "ip neigh flush all >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
wait_for_container_shell "HTTP interne via VPN" "client1" "curl -fsS http://192.168.20.10 | grep -q 'LabCyber Web Server'" 10 2
check_container_shell "SSH joignable via VPN" "client1" "nc -z 192.168.20.11 22"
check_container_shell "HTTP DMZ via VPN" "client1" "curl -fsS http://192.168.50.10 | grep -q 'LabCyber Web Server'"
check_container_shell "Internet simule -> DMZ HTTP" "internet-probe" "curl -fsS http://192.168.50.10 | grep -q 'LabCyber Web Server'"
check_container_shell "Frontend public HAProxy" "fw-isp" "curl -fsS http://200.0.0.10 | grep -q 'LabCyber Web Server'"
check_container_shell "Proxy Squid utilisable depuis client1" "client1" "curl -fsSI -x http://192.168.10.1:3128 http://example.com >/dev/null"
check_command "Uptime Kuma accessible depuis l'hote" curl -fsSI http://127.0.0.1:3001

echo ""
echo "--- VPN et temps ---"
check_container_shell "Tunnel IPsec etabli" "fw-client" "ipsec statusall | grep -Eq 'ESTABLISHED|INSTALLED'"
wait_for_container_shell "fw-server synchronise son NTP via fw-isp" "fw-server" "chronyc sources -n | grep -Eq '^\^[\*\+]\s+(fw-isp|192\\.168\\.99\\.1)'" 20 4

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) ont echoue."
	exit 1
fi

echo "Tous les tests exhaustifs ont reussi."
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

check_container_shell() {
	local description=$1
	local container_name=$2
	local shell_command=$3

	info "$description"
	if docker exec "$container_name" bash -lc "$shell_command" >/dev/null 2>&1; then
		ok "$description"
	else
		fail "$description"
	fi
}

wait_for_suricata() {
	local max_attempts=${1:-20}
	local delay_seconds=${2:-2}
	local attempt=1

	info "Attente de la disponibilite de Suricata"
	while [ "$attempt" -le "$max_attempts" ]; do
		if docker exec fw-client bash -lc "pgrep -f suricata >/dev/null && test -d /var/log/fw/suricata" >/dev/null 2>&1; then
			ok "Suricata disponible"
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	fail "Suricata indisponible"
	return 1
}

reset_suricata_logs() {
	info "Reinitialisation des logs Suricata"
	docker exec fw-client bash -lc "mkdir -p /var/log/fw/suricata && : > /var/log/fw/suricata/fast.log && : > /var/log/fw/suricata/eve.json" >/dev/null 2>&1 || true
}

echo "=========================================="
echo " Suricata IDS - Phase 2                   "
echo "=========================================="

echo ""
echo "--- Presence de la configuration ---"
check_container_shell "Binaire Suricata installe" "fw-client" "command -v suricata >/dev/null"
check_container_shell "Regle BitTorrent versionnee" "fw-client" "grep -q 'sid:4200001' /etc/suricata/lab.rules"
check_container_shell "Regle SSH burst versionnee" "fw-client" "grep -q 'sid:4200002' /etc/suricata/lab.rules"

echo ""
echo "--- Detection IDS ---"
if wait_for_suricata; then
	reset_suricata_logs
	info "Generation d'un marqueur BitTorrent de laboratoire"
	docker exec client1 bash -lc 'printf "GET / HTTP/1.1\r\nHost: 192.168.50.10\r\nX-Lab: BitTorrent\r\nConnection: close\r\n\r\n" | nc -w 2 192.168.50.10 80 >/dev/null 2>&1 || true'
	sleep 2
	check_container_shell "Alerte BitTorrent detectee" "fw-client" "grep -q 'LAB Suricata BitTorrent marker detected' /var/log/fw/suricata/fast.log"

	info "Generation d'une rafale SSH de laboratoire"
	docker exec client1 bash -lc 'for i in $(seq 1 6); do nc -zw 1 192.168.20.11 22 >/dev/null 2>&1 || true; done'
	sleep 2
	check_container_shell "Alerte SSH burst detectee" "fw-client" "grep -q 'LAB Suricata repeated SSH connection attempts' /var/log/fw/suricata/fast.log"
fi

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) Suricata ont echoue."
	exit 1
fi

echo "Suricata IDS valide."
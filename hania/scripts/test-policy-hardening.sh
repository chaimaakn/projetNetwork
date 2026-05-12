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

wait_for_proxy() {
	local max_attempts=${1:-20}
	local delay_seconds=${2:-2}
	local attempt=1

	info "Attente de la disponibilite du proxy Squid"
	while [ "$attempt" -le "$max_attempts" ]; do
		if docker exec client1 bash -lc "nc -zw 2 192.168.10.1 3128" >/dev/null 2>&1; then
			ok "Proxy Squid disponible"
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	fail "Proxy Squid indisponible"
	return 1
}

echo "=========================================="
echo " Hardening avancé - Phase 2               "
echo "=========================================="

echo ""
echo "--- Objets et groupes fw-client ---"
check_container_shell "Jeu ipset users_net present" "fw-client" "ipset list users_net | grep -q '192.168.10.0/24'"
check_container_shell "Jeu ipset servers_net present" "fw-client" "ipset list servers_net | grep -q '192.168.20.0/24'"
check_container_shell "Jeu ipset blocked_external present" "fw-client" "ipset list blocked_external | grep -q '169.254.0.0/16'"
check_container_shell "Jeu ipset web_ports present" "fw-client" "ipset list web_ports | grep -Eq '(^| )80( |$)'"

echo ""
echo "--- Filtrage web Squid ---"
check_container_shell "Liste de domaines bloques versionnee" "fw-client" "grep -q '^.facebook.com$' /etc/squid/blocked_domains.txt"
if wait_for_proxy; then
	check_container_shell "facebook bloque par le proxy" "client1" 'test "$(curl -sSI -o /dev/null -w '\''%{http_code}'\'' -x http://192.168.10.1:3128 http://www.facebook.com)" = "403"'
	check_container_shell "mot-cle malware bloque par le proxy" "client1" 'test "$(curl -sSI -o /dev/null -w '\''%{http_code}'\'' -x http://192.168.10.1:3128 http://example.com/malware)" = "403"'
	check_container_shell "domaine legitime autorise par le proxy" "client1" 'code=$(curl -sSI -o /dev/null -w '\''%{http_code}'\'' -x http://192.168.10.1:3128 http://example.com); [[ "$code" =~ ^(200|301|302|307|308)$ ]]'
fi

echo ""
echo "--- Garde-fous ISP ---"
check_container_shell "Blocage FTP sortant configure" "fw-isp" "iptables -S FORWARD | grep -q -- '--dports 21,23,139,445'"
check_container_shell "Blocage NetBIOS sortant configure" "fw-isp" "iptables -S FORWARD | grep -q -- '--dport 137:138'"
check_container_shell "Connlimit anti-abus configure" "fw-isp" "iptables -S FORWARD | grep -q -- '--connlimit-above 50'"
check_container_shell "Rate-limit ICMP configure" "fw-isp" "iptables -S FORWARD | grep -Eq -- '--limit 5/(sec|second)'"

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) de hardening ont echoue."
	exit 1
fi

echo "Hardening avance valide."
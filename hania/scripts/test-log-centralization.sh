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

MARKER_SUFFIX=$(date +%s)
FWISP_MARKER="LAB_REMOTE_FWISP_${MARKER_SUFFIX}"
SSHSERVER_MARKER="LAB_REMOTE_SSHSERVER_${MARKER_SUFFIX}"

echo "=========================================="
echo " Centralisation des logs Phase 4         "
echo "=========================================="

echo ""
echo "--- Collecteur central ---"
if docker compose ps --services --status running | grep -qx log-collector; then
	ok "Service compose actif: log-collector"
else
	fail "Service compose inactif: log-collector"
fi
check_container_shell "log-collector: rsyslog ecoute en 514" "log-collector" "ss -ltnu | grep -q ':514 '"

echo ""
echo "--- Forwarding firewall ---"
info "Emission d'un marqueur depuis fw-isp"
docker exec fw-isp bash -lc "logger -t phase4-test '${FWISP_MARKER}'"
wait_for_container_shell "fw-isp remonte son marqueur au collecteur" "log-collector" "grep -R '${FWISP_MARKER}' /var/log/remote/fw-isp 2>/dev/null" 20 2

echo ""
echo "--- Forwarding sshserver ---"
info "Emission d'un marqueur depuis sshserver"
docker exec sshserver bash -lc "logger -t phase4-test '${SSHSERVER_MARKER}'"
wait_for_container_shell "sshserver remonte son marqueur au collecteur" "log-collector" "grep -R '${SSHSERVER_MARKER}' /var/log/remote/sshserver 2>/dev/null"

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) de centralisation de logs ont echoue."
	exit 1
fi

echo "Centralisation des logs validee."
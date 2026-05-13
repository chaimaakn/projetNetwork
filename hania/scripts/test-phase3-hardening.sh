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

check_container_not_shell() {
	local description=$1
	local container_name=$2
	local shell_command=$3

	if docker exec "$container_name" bash -lc "$shell_command" >/dev/null 2>&1; then
		fail "$description"
	else
		ok "$description"
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

echo "=========================================="
echo " Hardening Phase 3                        "
echo "=========================================="

echo ""
echo "--- SSH cible durcie ---"
check_container_shell "sshserver: SSH ecoute toujours" "sshserver" "ss -ltn | grep -q ':22 '"
check_container_shell "sshserver: root login desactive" "sshserver" "grep -Eq '^PermitRootLogin no$' /etc/ssh/sshd_config"
check_container_shell "sshserver: password auth desactivee" "sshserver" "grep -Eq '^PasswordAuthentication no$' /etc/ssh/sshd_config"
check_container_shell "sshserver: acces restreint a admin" "sshserver" "grep -Eq '^AllowUsers admin$' /etc/ssh/sshd_config"
check_container_shell "sshserver: max auth tries durci" "sshserver" "grep -Eq '^MaxAuthTries 3$' /etc/ssh/sshd_config"
check_container_shell "sshserver: fail2ban actif" "sshserver" "fail2ban-client status sshd | grep -q 'Status for the jail: sshd'"
check_container_shell "sshserver: mot de passe root verrouille" "sshserver" "passwd -S root | awk '{print \$2}' | grep -q '^L$'"

echo ""
echo "--- Surface d'exposition reduite ---"
check_container_not_shell "webserver: SSH desactive" "webserver" "ss -ltn | grep -q ':22 '"
check_container_not_shell "dmz-web: SSH desactive" "dmz-web" "ss -ltn | grep -q ':22 '"

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) de hardening Phase 3 ont echoue."
	exit 1
fi

echo "Hardening Phase 3 valide."
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

expect_allow() {
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

expect_deny() {
    local description=$1
    local container_name=$2
    local shell_command=$3

    info "$description"
    if docker exec "$container_name" bash -lc "$shell_command" >/dev/null 2>&1; then
        fail "$description"
    else
        ok "$description"
    fi
}

echo "=========================================="
echo "   Matrice de flux - Phase 2              "
echo "=========================================="

echo ""
echo "--- USERS ---"
expect_allow "USERS -> SERVERS HTTP" "client1" "curl -fsS http://192.168.20.10 >/dev/null"
expect_allow "USERS -> SERVERS SSH" "client1" "nc -zw 3 192.168.20.11 22"
expect_deny  "USERS -> SERVERS SMB interdit" "client1" "nc -zw 3 192.168.20.10 445"
expect_allow "USERS -> DMZ HTTP" "client1" "curl -fsS http://192.168.50.10 >/dev/null"
expect_deny  "USERS -> DMZ SSH interdit" "client1" "nc -zw 3 192.168.50.10 22"
expect_deny  "USERS -> MGMT interdit" "client1" "nc -zw 3 192.168.99.10 22"

echo ""
echo "--- GUEST ---"
expect_allow "GUEST -> Internet HTTP" "guest1" "curl -fsSI http://example.com >/dev/null"
expect_deny  "GUEST -> SERVERS HTTP interdit" "guest1" "nc -zw 3 192.168.20.10 80"
expect_deny  "GUEST -> DMZ HTTP interdit" "guest1" "nc -zw 3 192.168.50.10 80"
expect_deny  "GUEST -> MGMT interdit" "guest1" "nc -zw 3 192.168.99.10 22"

echo ""
echo "--- VOIP ---"
expect_allow "VOIP -> DNS interne" "voip1" "getent hosts web.labcyber.local >/dev/null"
expect_deny  "VOIP -> SERVERS HTTP interdit" "voip1" "nc -zw 3 192.168.20.10 80"
expect_deny  "VOIP -> DMZ HTTP interdit" "voip1" "nc -zw 3 192.168.50.10 80"

echo ""
echo "--- INTERNET SIMULE ---"
expect_allow "Internet -> DMZ HTTP" "internet-probe" "curl -fsS http://192.168.50.10 >/dev/null"
expect_deny  "Internet -> SERVERS HTTP interdit" "internet-probe" "nc -zw 3 192.168.20.10 80"
expect_deny  "Internet -> MGMT interdit" "internet-probe" "nc -zw 3 192.168.99.10 22"

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
    echo "${FAILURES} test(s) de matrice ont echoue."
    exit 1
fi

echo "Matrice de flux validee."
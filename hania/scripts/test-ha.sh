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

cleanup() {
	docker start fw-isp fw-client fw-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

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

wait_for_container_shell() {
	local description=$1
	local container_name=$2
	local shell_command=$3
	local max_attempts=${4:-20}
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

get_conntrackd_external_created() {
	local container_name=$1
	local current_value

	current_value=$(docker exec "$container_name" bash -lc "conntrackd -s" 2>/dev/null | awk '/cache external:/{capture=1; next} capture && /connections created:/{print $3; exit}')
	if [ -z "$current_value" ]; then
		echo 0
	else
		echo "$current_value"
	fi
}

wait_for_conntrackd_created_increase() {
	local description=$1
	local container_name=$2
	local baseline_value=$3
	local max_attempts=${4:-10}
	local delay_seconds=${5:-2}
	local attempt=1
	local current_value=0

	info "$description"
	while [ "$attempt" -le "$max_attempts" ]; do
		current_value=$(get_conntrackd_external_created "$container_name")
		if [ "$current_value" -gt "$baseline_value" ]; then
			ok "$description"
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	fail "$description"
	return 1
}

wait_for_vip_owner() {
	local description=$1
	local container_name=$2
	local vip_ip=$3
	local max_attempts=${4:-30}
	local delay_seconds=${5:-2}
	local attempt=1

	info "$description"
	while [ "$attempt" -le "$max_attempts" ]; do
		if docker exec "$container_name" bash -lc "ip -o -4 addr show | grep -q ' ${vip_ip}/'" >/dev/null 2>&1; then
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
	local description=$1
	local container_name=$2
	local max_attempts=${3:-20}
	local delay_seconds=${4:-3}
	local attempt=1

	info "$description"
	while [ "$attempt" -le "$max_attempts" ]; do
		if docker exec "$container_name" bash -lc "ipsec statusall | grep -Eq 'ESTABLISHED|INSTALLED'" >/dev/null 2>&1; then
			ok "$description"
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	fail "$description"
	return 1
}

wait_for_running_container() {
	local container_name=$1
	local max_attempts=${2:-20}
	local delay_seconds=${3:-2}
	local attempt=1

	while [ "$attempt" -le "$max_attempts" ]; do
		if docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q true; then
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	return 1
}

echo "=========================================="
echo " Haute disponibilite - Phase 2           "
echo "=========================================="

echo ""
echo "--- Daemons HA ---"
for container_name in fw-isp fw-isp-2 fw-client fw-client-2 fw-server fw-server-2; do
	check_container_shell "${container_name}: keepalived actif" "$container_name" "pgrep -x keepalived"
done
for container_name in fw-client fw-client-2 fw-server fw-server-2; do
	check_container_shell "${container_name}: conntrackd actif" "$container_name" "pgrep -x conntrackd"
done

echo ""
echo "--- Synchronisation conntrackd ---"
client_backup_external_before=$(get_conntrackd_external_created fw-client-2)
server_backup_external_before=$(get_conntrackd_external_created fw-server-2)
info "Generation de flux de reference durable"
docker exec -d client1 bash -lc "exec 3<>/dev/tcp/192.168.20.11/22; sleep 20" >/dev/null 2>&1 || true
sleep 3
wait_for_conntrackd_created_increase "fw-client-2 recoit un nouvel etat dans son cache externe" "fw-client-2" "$client_backup_external_before" 10 2
wait_for_conntrackd_created_increase "fw-server-2 recoit un nouvel etat dans son cache externe" "fw-server-2" "$server_backup_external_before" 10 2

echo ""
echo "--- Failover pfSense-like ---"
info "Arret du noeud primaire fw-isp"
docker stop fw-isp >/dev/null
wait_for_vip_owner "fw-isp-2 reprend la VIP Internet" "fw-isp-2" "200.0.0.10"
wait_for_vip_owner "fw-isp-2 reprend la VIP WAN client" "fw-isp-2" "10.10.0.1"
wait_for_vip_owner "fw-isp-2 reprend la VIP WAN server" "fw-isp-2" "10.20.0.1"
wait_for_vip_owner "fw-isp-2 reprend la VIP management" "fw-isp-2" "192.168.99.1"
docker exec internet-probe bash -lc "ip neigh flush all" >/dev/null 2>&1 || true
wait_for_container_shell "Frontend public maintenu via fw-isp-2" "internet-probe" "curl -fsS http://200.0.0.10 | grep -q 'LabCyber Web Server'" 10 2
check_container_shell "Resolution DNS maintenue via fw-isp-2" "client1" "getent hosts example.com >/dev/null"
info "Redemarrage du noeud primaire fw-isp"
docker start fw-isp >/dev/null
if wait_for_running_container fw-isp; then
	wait_for_container_shell "keepalived re-demarre sur fw-isp" "fw-isp" "pgrep -x keepalived" 10 2
	docker exec internet-probe bash -lc "ip neigh flush all" >/dev/null 2>&1 || true
	wait_for_vip_owner "fw-isp recupere la VIP Internet" "fw-isp" "200.0.0.10"
	wait_for_vip_owner "fw-isp recupere la VIP management" "fw-isp" "192.168.99.1"
else
	fail "fw-isp redemarre"
fi

echo ""
echo "--- Failover FortiGate-like client ---"
info "Arret du noeud primaire fw-client"
docker stop fw-client >/dev/null
wait_for_vip_owner "fw-client-2 reprend la VIP LAN" "fw-client-2" "192.168.10.1"
wait_for_vip_owner "fw-client-2 reprend la VIP WAN" "fw-client-2" "10.10.0.2"
wait_for_vpn "Tunnel IPsec actif sur fw-client-2" "fw-client-2"
docker exec client1 bash -lc "ip neigh flush all" >/dev/null 2>&1 || true
check_container_shell "HTTP via VPN maintenu sur fw-client-2" "client1" "curl -fsS http://192.168.20.10 | grep -q 'LabCyber Web Server'"
check_container_shell "Proxy Squid maintenu sur fw-client-2" "client1" "curl -fsSI -x http://192.168.10.1:3128 http://example.com >/dev/null"
info "Redemarrage du noeud primaire fw-client"
docker start fw-client >/dev/null
if wait_for_running_container fw-client; then
	wait_for_vip_owner "fw-client recupere la VIP LAN" "fw-client" "192.168.10.1"
	wait_for_vip_owner "fw-client recupere la VIP WAN" "fw-client" "10.10.0.2"
	wait_for_vpn "Tunnel IPsec revenu sur fw-client" "fw-client"
else
	fail "fw-client redemarre"
fi

echo ""
echo "--- Failover FortiGate-like server ---"
info "Arret du noeud primaire fw-server"
docker stop fw-server >/dev/null
wait_for_vip_owner "fw-server-2 reprend la VIP LAN" "fw-server-2" "192.168.20.1"
wait_for_vip_owner "fw-server-2 reprend la VIP WAN" "fw-server-2" "10.20.0.2"
wait_for_vpn "Tunnel IPsec re-etabli apres bascule serveur" "fw-client"
docker exec client1 bash -lc "ip neigh flush all" >/dev/null 2>&1 || true
wait_for_container_shell "HTTP via VPN maintenu sur fw-server-2" "client1" "curl -fsS http://192.168.20.10 | grep -q 'LabCyber Web Server'" 10 2
check_container_shell "DMZ maintenue sur fw-server-2" "client1" "curl -fsS http://192.168.50.10 | grep -q 'LabCyber Web Server'"
info "Redemarrage du noeud primaire fw-server"
docker start fw-server >/dev/null
if wait_for_running_container fw-server; then
	wait_for_vip_owner "fw-server recupere la VIP LAN" "fw-server" "192.168.20.1"
	wait_for_vip_owner "fw-server recupere la VIP WAN" "fw-server" "10.20.0.2"
	wait_for_vpn "Tunnel IPsec revenu apres restauration serveur" "fw-client"
else
	fail "fw-server redemarre"
fi

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) HA ont echoue."
	exit 1
fi

echo "Haute disponibilite validee."
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
GRAFANA_USER=${GRAFANA_USER:-admin}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-labcyber-admin}
LOKI_BASE_URL=${LOKI_BASE_URL:-http://127.0.0.1:3110}
GRAFANA_BASE_URL=${GRAFANA_BASE_URL:-http://127.0.0.1:3002}

ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
fail() {
	echo -e "${RED}[FAIL]${NC} $1"
	FAILURES=$((FAILURES + 1))
}
info() { echo -e "${YEL}[..]${NC}   $1"; }

check_running_service() {
	local service_name=$1

	if docker compose ps --services --status running | grep -qx "$service_name"; then
		ok "Service compose actif: $service_name"
	else
		fail "Service compose inactif: $service_name"
	fi
}

check_host_shell() {
	local description=$1
	local shell_command=$2

	if bash -lc "$shell_command" >/dev/null 2>&1; then
		ok "$description"
	else
		fail "$description"
	fi
}

wait_for_host_shell() {
	local description=$1
	local shell_command=$2
	local max_attempts=${3:-15}
	local delay_seconds=${4:-2}
	local attempt=1

	info "$description"
	while [ "$attempt" -le "$max_attempts" ]; do
		if bash -lc "$shell_command" >/dev/null 2>&1; then
			ok "$description"
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	fail "$description"
	return 1
}

loki_query_range() {
	local query=$1

	curl -fsSG "$LOKI_BASE_URL/loki/api/v1/query_range" \
		--data-urlencode "query=${query}" \
		--data-urlencode "limit=100" \
		--data-urlencode "direction=BACKWARD" \
		--data-urlencode "since=10m"
}

wait_for_loki_match() {
	local description=$1
	local query=$2
	local regex=$3
	local max_attempts=${4:-15}
	local delay_seconds=${5:-2}
	local attempt=1

	info "$description"
	while [ "$attempt" -le "$max_attempts" ]; do
		if loki_query_range "$query" | grep -Eq "$regex"; then
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
REMOTE_MARKER="LAB_SIEM_REMOTE_${MARKER_SUFFIX}"
SURICATA_MARKER="LAB Suricata synthetic SIEM marker ${MARKER_SUFFIX}"

SURICATA_LINE="$(date -u '+%Y-%m-%dT%H:%M:%SZ') [**] [1:9900001:1] ${SURICATA_MARKER} [**] [Classification: Misc activity] [Priority: 2] {TCP} 192.168.10.10:42424 -> 192.168.50.10:80"


echo "=========================================="
echo " SOC / SIEM Phase 4                       "
echo "=========================================="

echo ""
echo "--- Plateforme SIEM ---"
check_running_service "loki"
check_running_service "promtail"
check_running_service "grafana"
wait_for_host_shell "Loki API prete" "curl --retry 5 --retry-delay 1 --retry-connrefused -fsS '$LOKI_BASE_URL/ready' | grep -q '^ready$'" 10 2
wait_for_host_shell "Grafana API prete" "curl --retry 5 --retry-delay 1 --retry-connrefused -fsS -u '$GRAFANA_USER:$GRAFANA_PASSWORD' '$GRAFANA_BASE_URL/api/health' | grep -Eq '\"database\"[[:space:]]*:[[:space:]]*\"ok\"'" 10 2
check_host_shell "Datasource Grafana Loki provisionnee" "curl -fsS -u '$GRAFANA_USER:$GRAFANA_PASSWORD' '$GRAFANA_BASE_URL/api/datasources/uid/labcyber-loki' | grep -q '\"name\":\"LabCyber Loki\"'"

echo ""
echo "--- Dashboards et regles ---"
check_host_shell "Dashboard LabCyber SOC Overview provisionne" "curl -fsS -u '$GRAFANA_USER:$GRAFANA_PASSWORD' '$GRAFANA_BASE_URL/api/search?query=LabCyber' | grep -q 'labcyber-soc-overview'"
check_host_shell "Dashboard LabCyber HA & VPN provisionne" "curl -fsS -u '$GRAFANA_USER:$GRAFANA_PASSWORD' '$GRAFANA_BASE_URL/api/search?query=LabCyber' | grep -q 'labcyber-ha-vpn'"
check_host_shell "Regle SSHAuthenticationFailuresBurst chargee" "curl -fsS '$LOKI_BASE_URL/prometheus/api/v1/rules' | grep -q 'SSHAuthenticationFailuresBurst'"
check_host_shell "Regle KeepalivedMasterTransitionObserved chargee" "curl -fsS '$LOKI_BASE_URL/prometheus/api/v1/rules' | grep -q 'KeepalivedMasterTransitionObserved'"
check_host_shell "Regle SuricataLabAlertObserved chargee" "curl -fsS '$LOKI_BASE_URL/prometheus/api/v1/rules' | grep -q 'SuricataLabAlertObserved'"

echo ""
echo "--- Ingestion des logs ---"
info "Emission d'un marqueur syslog depuis fw-isp"
docker exec fw-isp bash -lc "logger -t siem-test '${REMOTE_MARKER}'"
wait_for_loki_match "Loki ingere le marqueur centralise fw-isp" "{job=\"lab-remote-logs\"} |= \"${REMOTE_MARKER}\"" "${REMOTE_MARKER}" 20 2

info "Injection d'un marqueur IDS dans fast.log"
docker exec fw-client bash -lc "printf '%s\\n' '${SURICATA_LINE}' >> /var/log/fw/suricata/fast.log"
wait_for_loki_match "Loki ingere le marqueur IDS Suricata" "{job=\"suricata-fast\", firewall=\"fw-client\"} |= \"${SURICATA_MARKER}\"" "${MARKER_SUFFIX}" 20 2

echo ""
echo "=========================================="

if [ "$FAILURES" -gt 0 ]; then
	echo "${FAILURES} test(s) SIEM ont echoue."
	exit 1
fi

echo "SOC / SIEM Phase 4 valide."
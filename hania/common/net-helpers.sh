#!/bin/bash

get_if_by_ip() {
	ip -o -4 addr show | awk -v target="$1" '$4 ~ ("^" target "/") { print $2; exit }'
}

has_ip_address() {
	local target_ip=$1
	ip -o -4 addr show | awk -v target="$target_ip" '$4 ~ ("^" target "/") { found=1 } END { exit(found ? 0 : 1) }'
}

require_if_by_ip() {
	local var_name=$1
	local target_ip=$2
	local if_name

	if_name=$(get_if_by_ip "$target_ip")
	if [ -z "$if_name" ]; then
		echo "[net] Interface introuvable pour ${target_ip}" >&2
		exit 1
	fi

	printf -v "$var_name" '%s' "$if_name"
}

wait_for_ip_assignment() {
	local target_ip=$1
	local max_attempts=${2:-20}
	local delay_seconds=${3:-1}
	local attempt=1

	while [ "$attempt" -le "$max_attempts" ]; do
		if has_ip_address "$target_ip"; then
			return 0
		fi

		sleep "$delay_seconds"
		attempt=$((attempt + 1))
	done

	return 1
}

render_template() {
	local template_path=$1
	local output_path=$2
	shift 2

	local sed_args=()
	while [ "$#" -gt 1 ]; do
		sed_args+=( -e "s|__${1}__|${2}|g" )
		shift 2
	done

	sed "${sed_args[@]}" "$template_path" > "$output_path"
}

log_if_assignment() {
	local label=$1
	local if_name=$2
	local target_ip=$3

	echo "[net] ${label}=${if_name} (${target_ip})"
}

replace_default_route() {
	local gateway_ip=$1
	ip route replace default via "$gateway_ip"
}

replace_static_route() {
	local destination_cidr=$1
	local gateway_ip=$2
	ip route replace "$destination_cidr" via "$gateway_ip"
}

configure_resolver() {
	local nameserver_ip=$1
	local search_domain=$2

	{
		echo "nameserver ${nameserver_ip}"
		if [ -n "$search_domain" ]; then
			echo "search ${search_domain}"
		fi
	} > /etc/resolv.conf
}

configure_remote_syslog() {
	local target_host=$1
	local target_port=${2:-514}
	local protocol=${3:-tcp}
	local config_path=/etc/rsyslog.d/90-remote-log-collector.conf

	if [ -z "$target_host" ]; then
		rm -f "$config_path"
		return 0
	fi

	cat > "$config_path" <<EOF
*.* action(
    type="omfwd"
    target="${target_host}"
    port="${target_port}"
    protocol="${protocol}"
    action.resumeRetryCount="-1"
    queue.type="linkedList"
    queue.filename="remote_log_collector"
)
EOF
}
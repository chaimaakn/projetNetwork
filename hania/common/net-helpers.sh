#!/bin/bash

get_if_by_ip() {
	ip -o -4 addr show | awk -v target="$1" '$4 ~ ("^" target "/") { print $2; exit }'
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
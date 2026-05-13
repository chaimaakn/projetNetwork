#!/bin/bash

set -e

GATEWAY_IP=${GATEWAY_IP:-192.168.20.1}
DNS_SERVER=${DNS_SERVER:-192.168.99.1}
SEARCH_DOMAIN=${SEARCH_DOMAIN:-labcyber.local}
SERVER_ROLE=${SERVER_ROLE:-web}
ENABLE_SSH=${ENABLE_SSH:-0}
ENABLE_FAIL2BAN=${ENABLE_FAIL2BAN:-0}
SSH_PERMIT_ROOT_LOGIN=${SSH_PERMIT_ROOT_LOGIN:-no}
SSH_PASSWORD_AUTH=${SSH_PASSWORD_AUTH:-no}
SSH_ALLOW_USERS=${SSH_ALLOW_USERS:-admin}
SSH_AUTHORIZED_KEY=${SSH_AUTHORIZED_KEY:-}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-}
REMOTE_SYSLOG_HOST=${REMOTE_SYSLOG_HOST:-}
REMOTE_SYSLOG_PORT=${REMOTE_SYSLOG_PORT:-514}
REMOTE_SYSLOG_PROTOCOL=${REMOTE_SYSLOG_PROTOCOL:-tcp}

ip route del default 2>/dev/null || true
ip route add default via "$GATEWAY_IP" || true

if [ -n "$DNS_SERVER" ]; then
	echo "nameserver ${DNS_SERVER}" > /etc/resolv.conf
	if [ -n "$SEARCH_DOMAIN" ]; then
		echo "search ${SEARCH_DOMAIN}" >> /etc/resolv.conf
	fi
fi

ensure_sshd_setting() {
	local key=$1
	local value=$2

	if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" /etc/ssh/sshd_config; then
		sed -ri "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" /etc/ssh/sshd_config
	else
		echo "${key} ${value}" >> /etc/ssh/sshd_config
	fi
}

configure_remote_syslog() {
	if [ -z "$REMOTE_SYSLOG_HOST" ]; then
		rm -f /etc/rsyslog.d/90-remote-log-collector.conf
		return 0
	fi

	cat > /etc/rsyslog.d/90-remote-log-collector.conf <<EOF
*.* action(
	type="omfwd"
	target="${REMOTE_SYSLOG_HOST}"
	port="${REMOTE_SYSLOG_PORT}"
	protocol="${REMOTE_SYSLOG_PROTOCOL}"
	action.resumeRetryCount="-1"
	queue.type="linkedList"
	queue.filename="remote_log_collector"
)
EOF
}

configure_ssh_access() {
	install -d -m 700 /home/admin/.ssh
	chown admin:admin /home/admin/.ssh

	if [ -n "$SSH_AUTHORIZED_KEY" ]; then
		printf '%s\n' "$SSH_AUTHORIZED_KEY" > /home/admin/.ssh/authorized_keys
		chmod 600 /home/admin/.ssh/authorized_keys
		chown admin:admin /home/admin/.ssh/authorized_keys
	fi

	if [ "$SSH_PASSWORD_AUTH" = "yes" ] && [ -n "$ADMIN_PASSWORD" ]; then
		echo "admin:${ADMIN_PASSWORD}" | chpasswd
	else
		passwd -l admin >/dev/null 2>&1 || true
	fi

	passwd -l root >/dev/null 2>&1 || true

	ensure_sshd_setting PermitRootLogin "$SSH_PERMIT_ROOT_LOGIN"
	ensure_sshd_setting PasswordAuthentication "$SSH_PASSWORD_AUTH"
	ensure_sshd_setting KbdInteractiveAuthentication no
	ensure_sshd_setting ChallengeResponseAuthentication no
	ensure_sshd_setting PubkeyAuthentication yes
	ensure_sshd_setting MaxAuthTries 3
	ensure_sshd_setting LoginGraceTime 30
	ensure_sshd_setting AllowUsers "$SSH_ALLOW_USERS"
}

start_ssh_services() {
	rm -f /run/fail2ban/fail2ban.sock /var/run/fail2ban/fail2ban.sock
	rm -f /run/rsyslogd.pid /var/run/rsyslogd.pid
	install -d -m 755 /run/sshd /run/fail2ban
	touch /var/log/auth.log
	configure_remote_syslog
	rsyslogd
	configure_ssh_access
	service ssh start

	if [ "$ENABLE_FAIL2BAN" = "1" ]; then
		cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
backend = auto
logpath = /var/log/auth.log
usedns = no
maxretry = 3
findtime = 10m
bantime = 1h
EOF
		service fail2ban restart
	fi
}

if [ "$ENABLE_SSH" = "1" ]; then
	start_ssh_services
else
	echo "[SERVER] SSH desactive pour le role ${SERVER_ROLE}"
fi

# Démarrer Nginx au premier plan
echo "[SERVER] Role ${SERVER_ROLE} actif sur $(hostname -I)"
if [ "$ENABLE_SSH" = "1" ]; then
	echo "[SERVER] SSH demarre avec root login=${SSH_PERMIT_ROOT_LOGIN}, password auth=${SSH_PASSWORD_AUTH}, fail2ban=${ENABLE_FAIL2BAN}"
fi

nginx -g "daemon off;"
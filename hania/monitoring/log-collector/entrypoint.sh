#!/bin/bash

set -euo pipefail

mkdir -p /var/log/remote /var/spool/rsyslog

exec rsyslogd -n -f /etc/rsyslog.conf
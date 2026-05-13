FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    rsyslog \
    procps \
    net-tools \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

COPY monitoring/log-collector/rsyslog.conf /etc/rsyslog.conf
COPY monitoring/log-collector/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
 && sed -i 's/\r$//' /entrypoint.sh /etc/rsyslog.conf \
 && mkdir -p /var/log/remote /var/spool/rsyslog

ENTRYPOINT ["/entrypoint.sh"]
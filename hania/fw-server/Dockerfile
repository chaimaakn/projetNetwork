FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    iproute2 \
    iputils-ping \
    strongswan \
    strongswan-pki \
    libcharon-extra-plugins \
    libcharon-extauth-plugins \
    chrony \
    rsyslog \
    tcpdump \
    curl \
    netcat-openbsd \
    nano \
    procps \
    net-tools \
    ipset \
    keepalived \
    conntrackd \
    conntrack \
    && rm -rf /var/lib/apt/lists/*

COPY fw-server/ipsec.conf      /opt/lab/ipsec.conf.tmpl
COPY fw-server/ipsec.secrets   /etc/ipsec.secrets
COPY fw-server/chrony.conf     /etc/chrony/chrony.conf
COPY fw-server/keepalived.conf.tmpl /opt/lab/keepalived.conf.tmpl
COPY fw-server/conntrackd.conf.tmpl /opt/lab/conntrackd.conf.tmpl
COPY fw-server/ha-state.sh     /usr/local/bin/ha-state.sh
COPY common/net-helpers.sh     /usr/local/lib/lab-net.sh
COPY fw-server/rules.sh        /usr/local/bin/rules.sh
COPY fw-server/entrypoint.sh   /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/rules.sh /usr/local/bin/ha-state.sh \
 && sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/rules.sh /usr/local/bin/ha-state.sh /usr/local/lib/lab-net.sh /opt/lab/ipsec.conf.tmpl /etc/ipsec.secrets /etc/chrony/chrony.conf /opt/lab/keepalived.conf.tmpl /opt/lab/conntrackd.conf.tmpl \
 && mkdir -p /var/log/fw /opt/lab \
 && printf 'ha {\n    load = no\n}\n' > /etc/strongswan.d/charon/ha.conf \
 && chmod 600 /etc/ipsec.secrets

ENTRYPOINT ["/entrypoint.sh"]
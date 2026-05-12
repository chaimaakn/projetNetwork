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
    && rm -rf /var/lib/apt/lists/*

COPY fw-server/ipsec.conf      /etc/ipsec.conf
COPY fw-server/ipsec.secrets   /etc/ipsec.secrets
COPY fw-server/chrony.conf     /etc/chrony/chrony.conf
COPY common/net-helpers.sh     /usr/local/lib/lab-net.sh
COPY fw-server/rules.sh        /usr/local/bin/rules.sh
COPY fw-server/entrypoint.sh   /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/rules.sh \
 && sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/rules.sh /usr/local/lib/lab-net.sh /etc/ipsec.conf /etc/ipsec.secrets /etc/chrony/chrony.conf \
 && mkdir -p /var/log/fw \
 && printf 'ha {\n    load = no\n}\n' > /etc/strongswan.d/charon/ha.conf \
 && chmod 600 /etc/ipsec.secrets

ENTRYPOINT ["/entrypoint.sh"]
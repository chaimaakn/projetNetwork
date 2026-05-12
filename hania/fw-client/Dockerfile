FROM debian:12-slim

# --- Installation des paquets équivalents aux fonctions FortiGate ---
# strongswan  : VPN IPsec IKEv2 (équivalent VPN > IPsec FortiGate)
# iptables    : firewall stateful (équivalent moteur de policies FortiGate)
# dnsmasq     : DHCP serveur (équivalent DHCP FortiGate)
# squid       : proxy + filtrage web (équivalent Web Filter FortiGate)
# suricata    : IDS/IPS (équivalent IPS FortiGate) - optionnel
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    iproute2 \
    iputils-ping \
    strongswan \
    strongswan-pki \
    libcharon-extra-plugins \
    libcharon-extauth-plugins \
    dnsmasq \
    squid \
    rsyslog \
    tcpdump \
    curl \
    netcat-openbsd \
    nano \
    procps \
    net-tools \
    ipset \
    && rm -rf /var/lib/apt/lists/*

COPY fw-client/ipsec.conf      /etc/ipsec.conf
COPY fw-client/ipsec.secrets   /etc/ipsec.secrets
COPY fw-client/dnsmasq.conf    /etc/dnsmasq.conf
COPY fw-client/squid.conf      /etc/squid/squid.conf
COPY fw-client/blocked_domains.txt /etc/squid/blocked_domains.txt
COPY common/net-helpers.sh     /usr/local/lib/lab-net.sh
COPY fw-client/rules.sh        /usr/local/bin/rules.sh
COPY fw-client/entrypoint.sh   /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/rules.sh \
 && sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/rules.sh /usr/local/lib/lab-net.sh /etc/ipsec.conf /etc/ipsec.secrets /etc/dnsmasq.conf /etc/squid/squid.conf /etc/squid/blocked_domains.txt \
 && mkdir -p /var/log/fw \
 && printf 'ha {\n    load = no\n}\n' > /etc/strongswan.d/charon/ha.conf \
 && chmod 600 /etc/ipsec.secrets

ENTRYPOINT ["/entrypoint.sh"]
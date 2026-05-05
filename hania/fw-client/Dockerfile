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

COPY ipsec.conf      /etc/ipsec.conf
COPY ipsec.secrets   /etc/ipsec.secrets
COPY dnsmasq.conf    /etc/dnsmasq.conf
COPY squid.conf      /etc/squid/squid.conf
COPY rules.sh        /usr/local/bin/rules.sh
COPY entrypoint.sh   /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/rules.sh \
 && mkdir -p /var/log/fw \
 && chmod 600 /etc/ipsec.secrets

ENTRYPOINT ["/entrypoint.sh"]
FROM debian:12-slim

# --- Installation des paquets équivalents aux fonctions pfSense ---
# iptables    : firewall stateful (équivalent du moteur de filtrage pfSense)
# dnsmasq     : DNS Resolver + DHCP serveur
# chrony      : serveur NTP
# haproxy     : load balancer (équivalent HAProxy package pfSense)
# iproute2    : ip route, ip rule (multi-WAN)
# tcpdump     : capture pour debug
# rsyslog     : logging centralisé
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    iproute2 \
    iputils-ping \
    dnsmasq \
    chrony \
    haproxy \
    keepalived \
    tcpdump \
    rsyslog \
    curl \
    netcat-openbsd \
    nano \
    procps \
    net-tools \
    ipset \
    && rm -rf /var/lib/apt/lists/*

# Copie des configurations
COPY fw-isp/dnsmasq.conf      /opt/lab/dnsmasq.conf.tmpl
COPY fw-isp/chrony.conf       /etc/chrony/chrony.conf
COPY fw-isp/haproxy.cfg       /opt/lab/haproxy.cfg.tmpl
COPY fw-isp/keepalived.conf.tmpl /opt/lab/keepalived.conf.tmpl
COPY common/net-helpers.sh    /usr/local/lib/lab-net.sh
COPY fw-isp/rules.sh          /usr/local/bin/rules.sh
COPY fw-isp/entrypoint.sh     /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/rules.sh \
 && sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/rules.sh /usr/local/lib/lab-net.sh /opt/lab/dnsmasq.conf.tmpl /etc/chrony/chrony.conf /opt/lab/haproxy.cfg.tmpl /opt/lab/keepalived.conf.tmpl \
 && mkdir -p /var/log/fw /opt/lab

EXPOSE 53/udp 53/tcp 67/udp 123/udp 80/tcp

ENTRYPOINT ["/entrypoint.sh"]
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    iproute2 \
    curl \
    wget \
    dnsutils \
    traceroute \
    netcat-openbsd \
    nmap \
    tcpdump \
    nano \
    procps \
    net-tools \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Le client utilisera la passerelle 192.168.10.1 par défaut (FW_CLIENT)
# Docker assigne l'IP via le compose; on ajuste juste la route au boot
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
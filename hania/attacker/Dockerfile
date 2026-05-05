# =============================================================================
# Kali Linux pour la Phase 3 - Pentest
# Image officielle kali-rolling avec outils de base + ajouts
# =============================================================================
FROM kalilinux/kali-rolling

# Préfix non-interactif pour apt
ENV DEBIAN_FRONTEND=noninteractive

# Installation du toolset pentest essentiel pour ce projet
RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    metasploit-framework \
    hydra \
    medusa \
    nikto \
    netcat-openbsd \
    dnsutils \
    dnsenum \
    dnsrecon \
    hping3 \
    arp-scan \
    netdiscover \
    ike-scan \
    tcpdump \
    wireshark-common \
    tshark \
    iputils-ping \
    iproute2 \
    curl \
    wget \
    nano \
    vim \
    procps \
    net-tools \
    iputils-arping \
    macchanger \
    ettercap-text-only \
    hashcat \
    john \
    crunch \
    seclists \
    wordlists \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Décompresser rockyou (sera utilisé en Phase 3)
RUN if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then \
      gunzip /usr/share/wordlists/rockyou.txt.gz; \
    fi

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /root
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
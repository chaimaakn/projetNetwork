FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    iproute2 \
    curl \
    wget \
    dnsutils \
    netcat-openbsd \
    nmap \
    nano \
    procps \
    net-tools \
    nginx \
    openssh-server \
    fail2ban \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash admin && \
    mkdir -p /run/sshd /var/log/fail2ban

# Page web simple
RUN echo "<html><body><h1>LabCyber Web Server</h1><p>Serveur interne - Confidentiel</p><!-- TODO: remove debug info: app=v1.2.3, db=mysql-5.7 --></body></html>" \
    > /var/www/html/index.html

EXPOSE 22 80

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && sed -i 's/\r$//' /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
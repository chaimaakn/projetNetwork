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
    && rm -rf /var/lib/apt/lists/*

# --- Configuration SSH avec mot de passe FAIBLE (volontaire pour la Phase 3) ---
# ATTENTION : ces credentials sont volontairement faibles pour le pentest
# Ils doivent être renforcés en Phase 3 (Jour 42)
RUN useradd -m -s /bin/bash admin && \
    echo "admin:admin123" | chpasswd && \
    useradd -m -s /bin/bash test && \
    echo "test:test" | chpasswd && \
    echo "root:toor" | chpasswd

# Permettre login root + password (à durcir en Phase 3)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd

# Page web simple
RUN echo "<html><body><h1>LabCyber Web Server</h1><p>Serveur interne - Confidentiel</p><!-- TODO: remove debug info: app=v1.2.3, db=mysql-5.7 --></body></html>" \
    > /var/www/html/index.html

EXPOSE 22 80

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
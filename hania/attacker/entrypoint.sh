#!/bin/bash
ip route del default 2>/dev/null || true
ip route add default via 192.168.10.1 || true

echo "nameserver 192.168.99.1" > /etc/resolv.conf
echo "search labcyber.local" >> /etc/resolv.conf

cat <<'EOF'
============================================================
  KALI LINUX - Lab Cyber 4ème SSI - Phase 3 Pentest
============================================================
  Position : LAN_CLIENT - Attaquant interne simulé
  IP       : 192.168.10.50
  Cibles autorisées (LAB UNIQUEMENT) :
    - FW_CLIENT     : 192.168.10.1
    - FW_SERVER     : 192.168.20.1 (via VPN)
    - WebServer     : 192.168.20.10
    - SSHServer     : 192.168.20.11
    - FW_ISP        : 10.10.0.1 / 192.168.99.1

  Outils disponibles : nmap, metasploit, hydra, medusa,
                       nikto, hping3, arp-scan, ike-scan,
                       ettercap, hashcat, john, dnsenum
============================================================
EOF

exec "$@"
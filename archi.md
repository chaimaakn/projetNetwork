# Explication complète de l'architecture

## Vue d'ensemble

C'est une architecture d'entreprise simulée avec 3 niveaux de sécurité (périmètre, interne, DMZ) et haute disponibilité sur tous les firewalls.

---

## 1. INTERNET — 200.0.0.0/24

Le réseau qui simule Internet. Il contient :

- **internet-probe (200.0.0.50)** — une machine qui simule un attaquant externe ou un client Internet. Elle utilise 200.0.0.10 (VIP FW-ISP) comme gateway. Elle sert à tester que les règles de filtrage fonctionnent depuis l'extérieur (ex : accéder à la DMZ mais pas au LAN_SERVER).

---

## 2. ISP EDGE FW HA (VRRP) — Le firewall central

C'est l'équivalent de pfSense dans l'architecture originale. C'est le point d'entrée/sortie de tout le trafic.

- **fw-isp** : 200.0.0.11 / 10.10.0.11 / 10.20.0.11 / 192.168.99.11 (nœud primaire)
- **fw-isp-2** : 200.0.0.12 / 10.10.0.12 / 10.20.0.12 / 192.168.99.12 (nœud backup)
- **VIPs partagées** : 200.0.0.10 (Internet) / 10.10.0.1 (WAN CLIENT) / 10.20.0.1 (WAN SERVER) / 192.168.99.1 (MGMT)

Les deux nœuds partagent ces VIPs via VRRP. Si fw-isp tombe, fw-isp-2 reprend toutes les VIPs automatiquement.

**Ce qu'il fait :**
- **HAProxy** — distribue le trafic entrant vers les serveurs internes (load balancing), expose la DMZ sur les ports 80/443
- **DNS** — résout les noms internes (web.labcyber.local → 192.168.20.10)
- **NTP** — serveur de temps pour toute l'infrastructure
- **NAT** — traduit les adresses privées vers Internet
- **Routage** — fait passer le trafic entre WAN CLIENT (10.10.0.0/24) et WAN SERVER (10.20.0.0/24)

---

## 3. Le tunnel IPsec IKEv2

La flèche en pointillés entre FW-CLIENT et FW-SERVER représente le tunnel VPN chiffré. Ce tunnel transite physiquement par les liens WAN via FW-ISP — il ne s'établit pas directement entre les deux firewalls.

- **IKEv2** — protocole de négociation moderne
- **AES-256** — chiffrement des données
- **SHA-256** — intégrité des données
- **MODP-2048** — échange de clés Diffie-Hellman
- **Via WAN / UDP 500** — le tunnel est encapsulé dans UDP/500 et transite par 10.10.0.1 → 10.20.0.1 (via FW-ISP)

Tout le trafic entre LAN_CLIENT et LAN_SERVER est chiffré dans ce tunnel — personne sur le WAN ne peut lire les données.

---

## 4. FW-CLIENT HA (VRRP) — Firewall côté utilisateurs

C'est l'équivalent du FortiGate FW_CLIENT.

- **fw-client** : 10.10.0.21 / 192.168.10.21 / 192.168.30.21 / 192.168.40.21 / 192.168.99.21 (nœud primaire)
- **fw-client-2** : 10.10.0.22 / 192.168.10.22 / 192.168.30.22 / 192.168.40.22 / 192.168.99.22 (nœud backup)
- **VIPs partagées** : 10.10.0.2 (WAN) / 192.168.10.1 (LAN USERS) / 192.168.30.1 (VOIP) / 192.168.40.1 (GUEST) / 192.168.99.10 (MGMT)

**Ce qu'il fait :**
- **Squid** — proxy web qui filtre les URLs, bloque les malwares, logge les accès web
- **Suricata** — IDS qui détecte les intrusions en temps réel (BitTorrent, scan SSH, brute-force...)
- **IPsec** — gère le tunnel VPN vers FW-SERVER (endpoint local : VIP 10.10.0.2)
- **conntrackd** — synchronise les sessions TCP actives entre fw-client et fw-client-2 pour assurer la continuité des connexions lors d'un basculement HA
- **Syslog TCP/514** — fw-client forward ses logs vers le Log Collector (192.168.99.60)

---

## 5. CLIENT LAN — 192.168.10.0/24

Le réseau des utilisateurs internes.

- **Client-01 (192.168.10.10)** — poste utilisateur normal
- **Client-02 (192.168.10.11)** — poste utilisateur normal
- **Kali Linux (192.168.10.50)** — machine de pentest, simule un attaquant interne

### VOIP — 192.168.30.0/24

Réseau téléphonie IP, **segment distinct** rattaché à FW-CLIENT (VIP gateway : 192.168.30.1).

- **voip1 (192.168.30.10)** — représente un téléphone IP

Isolé pour la QoS et la sécurité : les hôtes du VLAN USERS ne peuvent pas atteindre ce segment (filtrage FORWARD sur fw-client).

### GUEST — 192.168.40.0/24

Réseau invités, **segment distinct** rattaché à FW-CLIENT (VIP gateway : 192.168.40.1).

- **guest1 (192.168.40.10)** — représente un poste invité

Totalement isolé : guest1 peut uniquement accéder à Internet sur les ports 80/443 — pas au LAN_SERVER, pas à la DMZ, pas au réseau MANAGEMENT.

---

## 6. FW-SERVER HA (VRRP) — Firewall côté serveurs

C'est l'équivalent du FortiGate FW_SERVER.

- **fw-server** : 10.20.0.21 / 192.168.20.21 / 192.168.50.21 / 192.168.99.31 (nœud primaire)
- **fw-server-2** : 10.20.0.22 / 192.168.20.22 / 192.168.50.22 / 192.168.99.32 (nœud backup)
- **VIPs partagées** : 10.20.0.2 (WAN) / 192.168.20.1 (LAN SERVER) / 192.168.50.1 (DMZ) / 192.168.99.20 (MGMT)

**Ce qu'il fait :**
- **IPsec Gateway** — termine le tunnel VPN côté serveur (endpoint local : VIP 10.20.0.2)
- **NTP** — synchronisé sur FW-ISP, distribue l'heure aux serveurs internes
- **conntrackd** — synchronisation des sessions TCP pour la HA entre fw-server et fw-server-2
- **NAT / Forwarding vers DMZ** — le trafic entrant en provenance de HAProxy (FW-ISP, port 80/443) est transféré vers dmz-web (192.168.50.10). FW-SERVER assure le filtrage ACL entre LAN_SERVER et DMZ
- **Syslog TCP/514** — fw-server forward ses logs vers le Log Collector (192.168.99.60)

---

## 7. SERVER LAN — 192.168.20.0/24

Le réseau des serveurs internes, accessible uniquement via le tunnel IPsec depuis LAN_CLIENT.

- **Web Server Nginx (192.168.20.10)** — serveur HTTP interne, accessible depuis LAN_CLIENT via VPN
- **SSH Server OpenSSH (192.168.20.11)** — serveur SSH interne, accessible depuis LAN_CLIENT via VPN
- **Log Collector Rsyslog** — dual-homed (deux interfaces réseau) :
  - **192.168.99.60** (interface MGMT) — reçoit les logs des firewalls (fw-isp, fw-client, fw-server) via le réseau Management
  - **192.168.20.60** (interface SERVER LAN) — reçoit les logs de webserver et sshserver via le LAN SERVER

---

## 8. DMZ — 192.168.50.0/24

Zone démilitarisée — accessible depuis Internet mais isolée du LAN_SERVER.

- **dmz-web Nginx (192.168.50.10)** — serveur web exposé publiquement via HAProxy sur FW-ISP (ports 80/443)
- Isolé du LAN_SERVER par les ACLs de FW-SERVER : un attaquant qui compromet dmz-web ne peut pas atteindre les serveurs internes (192.168.20.0/24)
- Monitoré depuis le réseau MANAGEMENT via Uptime Kuma (sondes HTTP)

---

## 9. MANAGEMENT — 192.168.99.0/24

Réseau d'administration hors-bande (OOB), inaccessible depuis les VLANs utilisateurs (USERS, VOIP, GUEST) et depuis Internet.

- **Grafana (192.168.99.72)** — tableaux de bord, visualise les logs et métriques en interrogeant Loki
- **Loki (192.168.99.70)** — stocke et indexe tous les logs reçus de Promtail
- **Promtail (192.168.99.71)** — agent qui collecte les logs depuis le Log Collector et les pousse vers Loki
- **Uptime Kuma (192.168.99.50)** — surveille la disponibilité des services via des sondes HTTP/Ping/TCP vers les firewalls et serveurs

**Flux de logs complet :**

```
fw-client / fw-server / fw-isp
        ↓  Syslog TCP/514
   Log Collector (192.168.99.60 + 192.168.20.60)
        ↓  Scraping fichiers logs
      Promtail (192.168.99.71)
        ↓  Push logs
       Loki (192.168.99.70)
        ↓  Query
     Grafana (192.168.99.72)  ← dashboards SOC
```

---

## Résumé du flux de trafic normal

```
Utilisateur (client1 — 192.168.10.10)
    ↓
FW-CLIENT VIP 192.168.10.1
(filtrage ACL, proxy Squid, IDS Suricata)
    ↓
Tunnel IPsec IKEv2 AES-256 (via WAN 10.10.0.2 → 10.20.0.2)
    ↓
FW-SERVER VIP 192.168.20.1
(déchiffrement IPsec, filtrage ACL)
    ↓
Web Server (192.168.20.10) ou SSH Server (192.168.20.11)

─────────────────────────────────────────

Internet (200.0.0.50 ou navigateur externe)
    ↓
FW-ISP VIP 200.0.0.10
(HAProxy port 80/443, NAT, DNS)
    ↓
FW-SERVER (NAT/forwarding ACL)
    ↓
dmz-web (192.168.50.10)  ✓ accessible
    ✗ LAN_SERVER (192.168.20.0/24) bloqué depuis Internet
```

# 📘 PHASE 2 — Renforcement & Segmentation Avancée (Jours 16-30)

> **Objectif** : Faire évoluer l'architecture vers un environnement entreprise mature avec VLANs, ACLs granulaires, filtrage web, contrôle applicatif et haute disponibilité.

> 💡 **Note Docker** : les VLANs natifs (802.1Q) sont possibles avec Docker mais lourds. Nous reproduisons leur **comportement fonctionnel** avec des **réseaux Docker bridge séparés**, ce qui est pédagogiquement équivalent.

## 🗓️ Semaine 4 — Segmentation VLAN (J16-J20)

### Jour 16 — Conception du plan VLAN

#### Plan de segmentation cible

| ID | Nom VLAN | Rôle | Subnet | Réseau Docker |
|---|---|---|---|---|
| 10 | VLAN_USERS | Postes utilisateurs | 192.168.10.0/24 | `lan_client_net` (existant) |
| 20 | VLAN_VOIP | Téléphonie | 192.168.30.0/24 | `vlan_voip_net` (à créer) |
| 30 | VLAN_GUEST | Invités/WiFi guest | 192.168.40.0/24 | `vlan_guest_net` (à créer) |
| 100 | VLAN_SERVERS | Serveurs internes | 192.168.20.0/24 | `lan_server_net` (existant) |
| 110 | VLAN_DMZ | Serveurs exposés | 192.168.50.0/24 | `dmz_net` (à créer) |
| 999 | VLAN_MGMT | Management OOB | 192.168.99.0/24 | `mgmt_net` (existant) |

#### Matrice de flux (à valider par l'enseignant)

| Source ↓ / Dest → | USERS | VOIP | GUEST | SERVERS | DMZ | MGMT | Internet |
|---|---|---|---|---|---|---|---|
| **USERS** | ALLOW | DENY | DENY | HTTP/HTTPS/SSH | HTTP/HTTPS | DENY | ALLOW |
| **VOIP** | DENY | ALLOW | DENY | DENY | DENY | DENY | DNS uniquement |
| **GUEST** | DENY | DENY | ALLOW | DENY | DENY | DENY | HTTP/HTTPS |
| **SERVERS** | DENY | DENY | DENY | ALLOW | DENY | DENY | Updates uniquement |
| **DMZ** | DENY | DENY | DENY | DENY | ALLOW | DENY | ALLOW (web) |
| **MGMT** | SSH | SSH | DENY | SSH/HTTPS | SSH | ALLOW | DENY |
| **Internet** | DENY | DENY | DENY | DENY | HTTP/HTTPS | DENY | — |

---

### Jour 17 — Déploiement VLANs côté CLIENT

**Étape 1** — Mettre à jour `docker-compose.yml` pour ajouter les nouveaux réseaux :

```yaml
# Ajouter dans la section networks: à la fin du docker-compose.yml
  vlan_voip_net:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 192.168.30.0/24

  vlan_guest_net:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 192.168.40.0/24

  dmz_net:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 192.168.50.0/24
```

**Étape 2** — Connecter FW_CLIENT aux nouveaux VLANs :

```yaml
# Dans la section fw-client > networks: ajouter
      vlan_voip_net:
        ipv4_address: 192.168.30.1
      vlan_guest_net:
        ipv4_address: 192.168.40.1
```

**Étape 3** — Mettre à jour `fw-client/rules.sh` avec les ACLs inter-VLAN :

```bash
# Ajouter à la fin de fw-client/rules.sh

# === SEGMENTATION VLAN - PHASE 2 ===

# VLAN_USERS (eth1) -> VLAN_SERVERS (via VPN) : HTTP, HTTPS, SSH uniquement
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -p tcp -m multiport --dports 22,80,443 -j ACCEPT
# Bloquer TOUT autre trafic 10 -> 20
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -j DROP

# VLAN_USERS -> VLAN_VOIP : interdit
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.30.0/24 -j DROP
# VLAN_USERS -> VLAN_GUEST : interdit
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.40.0/24 -j DROP

# VLAN_VOIP : seulement DNS et trafic VOIP (SIP UDP 5060, RTP)
iptables -A FORWARD -s 192.168.30.0/24 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s 192.168.30.0/24 -p udp --dport 5060 -j ACCEPT
iptables -A FORWARD -s 192.168.30.0/24 -j DROP

# VLAN_GUEST : Internet seulement, jamais l'interne
iptables -A FORWARD -s 192.168.40.0/24 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -s 192.168.40.0/24 -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -s 192.168.40.0/24 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s 192.168.40.0/24 -j DROP

# === ANTI-SPOOFING ===
iptables -A FORWARD -i eth1 ! -s 192.168.10.0/24 -j DROP   # eth1 = VLAN_USERS uniquement
```

**Étape 4** — Reconstruire et redémarrer :
```bash
docker compose down
docker compose up -d --build
```

**Étape 5** — Test d'isolation :

```bash
# Créer temporairement un conteneur dans VLAN_GUEST
docker run --rm -it --network docker-cyber-lab_vlan_guest_net --ip 192.168.40.50 \
  --cap-add NET_ADMIN debian:12-slim bash

# Dans ce conteneur :
ip route add default via 192.168.40.1
ping 192.168.20.10   # Doit ÉCHOUER (isolation)
ping 8.8.8.8         # Doit RÉUSSIR
```

**Livrable J17** : capture montrant l'isolation effective + matrice de flux validée.

---

### Jour 18 — VLANs côté SERVER + adaptation IPsec

**Étape 1** — Ajouter le VLAN DMZ et adapter le tunnel pour inclure les nouveaux subnets.

Modifier `fw-client/ipsec.conf` pour inclure plusieurs subnets côté CLIENT :
```
leftsubnet=192.168.10.0/24,192.168.30.0/24
```

Modifier `fw-server/ipsec.conf` pour ajouter le DMZ :
```
leftsubnet=192.168.20.0/24,192.168.50.0/24
```

Recharger IPsec :
```bash
docker exec fw-client ipsec restart
docker exec fw-server ipsec restart
sleep 5
docker exec fw-client ipsec statusall
```

---

### Jour 19 — VLAN management & sécurisation

**Restriction d'accès à l'administration** :

Ajouter dans tous les `rules.sh` :
```bash
# Bloquer SSH/HTTPS sur les firewalls depuis tout sauf MGMT
iptables -A INPUT ! -i eth_mgmt -p tcp --dport 22  -j DROP
iptables -A INPUT ! -i eth_mgmt -p tcp --dport 443 -j DROP
```

Déjà partiellement appliqué dans le code initial (les règles INPUT n'autorisent management que depuis mgmt_net).

**Test** :
```bash
# Depuis client1 (LAN_USERS) tenter d'atteindre l'admin de FW_CLIENT
docker exec client1 curl -k --connect-timeout 5 https://192.168.10.1
# Doit échouer (timeout ou connection refused)

# Depuis un conteneur sur mgmt_net, ça doit marcher
```

---

### Jour 20 — Tests systématiques

Créer un script de validation matrice de flux : `scripts/test-vlan-matrix.sh`

```bash
#!/bin/bash
# Test matrice de flux Phase 2

test_flow() {
    local desc=$1; local src=$2; local dst=$3; local port=$4; local expect=$5
    result=$(docker exec "$src" timeout 3 nc -zv "$dst" "$port" 2>&1)
    if [ "$expect" = "ALLOW" ]; then
        if echo "$result" | grep -q "succeeded\|open"; then
            echo "[OK]   $desc"
        else
            echo "[FAIL] $desc - attendu ALLOW, obtenu DENY"
        fi
    else
        if echo "$result" | grep -q "succeeded\|open"; then
            echo "[FAIL] $desc - attendu DENY, obtenu ALLOW (FUITE !)"
        else
            echo "[OK]   $desc"
        fi
    fi
}

# Tests à exécuter
test_flow "USERS->SERVERS HTTP"  client1 192.168.20.10 80   ALLOW
test_flow "USERS->SERVERS SMB"   client1 192.168.20.10 445  DENY
test_flow "USERS->MGMT FW"       client1 192.168.99.10 22   DENY
```

---

## 🗓️ Semaine 5 — ACLs, Filtrage Web, Application Control (J21-J25)

### Jour 21 — ACLs granulaires sur FW_ISP

Améliorer `fw-isp/rules.sh` avec des règles plus fines :

```bash
# === ACLs FW_ISP - Phase 2 ===

# Bloquer les services SMB/RPC sortants (vol de données)
iptables -A FORWARD -p tcp --dport 445 -j DROP
iptables -A FORWARD -p tcp --dport 139 -j DROP
iptables -A FORWARD -p udp --dport 137:138 -j DROP

# Bloquer Telnet sortant (en clair)
iptables -A FORWARD -p tcp --dport 23 -j DROP

# Bloquer FTP en clair sortant
iptables -A FORWARD -p tcp --dport 21 -j DROP

# Limiter les flux par client (anti-DDoS interne)
iptables -A FORWARD -p tcp --syn -m connlimit --connlimit-above 50 -j DROP

# Ratelimit ICMP (anti-flood)
iptables -A FORWARD -p icmp -m limit --limit 5/sec -j ACCEPT
iptables -A FORWARD -p icmp -j DROP

# Logger les blocages avec préfixe
iptables -A FORWARD -j LOG --log-prefix "[FW_ISP-BLOCK] " -m limit --limit 5/min
```

---

### Jour 22 — ACLs avancées sur FortiGate-like

Sur `fw-client/rules.sh`, ajouter le concept **address objects** et **groupes** :

```bash
# === Address objects (équivalent FortiGate) via ipset ===
ipset create users_net hash:net 2>/dev/null || ipset flush users_net
ipset add users_net 192.168.10.0/24

ipset create servers_net hash:net 2>/dev/null || ipset flush servers_net
ipset add servers_net 192.168.20.0/24

ipset create blocked_external hash:net 2>/dev/null || ipset flush blocked_external
ipset add blocked_external 0.0.0.0/8        # Bogons
ipset add blocked_external 169.254.0.0/16   # Link-local

# === Service groups ===
ipset create web_ports bitmap:port range 0-65535 2>/dev/null || ipset flush web_ports
ipset add web_ports 80
ipset add web_ports 443
ipset add web_ports 8080

# === Politiques basées sur groupes ===
iptables -A FORWARD -m set --match-set users_net src \
                    -m set --match-set servers_net dst \
                    -p tcp -m set --match-set web_ports dst -j ACCEPT
```

---

### Jour 23 — Filtrage web Squid

Activer le filtrage par catégories :

```bash
# Créer la liste de domaines bloqués
docker exec fw-client bash -c 'cat > /etc/squid/blocked_domains.txt <<EOF
.facebook.com
.tiktok.com
.youtube.com
.malware-test.com
.phishing-example.org
.pirate-bay.org
.thepiratebay.org
.torrent-tracker.io
EOF'

# Recharger Squid
docker exec fw-client squid -k reconfigure

# Test depuis client1
docker exec client1 curl -x http://192.168.10.1:3128 -I http://www.facebook.com
# Doit retourner : HTTP/1.1 403 Forbidden

docker exec client1 curl -x http://192.168.10.1:3128 -I http://www.example.com  
# Doit passer : HTTP/1.1 200 OK
```

**Forçage du proxy** (optionnel - mode transparent) : rediriger tout le trafic 80/443 vers Squid :
```bash
# Sur fw-client, ajouter :
iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 80 -j REDIRECT --to-port 3128
```

---

### Jour 24 — Application Control & DPI

Pour l'inspection L7, on peut ajouter **Suricata** au FW_CLIENT.

Mettre à jour `fw-client/Dockerfile` :
```dockerfile
RUN apt-get update && apt-get install -y suricata
```

Configuration minimale `/etc/suricata/suricata.yaml` :
```yaml
af-packet:
  - interface: eth1
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules
```

Règles d'application control (`/var/lib/suricata/rules/app-control.rules`) :
```
# Bloquer torrent
drop tcp any any -> any any (msg:"BitTorrent detected"; content:"BitTorrent"; sid:1000001;)

# Détecter SSH brute-force
alert tcp any any -> any 22 (msg:"Possible SSH brute force"; \
   threshold: type both, track by_src, count 5, seconds 60; sid:1000002;)
```

Démarrer Suricata :
```bash
docker exec fw-client suricata -c /etc/suricata/suricata.yaml -i eth1 -D
```

---

### Jour 25 — Tests de pénétration des politiques

```bash
docker exec -it kali bash

# Test contournement filtrage web
curl -x http://192.168.10.1:3128 -I http://facebook.com.evil.com
curl -x http://192.168.10.1:3128 --resolve www.facebook.com:80:1.2.3.4 http://www.facebook.com

# Test bypass via DNS (DNS over HTTPS)
curl https://1.1.1.1/dns-query?name=facebook.com -H 'accept: application/dns-json'

# Vérifier les logs Squid
docker exec fw-client tail -f /var/log/squid/access.log
```

---

## 🗓️ Semaine 6 — Haute Disponibilité (J26-J30)

### Jour 26 — Théorie HA

Concepts clés :
- **Active/Passive** : un nœud actif, l'autre en standby (basculement sur panne)
- **Active/Active** : les deux nœuds traitent du trafic, load balancing
- **VRRP/CARP** : protocoles d'élection d'IP virtuelle
- **Session synchronization** : préservation des connexions au failover
- **Heartbeat** : lien dédié pour vérifier la santé du peer

---

### Jour 27 — HA pfSense-like avec Keepalived

**Approche Docker** : utiliser `keepalived` pour simuler CARP/VRRP.

Créer `fw-isp-2/` (copie du fw-isp) :
```bash
cp -r fw-isp fw-isp-2
```

Ajouter au `Dockerfile` :
```dockerfile
RUN apt-get install -y keepalived
```

Configuration `keepalived.conf` (master) :
```
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass labcyber
    }
    virtual_ipaddress {
        200.0.0.100/24
    }
}
```

Configuration backup (priority 90).

Test failover :
```bash
docker stop fw-isp           # tuer le master
# Vérifier que fw-isp-2 prend la VIP en quelques secondes
docker exec fw-isp-2 ip addr show eth0 | grep 200.0.0.100
```

**Mesure RTO** : temps depuis l'arrêt jusqu'à la reprise du service.

---

### Jour 28 — HA FortiGate-like (Active/Passive)

Même principe pour les FortiGate-like : créer `fw-client-2`, configurer keepalived sur les interfaces LAN et WAN.

Pour la sync de session avec strongSwan : utiliser `conntrackd` (synchronisation conntrack).

```bash
apt-get install -y conntrackd
```

Configuration `/etc/conntrackd/conntrackd.conf` :
```
General {
    HashSize 32768
    HashLimit 131072
    LogFile on
}
Sync {
    Mode FTFW { }
    Multicast {
        IPv4_address 225.0.0.50
        IPv4_interface eth_sync
        Group 3780
        Interface eth_sync
    }
}
```

---

### Jour 29 — Tests d'endurance

Scénarios :
1. **Coupure FW_CLIENT master** : `docker stop fw-client` → mesurer le temps avant que les ping reprennent depuis client1 vers webserver
2. **Saturation lien WAN** : `iperf3` entre les deux sites, observer les performances VPN
3. **Failover en plein milieu d'un transfert** : préserver l'intégrité ?

```bash
# Préparer iperf3
docker exec sshserver apt install -y iperf3
docker exec sshserver iperf3 -s &

# Depuis client1
docker exec client1 apt install -y iperf3
docker exec client1 iperf3 -c 192.168.20.11 -t 60
# Pendant le test : docker stop fw-client
# Mesurer la coupure
```

---

### Jour 30 — Soutenance Phase 2

Démos live à préparer :
1. Création d'un nouveau VLAN à chaud
2. Test d'isolation inter-VLAN
3. Blocage Squid en direct (montrer une URL bloquée)
4. **Failover live** d'un firewall avec mesure RTO

---

## ✅ Validation Phase 2

| Critère | Validation |
|---|---|
| ≥ 4 VLANs déployés | `docker network ls` |
| Matrice de flux respectée | Script `test-vlan-matrix.sh` 100% OK |
| Filtrage web actif | facebook.com bloqué via Squid |
| Cluster HA fonctionnel | Failover testé avec mesure RTO < 10s |
| Logs centralisés | `/var/log/fw/*.log` exploitables |
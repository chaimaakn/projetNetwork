# 📘 PHASE 2 — Renforcement & Segmentation Avancée (Jours 16-30)

> **Objectif** : Faire évoluer l'architecture vers un environnement entreprise mature avec VLANs, ACLs granulaires, filtrage web, contrôle applicatif et haute disponibilité.

> **Positionnement** : ce document décrit les extensions de Phase 2 a appliquer sur le socle actuellement valide. Conserver les principes deja en place : reseaux WAN/LAN routes sans `internal: true` et resolution d'interfaces par IP plutot que par ordre `ethX`.

> 💡 **Note Docker** : les VLANs natifs (802.1Q) sont possibles avec Docker mais lourds. Nous reproduisons leur **comportement fonctionnel** avec des **réseaux Docker bridge séparés**, ce qui est pédagogiquement équivalent.

> **Statut courant** : la segmentation coeur de Phase 2, le hardening avance, la brique IDS et la haute disponibilite sont maintenant presents dans le depot avec `vlan_voip_net`, `vlan_guest_net`, `dmz_net`, les hotes `voip1`, `guest1`, `dmz-web`, `internet-probe`, les objets `ipset` de `fw-client`, la liste versionnee `fw-client/blocked_domains.txt`, `Suricata` sur `fw-client`, les garde-fous egress de `fw-isp`, les paires `fw-isp` / `fw-isp-2`, `fw-client` / `fw-client-2`, `fw-server` / `fw-server-2`, et les scripts `scripts/test-vlan-matrix.sh`, `scripts/test-policy-hardening.sh`, `scripts/test-suricata.sh`, `scripts/test-ha.sh` et `scripts/test-full-lab.sh`. La prochaine grosse tranche restante est le SIEM / la correlation.

## 🗓️ Semaine 4 — Segmentation VLAN (J16-J20)

### Jour 16 — Conception du plan VLAN

#### Plan de segmentation cible

| ID | Nom VLAN | Rôle | Subnet | Réseau Docker |
|---|---|---|---|---|
| 10 | VLAN_USERS | Postes utilisateurs | 192.168.10.0/24 | `lan_client_net` (existant) |
| 20 | VLAN_VOIP | Téléphonie | 192.168.30.0/24 | `vlan_voip_net` (déployé) |
| 30 | VLAN_GUEST | Invités/WiFi guest | 192.168.40.0/24 | `vlan_guest_net` (déployé) |
| 100 | VLAN_SERVERS | Serveurs internes | 192.168.20.0/24 | `lan_server_net` (existant) |
| 110 | VLAN_DMZ | Serveurs exposés | 192.168.50.0/24 | `dmz_net` (déployé) |
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

**Étape 1** — Vérifier les réseaux déjà ajoutés dans `docker-compose.yml` :

```yaml
# Ajouter dans la section networks: à la fin du docker-compose.yml
  vlan_voip_net:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.30.0/24
          gateway: 192.168.30.254

  vlan_guest_net:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.40.0/24
          gateway: 192.168.40.254

  dmz_net:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.50.0/24
          gateway: 192.168.50.254
```

**Étape 2** — Vérifier le raccordement des firewalls et hotes de test :

```yaml
# Dans la section fw-client > networks: ajouter
      vlan_voip_net:
        ipv4_address: 192.168.30.1
      vlan_guest_net:
        ipv4_address: 192.168.40.1

# Dans la section fw-server > networks: ajouter
      dmz_net:
        ipv4_address: 192.168.50.1

# Hotes de validation
voip1:        192.168.30.10
guest1:       192.168.40.10
dmz-web:      192.168.50.10
internet-probe: 200.0.0.50
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
# Validation directe sur le dépôt courant
bash ./scripts/test-vlan-matrix.sh

# Vérifications ciblées manuelles si besoin
docker exec guest1 nc -zw 3 192.168.20.10 80    # Doit échouer
docker exec guest1 curl -fsSI http://example.com # Doit réussir
docker exec client1 curl -fsS http://192.168.50.10 # Doit réussir
```

**Livrable J17** : sortie verte de `scripts/test-vlan-matrix.sh` + capture des reseaux Docker.

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

Le dépôt contient maintenant le script de validation matrice de flux : `scripts/test-vlan-matrix.sh`

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

**Statut depot** : deja implemente dans `fw-isp/rules.sh` avec blocage sortant FTP/Telnet/SMB/NetBIOS, `connlimit`, rate-limit ICMP et journalisation `[FW_ISP-BLOCK]`. La validation automatisee passe par `scripts/test-policy-hardening.sh`.

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

**Statut depot** : deja implemente dans `fw-client/rules.sh` via des objets et groupes `ipset` (`users_net`, `voip_net`, `guest_net`, `servers_net`, `dmz_net`, `mgmt_net`, `blocked_external`, `web_ports`) utilises directement par les politiques `iptables`.

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

**Statut depot** : deja implemente de facon versionnee via `fw-client/blocked_domains.txt`, copie a l'image par `fw-client/Dockerfile`, preserve au demarrage et valide par `scripts/test-policy-hardening.sh`.

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

**Statut depot** : deja implemente en mode IDS sur `fw-client` avec `Suricata`, un jeu de regles versionne `fw-client/lab.rules`, des logs persistants sous `fw-client/logs/suricata/` et une validation automatisee via `scripts/test-suricata.sh`.

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

**Statut depot** : deja implemente dans `docker-compose.yml`, `fw-isp/keepalived.conf.tmpl`, `fw-isp/entrypoint.sh` et `scripts/test-ha.sh`.

Le design retenu conserve les adresses historiques comme VIPs de service et attribue des IPs de noeud distinctes aux deux pares-feu ISP :

- noeuds `fw-isp` / `fw-isp-2` : `200.0.0.11` / `200.0.0.12`, `10.10.0.11` / `10.10.0.12`, `10.20.0.11` / `10.20.0.12`, `192.168.99.11` / `192.168.99.12`
- VIPs preservees : `200.0.0.10`, `10.10.0.1`, `10.20.0.1`, `192.168.99.1`
- VRRP keepalived en unicast sur chaque segment, avec reprise du DNS, du NTP, du routage et du frontend HAProxy

Validation minimale :
```bash
bash ./scripts/test-ha.sh
docker exec fw-isp ip -o -4 addr show | grep '200.0.0.10/'
docker exec fw-isp-2 ip -o -4 addr show | grep '200.0.0.10/'
```

**Mesure RTO** : la validation automatisee mesure le delai de reprise de la VIP et de la publication HTTP pendant `docker stop fw-isp`.

---

### Jour 28 — HA FortiGate-like (Active/Passive)

**Statut depot** : deja implemente pour `fw-client` / `fw-client-2` et `fw-server` / `fw-server-2`.

Le design applique keepalived sur les VIPs WAN, LAN, DMZ et management, et `conntrackd` sur `mgmt_net` pour la synchronisation d'etat :

- `fw-client*` preserve `10.10.0.2`, `192.168.10.1`, `192.168.30.1`, `192.168.40.1`, `192.168.99.10` comme VIPs
- `fw-server*` preserve `10.20.0.2`, `192.168.20.1`, `192.168.50.1`, `192.168.99.20` comme VIPs
- `ha-state.sh` pilote les transitions master / backup pour IPsec, dnsmasq et la resynchronisation `conntrackd`
- la sync de session est validee via l'augmentation du cache externe `conntrackd` sur les backups, et non via la table noyau du noeud passif

Validation minimale :
```bash
bash ./scripts/test-ha.sh
docker exec fw-client bash -lc "conntrackd -s | grep -A4 'cache external'"
docker exec fw-server bash -lc "ipsec statusall | grep -E 'ESTABLISHED|INSTALLED'"
```

---

### Jour 29 — Tests d'endurance

**Statut depot** : la campagne de bascule automatisee est deja couverte par `scripts/test-ha.sh`, puis revalidee dans `scripts/test-full-lab.sh`.

Scenarios valides aujourd'hui :
1. **Coupure FW_ISP master** : reprise des VIPs WAN / MGMT, DNS et frontend public sur `fw-isp-2`
2. **Coupure FW_CLIENT master** : reprise des VIPs LAN / WAN, continuité du tunnel IPsec et du proxy sur `fw-client-2`
3. **Coupure FW_SERVER master** : reprise des VIPs LAN / WAN, re-etablissement du tunnel IPsec et maintien HTTP / DMZ sur `fw-server-2`

```bash
bash ./scripts/test-ha.sh
bash ./scripts/test-full-lab.sh
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
| ACLs avancees et filtrage web actif | Script `test-policy-hardening.sh` 100% OK |
| IDS / controle applicatif de base | Script `test-suricata.sh` 100% OK |
| Cluster HA fonctionnel | Scripts `test-ha.sh` et `test-full-lab.sh` 100% OK |
| Logs centralisés | `/var/log/fw/*.log` exploitables |
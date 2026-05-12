# 📘 PHASE 1 — Consolidation & Documentation (Jours 1-15)

> **Objectif** : Comprendre, documenter, auditer l'architecture déployée. Aucune modification structurelle n'est apportée. Cette phase est analytique.

> **Note d'état** : le lab Docker est aujourd'hui fonctionnel, mais les noms d'interfaces Docker ne sont pas stables. Quand un exemple ci-dessous mentionne `eth0` / `eth1`, vérifier d'abord les interfaces réelles avec `ip -br addr` ou les IP affectées.

## 🗓️ Semaine 1 — Prise en main & Cartographie

### Jour 1 — Onboarding technique

**Objectif** : déployer le lab et vérifier la connectivité de base.

```bash
# 1) Construction des images
cd hania/
docker compose build

# 2) Lancement
docker compose up -d
docker compose ps

# 3) Vérification connectivité
bash ./scripts/test-connectivity.sh

# 4) Tests manuels
docker exec client1 ping -c 3 192.168.10.1     # client1 -> FW_CLIENT
docker exec client1 ping -c 3 192.168.20.10    # client1 -> webserver (via VPN)
docker exec fw-client ipsec statusall          # Statut du tunnel VPN
```

**Livrable J1** : `livrable_J1_connectivite.md`
```markdown
# Rapport de vérification de connectivité - J1

## Résultats
- [x] Tous les conteneurs up : `docker compose ps`
- [x] Ping intra-LAN_CLIENT : OK
- [x] Ping inter-LAN via VPN : OK
- [x] Tunnel IPsec ESTABLISHED : OK
- [x] Résolution DNS via FW_ISP : OK
- [x] Accès Internet (8.8.8.8) : OK

## Captures (à joindre)
- output `docker compose ps`
- output `ipsec statusall`
- traceroute client1 -> webserver
```

---

### Jour 2 — Documentation topologie

**Outils** : draw.io / Lucidchart / Mermaid

#### Tableau d'adressage à compléter

| Composant | Interface | Réseau Docker | IP | Masque | Passerelle |
|---|---|---|---|---|---|
| FW_ISP | eth0 | internet_net | 200.0.0.10 | /24 | 200.0.0.1 |
| FW_ISP | eth1 | wan_client_net | 10.10.0.1 | /24 | — |
| FW_ISP | eth2 | wan_server_net | 10.20.0.1 | /24 | — |
| FW_ISP | eth3 | mgmt_net | 192.168.99.1 | /24 | — |
| FW_CLIENT | eth0 | wan_client_net | 10.10.0.2 | /24 | 10.10.0.1 |
| FW_CLIENT | eth1 | lan_client_net | 192.168.10.1 | /24 | — |
| FW_CLIENT | eth2 | mgmt_net | 192.168.99.10 | /24 | 192.168.99.1 |
| FW_SERVER | eth0 | wan_server_net | 10.20.0.2 | /24 | 10.20.0.1 |
| FW_SERVER | eth1 | lan_server_net | 192.168.20.1 | /24 | — |
| FW_SERVER | eth2 | mgmt_net | 192.168.99.20 | /24 | 192.168.99.1 |
| client1 | eth0 | lan_client_net | 192.168.10.10 | /24 | 192.168.10.1 |
| client2 | eth0 | lan_client_net | 192.168.10.11 | /24 | 192.168.10.1 |
| kali | eth0 | lan_client_net | 192.168.10.50 | /24 | 192.168.10.1 |
| webserver | eth0 | lan_server_net | 192.168.20.10 | /24 | 192.168.20.1 |
| sshserver | eth0 | lan_server_net | 192.168.20.11 | /24 | 192.168.20.1 |

#### Vérification des interfaces réelles

```bash
# Voir les interfaces de chaque firewall
for fw in fw-isp fw-client fw-server; do
  echo "=== $fw ==="
  docker exec $fw ip -br addr
done

# Voir les réseaux Docker
docker network ls | grep cyber
docker network inspect docker-cyber-lab_lan_client_net
```

**Livrable J2** : schéma annoté (PNG/PDF) + tableau ci-dessus complété avec les vraies IP observées.

---

### Jour 3 — Analyse FW_ISP (équivalent pfSense)

```bash
# Entrer dans le conteneur
docker exec -it fw-isp bash

# 1. Inspection des règles iptables (équivalent Rules > WAN/LAN sur pfSense)
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v

# 2. Configuration DNS (équivalent Services > DNS Resolver)
cat /etc/dnsmasq.conf
ps aux | grep dnsmasq

# 3. Configuration NTP (équivalent Services > NTP)
cat /etc/chrony/chrony.conf
chronyc sources -v

# 4. HAProxy (équivalent Services > HAProxy package)
cat /etc/haproxy/haproxy.cfg

# 5. IP forwarding
cat /proc/sys/net/ipv4/ip_forward    # doit être 1

# 6. Routes
ip route show
```

**Livrable J3** : `livrable_J3_analyse_fwisp.md` qui doit contenir :
- Liste des règles INPUT/FORWARD avec interprétation (à quoi sert chaque règle ?)
- Liste des forwarders DNS configurés
- Liste des sources NTP en amont
- Configuration NAT (POSTROUTING)
- Identifications des règles **trop permissives** (préparation J9)

---

### Jour 4 — Analyse FW_CLIENT et FW_SERVER

```bash
# Pour FW_CLIENT
docker exec -it fw-client bash

# Politiques iptables
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v

# IPsec - Phase 1 et Phase 2
cat /etc/ipsec.conf
ipsec listall                # Liste des connexions
ipsec statusall              # Statut détaillé (SAs, child SAs)

# DHCP
cat /etc/dnsmasq.conf
cat /var/log/fw/dhcp.log    # logs DHCP

# Squid (filtrage web)
cat /etc/squid/squid.conf
ls /var/log/squid/

# Même chose pour FW_SERVER
docker exec -it fw-server bash
cat /etc/ipsec.conf
ipsec statusall
cat /etc/chrony/chrony.conf  # serveur NTP
chronyc clients              # Qui se synchronise ?
```

**Livrable J4** : 2 rapports d'analyse (FW_CLIENT et FW_SERVER) avec :
- Toutes les politiques de sécurité documentées
- Paramètres VPN IPsec : algos, durée de vie, PFS, DH groups
- Analyse du DHCP et du NTP
- Point d'attention : algos cryptographiques utilisés ?

---

### Jour 5 — Monitoring Uptime Kuma

```bash
# Accès web
# Ouvrir http://localhost:3001 dans le navigateur de l'hôte
# (premier accès : créer un compte admin)
```

**Sondes à configurer (cliquer sur "Add New Monitor")** :

| Type | Nom | Cible | Intervalle |
|---|---|---|---|
| Ping | FW_ISP | 192.168.99.1 | 60s |
| Ping | FW_CLIENT | 192.168.99.10 | 60s |
| Ping | FW_SERVER | 192.168.99.20 | 60s |
| HTTP | WebServer | http://192.168.20.10 | 60s |
| TCP | SSH Server | 192.168.20.11:22 | 60s |
| DNS | DNS FW_ISP | 192.168.99.1, query=labcyber.local | 120s |

**Test de simulation de panne** :
```bash
docker stop webserver
# → Vérifier que Uptime Kuma déclenche l'alerte sous 60s
docker start webserver
```

**Livrable J5** : capture d'écran du dashboard Uptime Kuma + rapport décrivant les sondes et le délai de détection mesuré.

---

## 🗓️ Semaine 2 — Analyse approfondie

### Jour 6 — Analyse du routage statique

```bash
# Sur chaque firewall
for fw in fw-isp fw-client fw-server; do
  echo "=== $fw ==="
  docker exec $fw ip route
done

# Test traceroute (chemins entre LANs)
docker exec client1 apt install -y traceroute   # si besoin
docker exec client1 traceroute -n 192.168.20.10
```

**Livrable J6** : tableau des routes par firewall + diagramme des chemins.

---

### Jour 7 — Analyse VPN IPsec en profondeur

```bash
# 1. Statut détaillé du tunnel
docker exec fw-client ipsec statusall

# 2. Vérifier les algorithmes en place
# Doit afficher : IKE: AES_CBC_256/HMAC_SHA2_256_128/MODP_2048
#                ESP: AES_CBC_256/HMAC_SHA2_256_128

# 3. Capture Wireshark sur le tunnel
docker exec fw-client tcpdump -i eth0 -w /var/log/fw/ipsec_capture.pcap port 500 or port 4500 or esp &
# Générer du trafic : depuis client1, ping webserver
docker exec client1 ping -c 10 192.168.20.10
# Arrêter la capture (Ctrl+C dans la session tcpdump)

# Récupérer le pcap
docker cp fw-client:/var/log/fw/ipsec_capture.pcap ./capture_vpn.pcap
# Ouvrir dans Wireshark sur l'hôte
```

**Livrable J7** : fiche VPN documentant :
- Algorithmes Phase 1 (IKE) : AES-256, SHA-256, DH MODP-2048
- Algorithmes Phase 2 (ESP) : AES-256, SHA-256, PFS = MODP-2048
- Lifetime IKE : 8h ; Lifetime CHILD : 1h
- DPD : 30s/120s
- **Recommandations** : passer en certificat PKI plutôt que PSK (à appliquer Phase 3)

---

### Jour 8 — Centralisation du trafic Internet

**Test de leak** : vérifier que les firewalls clients ne contournent pas FW_ISP.

```bash
# Depuis FW_CLIENT, on ne doit PAS pouvoir sortir directement sur Internet
# (tout doit passer par FW_ISP)

docker exec fw-client traceroute -n 8.8.8.8
# Le 1er saut DOIT être 10.10.0.1 (FW_ISP)

# Vérifier qu'il n'y a qu'une seule route par défaut
docker exec fw-client ip route | grep default
# Doit afficher : default via 10.10.0.1 dev eth0

# Si on veut tester un leak (à NE PAS faire en prod)
# docker exec fw-client curl -v http://200.0.0.10  # Direct vers Internet ?
```

**Livrable J8** : rapport démontrant l'absence de leaks + capture traceroute.

---

### Jour 9 — Premier audit de sécurité

```bash
# Démarrer l'audit depuis Kali
docker exec -it kali bash

# 1. Scan interne
nmap -sS -p- 192.168.10.0/24
nmap -sS -p- 192.168.99.0/24

# 2. Identifier les services exposés
nmap -sV -p- 192.168.99.10  # FW_CLIENT côté management
nmap -sV -p- 192.168.20.11  # SSHServer

# 3. Analyse des comptes
# Sur le sshserver - tester les credentials par défaut
ssh admin@192.168.20.11   # admin/admin123 (vulnérabilité volontaire)
```

**Vulnérabilités à identifier (niveau 1)** :
- ❗ SSH avec mot de passe `admin/admin123` sur sshserver
- ❗ SSH avec `root/toor` activé
- ❗ Pas d'authentification multi-facteur
- ❗ HTTP non chiffré sur webserver
- ❗ PSK IPsec dans le code source (si exfiltré → tunnel cassable offline)
- ⚠️ Ports ICMP autorisés sans limitation
- ⚠️ Logs limités à 5/min (peut masquer des attaques rapides)

**Livrable J9** : `livrable_J9_audit_v1.md` avec liste priorisée des vulnérabilités.

---

### Jour 10 — Synthèse rapport S1-S2

Structure recommandée :
1. Résumé exécutif (1 page)
2. Architecture déployée (schémas + tableau adressage)
3. Analyse FW_ISP
4. Analyse FW_CLIENT
5. Analyse FW_SERVER
6. Analyse VPN IPsec
7. Monitoring Uptime Kuma
8. Vulnérabilités identifiées (Top 10)
9. Recommandations à court terme

---

## 🗓️ Semaine 3 — Corrections, hardening, soutenance

### Jour 11 — Corrections rapides post-audit

```bash
# 1. Changer les mots de passe faibles sur sshserver
docker exec -it sshserver bash
passwd admin   # Mettre un mdp fort
passwd test    # idem
# Désactiver le login root direct
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
service ssh restart
exit

# 2. Désactiver les comptes inutiles
docker exec sshserver userdel -r test

# 3. Sur FW_CLIENT, restreindre Squid au LAN_CLIENT uniquement (déjà fait dans squid.conf)
# Vérifier :
docker exec fw-client grep "http_access" /etc/squid/squid.conf
```

**Livrable J11** : changelog des modifications.

---

### Jour 12 — Hardening de base

Checklist CIS-like à appliquer :

```bash
# Sur chaque firewall
docker exec -it fw-client bash

# 1. SSH : authentification clé uniquement (à terme)
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# 2. Désactiver les services inutilisés
ss -tlnp   # Lister les sockets en écoute

# 3. Logging activé sur toutes les règles
# (déjà configuré dans rules.sh, vérifier)
iptables -L -n -v | grep LOG

# 4. Timeouts session
# Pour SSH :
echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
echo "ClientAliveCountMax 0" >> /etc/ssh/sshd_config
```

**Livrable J12** : checklist hardening complétée.

---

### Jour 13 — Tests de non-régression

```bash
# Réexécuter le script de Phase 1
./scripts/test-connectivity.sh

# Vérification VPN après hardening
docker exec fw-client ipsec statusall

# Test DNS, DHCP, NTP
docker exec client1 nslookup web.labcyber.local
docker exec client1 dhclient -v eth0 || true  # tester DHCP
docker exec client1 chronyc tracking 2>/dev/null || ntpdate -q 192.168.99.1
```

---

### Jour 14 — Théorie VLANs & ACLs (préparation Phase 2)

Notions à réviser :
- IEEE 802.1Q (trunk, tagging, native VLAN)
- Inter-VLAN routing (router-on-a-stick vs L3 switch)
- ACL stateless vs stateful
- Application layer filtering (L7)

**QCM type** :
1. Quelle est la différence entre une ACL standard et étendue Cisco ?
2. Que signifie PFS dans IPsec ?
3. Différence entre Active/Passive et Active/Active en HA ?

---

### Jour 15 — Soutenance Phase 1

**Format** : 15 min de présentation + 10 min de questions.

**Plan recommandé** :
1. (2 min) Architecture déployée + démo `docker compose ps`
2. (4 min) Cartographie réseau (schéma + tableau adressage)
3. (4 min) Analyse de sécurité : top 5 vulnérabilités
4. (3 min) Hardening appliqué + démo
5. (2 min) Roadmap Phase 2

---

## ✅ Critères de validation Phase 1

| Critère | Validation |
|---|---|
| Lab Docker fonctionnel | `docker compose ps` montre tous les services UP |
| VPN IPsec établi | `ipsec statusall` montre INSTALLED/ESTABLISHED |
| Connectivité cross-LAN | client1 ping webserver = OK |
| Internet via FW_ISP | traceroute confirme passage par 10.10.0.1 |
| Schéma réseau | Doc draw.io ou équivalent fournie |
| Audit initial | ≥ 5 vulnérabilités identifiées + corrigées |
| Monitoring | ≥ 6 sondes Uptime Kuma actives |
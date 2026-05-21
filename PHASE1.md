# Guide de Soutenance — Phase 1
## Sécurité des Réseaux et Infrastructures | 4ème SSI

---

## ✅ Réponse courte : oui, tu parles des vulnérabilités

La Phase 1 inclut explicitement J9 (audit de sécurité) et J11-J12 (corrections).
Tu dois présenter les vulnérabilités identifiées ET les correctifs appliqués.
C'est un des critères de validation officiels : "≥ 5 vulnérabilités identifiées + corrigées".

---

## 🎯 Plan de présentation (15 min + 10 min questions)

### Partie 1 — Architecture déployée (2-3 min)
**Ce que tu dis :**
"J'ai déployé un lab Docker sur Kali Linux reproduisant une architecture d'entreprise réelle
avec 3 zones réseau, 3 paires de firewalls en haute disponibilité et un tunnel VPN IPsec."

**Ce que tu montres :**
```bash
# Montrer que tout tourne
cd ~/projetNetwork/hania
sudo docker compose ps
```

### Partie 2 — Cartographie réseau (3-4 min)
**Ce que tu dis :**
"L'infrastructure est composée de 6 zones isolées interconnectées via FW_ISP (équivalent pfSense),
FW_CLIENT et FW_SERVER (équivalents FortiGate)."

**Ce que tu montres :**
```bash
# Tableau d'adressage réel
sudo docker inspect $(sudo docker ps -q) \
  | grep -E '"Name"|"IPAddress"' \
  | grep -v '""' | paste - -

# Tables de routage des firewalls
for fw in fw-isp fw-client fw-server; do
  echo "=== $fw ==="
  sudo docker exec $fw ip route show
done
```
→ Montre ton schéma draw.io / tableau d'adressage du rapport

### Partie 3 — Analyse des firewalls (3-4 min)
**Ce que tu dis :**
"Chaque firewall a été analysé : règles iptables, VPN, DNS, NTP, DHCP et proxy web."

**Ce que tu montres :**
```bash
# Règles firewall FW_CLIENT
sudo docker exec fw-client iptables -L FORWARD -n --line-numbers | head -20

# Statut VPN IPsec
sudo docker exec fw-client ipsec status | grep ESTABLISHED

# DNS
sudo docker exec client1 nslookup web.labcyber.local

# NTP
sudo docker exec fw-server chronyc tracking | grep -E "Reference|Stratum|Leap"

# Proxy Squid
sudo docker exec fw-client grep "http_access" /etc/squid/squid.conf
```

### Partie 4 — Audit de sécurité + Vulnérabilités (3-4 min)
**Ce que tu dis :**
"L'audit a révélé 10 vulnérabilités dont 2 critiques. Les principales sont :
- PSK IPsec stocké en clair → risque si fichier exfiltré
- Mot de passe SSH faible admin/admin123 → accès non autorisé possible
- HTTP non chiffré sur le webserver → interception possible
- LDAP non chiffré exposé sur port 389"

**Ce que tu montres :**
```bash
# Scan Nmap depuis Kali — découverte des services exposés
sudo docker exec kali nmap -sV 192.168.20.0/24
sudo docker exec kali nmap -sV 192.168.10.0/24

# Montrer le port 80 ouvert sur webserver
sudo docker exec kali nmap -p 80,443 192.168.20.10

# Montrer que SSH répond sur sshserver
sudo docker exec fw-server nc -zv 192.168.20.11 22
```

### Partie 5 — Correctifs appliqués + Hardening (1-2 min)
**Ce que tu dis :**
"J'ai appliqué les corrections urgentes : changement du mot de passe admin,
vérification PermitRootLogin, restriction Squid au LAN_CLIENT,
activation du logging iptables sur toutes les règles."

**Ce que tu montres :**
```bash
# Mot de passe changé — PermitRootLogin vérifié
sudo docker exec sshserver grep "PermitRootLogin" /etc/ssh/sshd_config

# Squid restreint
sudo docker exec fw-client grep "http_access" /etc/squid/squid.conf

# Logging actif sur tous les firewalls
sudo docker exec fw-client iptables -L -n -v | grep LOG
sudo docker exec fw-server iptables -L -n -v | grep LOG

# SSH non installé sur les firewalls (surface réduite)
sudo docker exec fw-client which sshd 2>/dev/null || echo "SSH absent sur fw-client ✅"
```

### Partie 6 — Tests de validation (1 min)
**Ce que tu dis :**
"Les scripts de validation automatique confirment que tout fonctionne
et que les correctifs n'ont pas cassé la connectivité."

**Ce que tu montres :**
```bash
# Script de connectivité
cd ~/projetNetwork/hania
sudo bash scripts/test-connectivity.sh

# Haute disponibilité
sudo bash scripts/test-ha.sh 2>&1 | grep -E "OK|FAIL|==="

# Matrice de flux VLAN
sudo bash scripts/test-vlan-matrix.sh 2>&1 | grep -E "OK|FAIL|==="
```

### Conclusion — Roadmap Phase 2 (30 sec)
**Ce que tu dis :**
"Pour la Phase 2, je vais déployer les VLANs 802.1Q,
renforcer les ACLs, activer HTTPS sur le webserver
et migrer IPsec de PSK vers certificats PKI."

---

## 📋 Critères de validation officiels — checklist

| Critère | Commande de démo | Statut |
|---|---|---|
| Lab Docker fonctionnel | `sudo docker compose ps` | ✅ |
| VPN IPsec établi | `ipsec status \| grep ESTABLISHED` | ✅ |
| Connectivité cross-LAN | `docker exec client1 ping -c 2 192.168.20.10` | ✅ |
| Internet via FW_ISP | `docker exec client1 traceroute 8.8.8.8` | ✅ |
| Schéma réseau | Fichier draw.io / tableau adressage | ✅ |
| ≥ 5 vulnérabilités identifiées | Tableau audit rapport | ✅ (10 trouvées) |
| Correctifs appliqués | Démonstration live | ✅ |
| Monitoring actif | `http://127.0.0.1:3001` | ✅ |

---

## ❓ Questions probables du prof et tes réponses

**Q : Pourquoi utiliser Docker plutôt que pfSense/FortiGate réels ?**
R : "Les images propriétaires pfSense/FortiGate nécessitent des licences coûteuses
et des ressources importantes. Docker permet de simuler les mêmes fonctionnalités
(iptables = FortiGate policies, dnsmasq = DNS Resolver pfSense, strongSwan = IPsec FortiGate)
avec 4 GB de RAM au lieu de 16 GB, et un déploiement reproductible en 30 secondes."

**Q : Qu'est-ce que VRRP et comment ça marche ici ?**
R : "VRRP (Virtual Router Redundancy Protocol) permet à deux firewalls de partager
une IP virtuelle. Le primaire (priorité 200) détient la VIP. Si il tombe,
le secondaire (priorité 100) prend la VIP automatiquement en moins de 3 secondes.
conntrackd synchronise les sessions TCP actives pour éviter les coupures."

**Q : Pourquoi PSK est dangereux pour IPsec ?**
R : "Avec PSK, si un attaquant capture le trafic IKE et exfiltre le fichier ipsec.secrets,
il peut déchiffrer tout le trafic VPN offline par brute-force ou dictionnaire.
Avec PKI, même si la clé privée est compromise, les sessions passées sont protégées
par Perfect Forward Secrecy."

**Q : Quelle différence entre MODP-2048 et MODP-4096 ?**
R : "MODP-2048 offre une sécurité de 112 bits équivalente — acceptable aujourd'hui
mais pas recommandé pour des données sensibles à long terme.
MODP-4096 offre 140 bits équivalents. La NSA recommande ECP-384 (courbes elliptiques)
qui est plus efficace et plus sûr."

**Q : Pourquoi le port 389 LDAP est-il critique ?**
R : "LDAP sur port 389 transmet les credentials en clair sur le réseau.
Un attaquant en position MITM peut capturer les mots de passe avec Wireshark.
La solution est LDAPS (port 636) qui chiffre la communication via TLS."

**Q : Qu'est-ce que le principe du moindre privilège appliqué ici ?**
R : "Sur les firewalls, la politique par défaut est DROP — tout est bloqué sauf
ce qui est explicitement autorisé. Par exemple fw-server n'autorise que
les ports 22, 80 et 443 depuis LAN_CLIENT vers LAN_SERVER, et bloque tout le reste.
Kali (machine de pentest) est isolée du LAN_SERVER."

---

## 🖥️ Commandes de démo rapide (à lancer dans l'ordre)

```bash
# 1. Montrer l'infra complète
cd ~/projetNetwork/hania
sudo docker compose ps

# 2. Connectivité
sudo bash scripts/test-connectivity.sh

# 3. VPN
sudo docker exec fw-client ipsec status | grep ESTABLISHED

# 4. DNS
sudo docker exec client1 nslookup web.labcyber.local

# 5. Audit Nmap
sudo docker exec kali nmap -sV --open 192.168.20.0/24 2>/dev/null | grep -E "Nmap scan|open|service"

# 6. Firewall rules
sudo docker exec fw-client iptables -L FORWARD -n | head -15

# 7. HA
sudo bash scripts/test-ha.sh 2>&1 | grep -E "\[OK\]|\[FAIL\]|===" | head -30

# 8. Monitoring
# Ouvrir http://127.0.0.1:3001 dans le navigateur
```

---

## 📁 Documents à avoir ouverts pendant la soutenance

1. Ce guide (terminal)
2. Ton rapport Phase 1 (PDF ou Word)
3. Schéma d'architecture draw.io
4. Dashboard Uptime Kuma (navigateur : http://127.0.0.1:3001)
5. Grafana (navigateur : http://127.0.0.1:3002)
6. Terminal avec le lab démarré

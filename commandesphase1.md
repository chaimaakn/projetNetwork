# Démonstrations Phase 1 — Soutenance
# Toutes les commandes avec explications complètes

> **Répertoire de travail :** `cd ~/projetNetwork/hania`
> **Rappel IPs clés :**
> - 192.168.10.1 = VIP gateway LAN_CLIENT (fw-client MASTER)
> - 10.10.0.2 = VIP WAN fw-client (endpoint IPsec côté client)
> - 192.168.20.1 = VIP gateway LAN_SERVER (fw-server MASTER)
> - 10.20.0.2 = VIP WAN fw-server (endpoint IPsec côté serveur)
> - 192.168.20.10 = webserver (serveur web interne)
> - 192.168.20.11 = sshserver (serveur SSH interne)
> - 192.168.99.1 = VIP MGMT fw-isp (gateway réseau management)
> - 192.168.99.50 = Uptime Kuma (monitoring)
> - 192.168.50.10 = dmz-web (serveur web exposé Internet)
> - 192.168.10.10 = client1 (poste utilisateur)
> - 192.168.10.50 = kali (machine pentest)

---

## DÉMO 1 — Tous les containers sont UP

```bash
sudo docker compose ps
```

**Ce que tu vois :** Liste de tous les containers avec STATUS = Up
**Ce que tu dis :**
> "Toute l'infrastructure est déployée sous Docker :
> 3 paires de firewalls en HA (fw-isp/fw-isp-2, fw-client/fw-client-2, fw-server/fw-server-2),
> les serveurs (webserver, sshserver, dmz-web),
> les clients (client1, client2, kali, voip1, guest1),
> et la stack de monitoring (uptime-kuma, grafana, loki, promtail, log-collector)."

---

## DÉMO 2 — Haute Disponibilité Active/Passive

### Étape 1 — Montrer l'état normal (fw-client = MASTER)

```bash
sudo docker exec fw-client ip addr show | grep -E "192.168.10.1|10.10.0.2"
```

**Ce que tu vois :**
```
inet 10.10.0.2/24 scope global secondary eth4
inet 192.168.10.1/24 scope global secondary eth0
```

**Explication des IPs :**
- `10.10.0.2` → VIP WAN de fw-client = l'adresse que fw-server connaît comme endpoint IPsec
  C'est l'IP publique virtuelle qui flotte entre fw-client et fw-client-2
- `192.168.10.1` → VIP LAN = la gateway de tous les utilisateurs (client1, client2, kali)
  Quand client1 envoie un paquet, il l'envoie vers cette IP
- `secondary` → ajouté dynamiquement par keepalived par-dessus l'IP physique 10.10.0.21

**Ce que tu dis :**
> "fw-client est MASTER — il détient les deux VIPs.
> 192.168.10.1 est la gateway des utilisateurs,
> 10.10.0.2 est l'endpoint du tunnel IPsec.
> Ces IPs sont marquées 'secondary' car keepalived les a ajoutées
> dynamiquement par-dessus l'IP physique 10.10.0.21."

---

### Étape 2 — Montrer que fw-client-2 n'a PAS les VIPs (BACKUP)

```bash
sudo docker exec fw-client-2 ip addr show | grep -E "192.168.10.1|10.10.0.2"
```

**Ce que tu vois :**
```
inet 10.10.0.22/24 brd 10.10.0.255 scope global eth4
```
(seulement son IP physique 10.10.0.22 — aucune VIP)

**Ce que tu dis :**
> "fw-client-2 est BACKUP — il n'a que son IP physique 10.10.0.22.
> Il reçoit les heartbeats VRRP de fw-client toutes les secondes via le réseau MGMT.
> Tant que fw-client répond, fw-client-2 reste passif et ne traite aucun trafic."

---

### Étape 3 — Simuler la panne de fw-client (failover)

```bash
sudo docker stop fw-client
```

**Ce que tu dis :**
> "Je coupe fw-client — keepalived sur fw-client-2 va détecter
> l'absence de heartbeat VRRP après 3 secondes et prendre les VIPs."

```bash
sleep 5
sudo docker exec fw-client-2 ip addr show | grep -E "192.168.10.1|10.10.0.2"
```

**Ce que tu vois :**
```
inet 10.10.0.22/24 brd 10.10.0.255 scope global eth4
inet 10.10.0.2/24 scope global secondary eth4      ← VIP WAN reprise
inet 192.168.10.1/24 scope global secondary eth0   ← VIP LAN reprise
```

**Explication des IPs :**
- fw-client-2 a maintenant les mêmes VIPs qu'avait fw-client
- 10.10.0.22 = son IP physique (inchangée)
- 10.10.0.2 = VIP WAN reprise → le tunnel IPsec continue depuis fw-client-2
- 192.168.10.1 = VIP LAN reprise → client1 continue d'envoyer vers cette gateway

**Ce que tu dis :**
> "fw-client-2 a repris les deux VIPs en moins de 5 secondes.
> Pour les utilisateurs, c'est totalement transparent."

---

### Étape 4 — Prouver que la connectivité est maintenue pendant le failover

```bash
sudo docker exec client1 ping -c 2 192.168.20.10
```

**Ce que tu vois :** 0% packet loss, même après la panne

**Explication des IPs :**
- `192.168.20.10` = webserver dans LAN_SERVER
- client1 (192.168.10.10) atteint webserver via fw-client-2 qui a pris le relais

**Ce que tu dis :**
> "client1 (192.168.10.10) continue d'atteindre le webserver (192.168.20.10)
> sans interruption. Le tunnel IPsec s'est rétabli automatiquement
> depuis fw-client-2. conntrackd avait synchronisé les sessions actives
> donc les connexions TCP établies survivent au basculement."

---

### Étape 5 — Restaurer fw-client (retour au MASTER)

```bash
sudo docker start fw-client
sleep 15
sudo docker exec fw-client ip addr show | grep -E "192.168.10.1|10.10.0.2"
```

**Ce que tu vois :**
```
inet 10.10.0.21/24 brd 10.10.0.255 scope global eth4
inet 10.10.0.2/24 scope global secondary eth4      ← VIP reprise
inet 192.168.10.1/24 scope global secondary eth0   ← VIP reprise
```

**Ce que tu dis :**
> "fw-client reprend automatiquement les VIPs car sa priorité VRRP est 200
> contre 150 pour fw-client-2. C'est la preemption VRRP.
> fw-client-2 repasse BACKUP sans intervention manuelle.
> Le sleep 15 est nécessaire car keepalived met ~10-15 secondes
> à redémarrer complètement à l'intérieur du container."

---

## DÉMO 3 — Tunnel VPN IPsec

```bash
sudo docker exec fw-client ipsec status | grep ESTABLISHED
```

**Ce que tu vois :**
```
site-to-site[1]: ESTABLISHED X minutes ago,
  10.10.0.2[fw-client.labcyber.local]...10.20.0.2[fw-server.labcyber.local]
```

**Explication des IPs :**
- `10.10.0.2` = VIP WAN de fw-client = endpoint IPsec LOCAL (côté client)
  C'est l'adresse que fw-server connaît comme "l'autre bout du tunnel"
- `10.20.0.2` = VIP WAN de fw-server = endpoint IPsec DISTANT (côté serveur)
  Ces deux IPs sont sur le réseau WAN (10.10.0.0/24 et 10.20.0.0/24) géré par fw-isp

```bash
sudo docker exec fw-client ipsec statusall | grep -E "AES|SHA|MODP|proposal"
```

**Ce que tu vois :**
```
IKE proposal: AES_CBC_256/HMAC_SHA2_256_128/PRF_HMAC_SHA2_256/MODP_2048
ESP proposal: AES_CBC_256/HMAC_SHA2_256_128
```

**Ce que tu dis :**
> "Le tunnel est établi entre 10.10.0.2 (fw-client) et 10.20.0.2 (fw-server).
> Ces IPs sont les VIPs WAN des firewalls — pas les IPs physiques.
> Ainsi même après un failover HA, le tunnel reste établi car les VIPs ne changent pas.
> Les algorithmes sont AES-256 pour le chiffrement, SHA-256 pour l'intégrité,
> et MODP-2048 (Diffie-Hellman group 14) pour l'échange de clés.
> Le '!' dans la config impose ces algorithmes sans fallback vers des algos faibles."

```bash
sudo docker exec fw-client ipsec statusall | grep "child:"
```

**Ce que tu vois :**
```
child: 192.168.10.0/24 192.168.30.0/24 === 192.168.20.0/24 192.168.50.0/24
```

**Explication :**
- Gauche du `===` = sous-réseaux côté fw-client qui passent dans le tunnel :
  - 192.168.10.0/24 = LAN_USERS (client1, client2, kali)
  - 192.168.30.0/24 = VLAN_VOIP (voip1)
- Droite du `===` = sous-réseaux côté fw-server qui passent dans le tunnel :
  - 192.168.20.0/24 = LAN_SERVER (webserver, sshserver)
  - 192.168.50.0/24 = DMZ (dmz-web)

**Ce que tu dis :**
> "Les sélecteurs de trafic définissent quels sous-réseaux sont chiffrés.
> Tout paquet de 192.168.10.0/24 vers 192.168.20.0/24 est automatiquement
> encapsulé dans IPsec ESP — le client n'a rien à faire."

---

## DÉMO 4 — Connectivité cross-LAN via VPN

```bash
sudo docker exec client1 ping -c 2 192.168.20.10
```

**Explication des IPs :**
- `client1` = machine source avec IP 192.168.10.10 (LAN_CLIENT)
- `192.168.20.10` = webserver (LAN_SERVER) — réseau différent, séparé par 2 firewalls et un VPN

**Ce que tu dis :**
> "client1 (192.168.10.10) atteint webserver (192.168.20.10).
> Le paquet part de LAN_CLIENT, traverse fw-client qui l'encapsule dans IPsec,
> le tunnel chiffré traverse le WAN via fw-isp, fw-server désencapsule
> et livre au webserver. Tout ça de façon transparente pour client1."

```bash
sudo docker exec client1 curl -s http://192.168.20.10
```

**Ce que tu vois :**
```html
<html><body><h1>LabCyber Web Server</h1>
<p>Serveur interne - Confidentiel</p>
<!-- TODO: remove debug info: app=v1.2.3, db=mysql-5.7 -->
</body></html>
```

**Ce que tu dis :**
> "Le serveur web répond. Et on voit déjà une vulnérabilité identifiée en Phase 3 :
> le commentaire HTML expose la version applicative (v1.2.3) et la base de données
> (mysql-5.7) — c'est VULN-005, corrigée en Phase 3."

---

## DÉMO 5 — Isolation du réseau MANAGEMENT

```bash
# Test 1 : ping MGMT depuis Kali (192.168.10.50) — ICMP passe (VULN-009)
sudo docker exec kali ping -c 2 192.168.99.1 2>&1 | tail -2
```

**Ce que tu vois :** ping réussit (0% loss)

**Ce que tu dis :**
> "Le ping ICMP vers MGMT (192.168.99.1 = VIP MGMT de fw-isp) fonctionne
> depuis Kali — c'est VULN-009 documentée en Phase 3 :
> l'ICMP inter-VLAN n'est pas filtré.
> Mais regardons les services TCP — là c'est bloqué :"

```bash
# Test 2 : connexion TCP vers Uptime Kuma depuis Kali — doit être BLOQUÉ
sudo docker exec kali nc -zv -w 2 192.168.99.50 3001 2>&1
```

**Ce que tu vois :** `timed out` — connexion refusée

**Explication des IPs :**
- 192.168.99.50 = Uptime Kuma sur le réseau MGMT
- Port 3001 = interface web d'Uptime Kuma
- Kali (192.168.10.50) est dans LAN_USERS → ne doit pas accéder à MGMT

**Ce que tu dis :**
> "Le service TCP (port 3001) est bien bloqué — un attaquant depuis LAN_USERS
> ne peut pas accéder aux outils de monitoring.
> Le correctif ICMP de VULN-009 est appliqué en Phase 3 via iptables."

```bash
# Test 3 : DNS fonctionne depuis client1 (autorisé explicitement)
sudo docker exec client1 dig @192.168.99.1 web.labcyber.local +short
```

**Ce que tu vois :** `192.168.20.10`

**Explication des IPs :**
- `192.168.99.1` = VIP MGMT de fw-isp = serveur DNS du lab
- `web.labcyber.local` = nom DNS interne du webserver
- Résultat `192.168.20.10` = IP du webserver

**Ce que tu dis :**
> "DNS est autorisé explicitement depuis tous les VLANs vers 192.168.99.1
> car c'est un service nécessaire. On voit que web.labcyber.local résout
> vers 192.168.20.10 — la résolution DNS interne fonctionne."

---

## DÉMO 6 — Monitoring Uptime Kuma + Grafana

```bash
# Vérifier que les interfaces sont accessibles depuis l'hôte
curl -s -o /dev/null -w "Uptime Kuma: %{http_code}\n" http://127.0.0.1:3001
curl -s -o /dev/null -w "Grafana: %{http_code}\n" http://127.0.0.1:3002
```

Puis ouvrir dans le navigateur Kali :
- `http://127.0.0.1:3001` → Uptime Kuma (10 sondes actives)
- `http://127.0.0.1:3002` → Grafana (user: admin / pass: labcyber-admin)

**Simulation de panne :**
```bash
sudo docker stop sshserver
# Attendre 1-2 minutes → SSHServer passe ROUGE dans Uptime Kuma
sudo docker start sshserver
# Attendre → repasse VERT
```

**Ce que tu dis :**
> "Uptime Kuma surveille 10 services en temps réel :
> les 3 paires HA des firewalls (VIPs MGMT), le webserver (HTTP) et le sshserver (TCP/22).
> Quand je coupe sshserver, l'alerte passe au rouge.
> Grafana avec Loki centralise tous les logs — on peut voir les drops iptables,
> les alertes Suricata, les événements keepalived."

---

## DÉMO 7 — Segmentation inter-VLAN

```bash
echo "=== TEST SEGMENTATION ===" && \
echo -n "MGMT ping depuis Kali (VULN-009 ICMP) : " && \
sudo docker exec kali ping -c 1 -W 2 192.168.99.1 2>&1 | grep -E "loss|unreachable" && \
echo -n "GUEST ping depuis Kali (doit passer - meme FW) : " && \
sudo docker exec kali ping -c 1 -W 2 192.168.40.10 2>&1 | grep -E "loss|unreachable" && \
echo -n "DMZ HTTP depuis Kali (autorise) : " && \
sudo docker exec kali curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://192.168.50.10 && \
echo -n "MGMT TCP Uptime Kuma depuis Kali (BLOQUE) : " && \
sudo docker exec kali nc -zv -w 2 192.168.99.50 3001 2>&1 | grep -E "timeout|refused|open"
```

**Ce que tu dis :**
> "La matrice de flux Phase 2 est respectée :
> DMZ HTTP (192.168.50.10) accessible depuis USERS — c'est autorisé.
> MGMT TCP bloqué — les outils d'administration sont protégés.
> ICMP inter-VLAN non filtré = VULN-009, corrigée en Phase 3
> avec iptables DROP ICMP sur fw-client FORWARD."

---

## DÉMO 8 — Script de validation automatique

```bash
sudo bash scripts/test-connectivity.sh
```

**Ce que tu dis :**
> "Ce script automatise tous les tests de connectivité.
> Il vérifie : intra-LAN, cross-VPN HTTP et SSH, NAT Internet, DNS.
> Tous les tests passent — l'infrastructure est fonctionnelle."
Structure générale
Il définit d'abord des fonctions utilitaires :

ok() — affiche en vert [OK]
fail() — affiche en rouge [FAIL] et incrémente un compteur d'erreurs
ping_check() — teste un ping entre deux containers
wait_for_container_shell() — réessaie une commande plusieurs fois avec délai (utile pour les services lents à démarrer)
wait_for_vpn() — attend que le tunnel IPsec soit établi avant de continuer


Tests effectués dans l'ordre
1. Tests intra-LAN
Vérifie que les machines du même réseau se voient :

client1 → client2 (même LAN_CLIENT)
client1 → FW_CLIENT gateway (192.168.10.1)

2. Tests vers les firewalls

client1 → FW_ISP (10.10.0.1) — vérifie que le WAN est joignable
webserver → FW_SERVER (192.168.20.1) — vérifie la gateway du LAN_SERVER

3. Tests cross-LAN via VPN
C'est le test le plus important — il attend d'abord que le tunnel IPsec soit ESTABLISHED, puis vérifie :

HTTP depuis client1 vers webserver (trafic qui traverse le VPN)
SSH depuis client1 vers sshserver (trafic qui traverse le VPN)

4. Test Internet

client1 → 8.8.8.8 — vérifie que le NAT fonctionne et qu'Internet est accessible

5. Test DNS

Résolution de web.labcyber.local depuis client1 — vérifie que dnsmasq sur FW_ISP répond correctement


---

## RÉCAPITULATIF DES IPs POUR LE PROF

```
192.168.10.1   = VIP gateway LAN_CLIENT (fw-client MASTER keepalived)
10.10.0.2      = VIP WAN fw-client (endpoint IPsec côté client)
10.10.0.21     = IP physique fw-client (nœud primaire)
10.10.0.22     = IP physique fw-client-2 (nœud backup)

192.168.20.1   = VIP gateway LAN_SERVER (fw-server MASTER keepalived)
10.20.0.2      = VIP WAN fw-server (endpoint IPsec côté serveur)
10.20.0.21     = IP physique fw-server (nœud primaire)
10.20.0.22     = IP physique fw-server-2 (nœud backup)

200.0.0.10     = VIP Internet fw-isp (IP publique virtuelle)
10.10.0.1      = VIP WAN CLIENT fw-isp (gateway de fw-client)
10.20.0.1      = VIP WAN SERVER fw-isp (gateway de fw-server)
192.168.99.1   = VIP MGMT fw-isp (DNS + NTP + gateway management)

192.168.10.10  = client1 (utilisateur standard)
192.168.10.11  = client2 (utilisateur standard)
192.168.10.50  = kali (machine pentest)
192.168.20.10  = webserver nginx (serveur web interne)
192.168.20.11  = sshserver openssh (serveur SSH interne)
192.168.50.10  = dmz-web (serveur web exposé Internet)
192.168.99.50  = uptime-kuma (monitoring disponibilité)
192.168.99.70  = loki (stockage logs)
192.168.99.71  = promtail (collecte logs)
192.168.99.72  = grafana (dashboards)
192.168.20.60  = log-collector interface LAN_SERVER (reçoit logs serveurs)
192.168.99.60  = log-collector interface MGMT (reçoit logs firewalls)
```

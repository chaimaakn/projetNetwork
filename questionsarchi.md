# Architecture Réseau — Explication Technique Complète

---

## 1. LA HAUTE DISPONIBILITÉ (HA) — Actif/Passif avec VRRP

### Principe général

La HA signifie qu'il existe deux machines pour chaque rôle critique. Si l'une tombe, l'autre prend
le relais automatiquement sans interruption visible pour les utilisateurs.

Dans cette architecture, chaque firewall a un clone :
- fw-isp ↔ fw-isp-2
- fw-client ↔ fw-client-2
- fw-server ↔ fw-server-2

### Le protocole VRRP (Virtual Router Redundancy Protocol)

VRRP crée une **IP virtuelle (VIP)** partagée entre deux machines. Une seule machine la détient
à la fois : le **MASTER**. L'autre est en mode **BACKUP** et surveille.

```
fw-isp (MASTER, priorité 200)     fw-isp-2 (BACKUP, priorité 150)
       ↓                                    ↓
  détient VIP 200.0.0.10            surveille, prêt à prendre
  répond aux paquets                la VIP si le master tombe
       ↑___________heartbeat___________↑
           (toutes les 1 seconde)
```

Le MASTER envoie des messages VRRP (advertisements) toutes les secondes sur le réseau MGMT.
Si le BACKUP ne reçoit plus ces messages pendant 3 secondes (dead interval = 3 × 1s), il
déclare le master mort et prend la VIP.

### Flux actif/passif en détail — FW-ISP

**Situation normale :**
```
Internet → VIP 200.0.0.10 → fw-isp (MASTER) → traite le trafic
fw-isp-2 (BACKUP) → reçoit les heartbeats → ne fait rien
```

**Lors d'un failover :**
```
fw-isp tombe (crash, reboot, panne réseau)
fw-isp-2 attend 3 secondes sans heartbeat
fw-isp-2 passe MASTER → envoie un ARP gratuit pour annoncer
  "je suis maintenant 200.0.0.10"
Tous les switches/routeurs mettent à jour leur table ARP
Nouveau trafic → VIP 200.0.0.10 → fw-isp-2
```

**Quand fw-isp revient :**
```
fw-isp redémarre → priorité 200 > 150 → reprend le rôle MASTER
fw-isp-2 repasse BACKUP
```

### Synchronisation des sessions — conntrackd

**Problème sans conntrackd :**
Un utilisateur a une connexion SSH active vers le serveur. Le master fw-client tombe.
fw-client-2 prend la VIP mais ne connaît pas la session SSH → la connexion est coupée.

**Solution avec conntrackd :**
conntrackd réplique en temps réel la table des connexions actives (conntrack) entre le master
et le backup via le réseau MGMT.

```
fw-client (MASTER)
  Session TCP: 192.168.10.10:54321 → 192.168.20.11:22 ESTABLISHED
       ↓ réplication toutes les secondes
fw-client-2 (BACKUP)
  Connaît déjà: 192.168.10.10:54321 → 192.168.20.11:22 ESTABLISHED
```

Lors du failover, fw-client-2 connaît toutes les sessions → les connexions survivent au basculement.

### Scénarios de redondance

**Scénario 1 : Panne du FW-ISP primaire**
- Impact : coupure de 12-14 secondes (timer VRRP 3s + redémarrage HAProxy/DNS/NTP sur backup)
- Résolution : fw-isp-2 prend les 4 VIPs (200.0.0.10, 10.10.0.1, 10.20.0.1, 192.168.99.1)
- Internet, DNS, NTP, HAProxy reprennent sur fw-isp-2

**Scénario 2 : Panne du FW-CLIENT primaire**
- Impact : coupure 13 secondes (VRRP + redémarrage Squid + IPsec sur backup)
- Résolution : fw-client-2 prend VIP 10.10.0.2 et 192.168.10.1
- Le tunnel IPsec se rétablit depuis fw-client-2 vers fw-server
- Les sessions déjà établies survivent grâce à conntrackd

**Scénario 3 : Panne du FW-SERVER primaire**
- Résolution : fw-server-2 prend VIP 10.20.0.2 et 192.168.20.1
- IPsec se rétablit avec fw-server-2 comme endpoint
- Serveurs web et SSH restent accessibles

---

## 2. LE NAT — Adresses publiques vs privées

### Principe du NAT (Network Address Translation)

Les machines internes ont des adresses **privées** (non routables sur Internet).
Le NAT traduit ces adresses en adresse **publique** (routable) au moment de sortir.

```
Adresses privées (RFC 1918) :     Adresse publique :
192.168.x.x                       200.0.0.10 (simulé dans ce lab)
10.x.x.x
172.16.x.x à 172.31.x.x
```

### Où se passe le NAT dans cette architecture

**NAT sortant (MASQUERADE) — sur FW-ISP :**
```
client1 (192.168.10.10) veut accéder à example.com

192.168.10.10:54321 → example.com:80
        ↓ passe par fw-client (proxy Squid)
        ↓ passe par le tunnel IPsec
        ↓ arrive sur fw-isp
FW-ISP applique MASQUERADE :
200.0.0.10:12345 → example.com:80   ← adresse publique
        ↓
example.com répond à 200.0.0.10:12345
FW-ISP traduit en retour :
192.168.10.10:54321 ← la réponse revient au bon client
```

**NAT entrant (DNAT/forwarding) — pour la DMZ :**
```
Internet → 200.0.0.10:80
FW-ISP HAProxy redirige vers 192.168.50.10:80 (dmz-web)
```

---

## 3. LE RÉSEAU MANAGEMENT (MGMT) — À quoi ça sert vraiment ?

### Définition

Le réseau Management (192.168.99.0/24) est un réseau dit **"Out-of-Band" (OOB)**.
OOB signifie "en dehors du trafic normal" — c'est un réseau dédié uniquement à
l'administration et à la supervision, complètement séparé du trafic utilisateur.

### Ce qu'il contient et pourquoi

**1. Communication HA (heartbeats VRRP + conntrackd)**
Tous les échanges entre nœuds HA passent par MGMT :
```
fw-client (192.168.99.21) ←→ fw-client-2 (192.168.99.22)
  VRRP advertisements (UDP 112)
  conntrackd state sync (TCP)
```
Si ce trafic passait par le LAN normal, il consommerait de la bande passante utilisateur
et serait exposé à des perturbations.

**2. Réception centralisée des logs (syslog)**
Tous les firewalls envoient leurs logs vers 192.168.99.60 (Log Collector) via TCP/514.
Ces logs ne transitent pas par le réseau utilisateur → aucun risque d'interception.

**3. Outils de supervision (Grafana, Loki, Promtail, Uptime Kuma)**
Ces outils sont uniquement accessibles depuis MGMT.
Un attaquant qui compromet le LAN_USERS ou le LAN_SERVER ne peut pas accéder
aux dashboards de supervision → il ne peut pas effacer ses traces ni aveugler le SOC.

**4. Isolation totale**
MGMT est inaccessible depuis :
- LAN_USERS (192.168.10.0/24) → règle FORWARD DROP
- VOIP (192.168.30.0/24) → règle FORWARD DROP
- GUEST (192.168.40.0/24) → règle FORWARD DROP
- Internet (200.0.0.0/24) → pas de route publique

Seuls les firewalls et les outils de monitoring y ont accès → principe du moindre privilège.

---

## 4. POURQUOI LE VPN EST ENTRE LES FIREWALLS ET PAS ENTRE LES LANs

### Raison 1 — Les machines du LAN ne savent pas chiffrer

client1 (Alpine Linux) est une simple machine utilisateur. Elle n'a pas strongSwan installé,
ne connaît pas les clés IPsec, ne peut pas négocier IKEv2.

Si on voulait du VPN machine-à-machine, il faudrait installer et configurer strongSwan
sur CHAQUE poste utilisateur → ingérable en entreprise.

### Raison 2 — Transparence totale pour les utilisateurs

Avec le VPN entre firewalls, client1 envoie un paquet normal vers 192.168.20.10.
FW-CLIENT intercepte ce paquet, l'encapsule dans IPsec et l'envoie à FW-SERVER.
FW-SERVER désencapsule et livre à 192.168.20.10.

Pour client1, c'est transparent : il ne sait pas qu'il y a un VPN.

```
client1 → paquet normal → fw-client
fw-client → ESP(paquet chiffré) → fw-server  ← invisble pour client1
fw-server → paquet normal → webserver
```

### Raison 3 — Point de contrôle unique

En plaçant le VPN sur les firewalls, on a un seul point de contrôle pour :
- Les politiques de chiffrement (algorithmes, durée de vie des clés)
- La journalisation de tout le trafic inter-site
- Les règles ACL qui décident quels flux peuvent passer dans le tunnel

---

## 5. IKE — La négociation de quoi exactement ?

### Problème de départ

FW-CLIENT et FW-SERVER veulent communiquer de façon chiffrée. Mais pour chiffrer,
ils ont besoin d'une clé secrète. Comment se mettre d'accord sur cette clé sans
qu'un attaquant sur le WAN puisse la lire ?

### IKE (Internet Key Exchange) — Phase 1 : établissement du canal sécurisé

IKEv2 négocie d'abord un canal sécurisé pour s'échanger les paramètres en sécurité.

```
fw-client → fw-server : "Je veux IPsec. Voici mes propositions crypto :
                          AES-256, SHA-256, DH group 14 (MODP-2048)"
fw-server → fw-client : "OK, j'accepte AES-256/SHA-256/MODP-2048"

Échange Diffie-Hellman :
fw-client génère ga mod p → envoie à fw-server
fw-server génère gb mod p → envoie à fw-client
Les deux calculent gab mod p = clé secrète partagée
(un attaquant qui intercepte ga et gb ne peut pas calculer gab sans résoudre
le problème du logarithme discret → mathématiquement infaisable)

Authentification mutuelle :
fw-client prouve son identité avec la PSK (clé pré-partagée définie dans ipsec.secrets)
fw-server prouve son identité avec sa PSK
→ Canal IKE sécurisé établi (IKE_SA)
```

### IKE — Phase 2 : négociation du tunnel de données (IPsec SA)

```
Dans le canal IKE sécurisé :
fw-client → fw-server : "Je veux chiffrer les flux 192.168.10.0/24 ↔ 192.168.20.0/24
                          avec AES-256-CBC + SHA-256 + PFS DH14"
fw-server → fw-client : "OK"
Génération des clés de session ESP (Encapsulating Security Payload)
→ Tunnel IPsec établi (IPsec SA)
```

### En résumé, IKE négocie :
1. **Les algorithmes** (AES-256, SHA-256, DH group 14)
2. **Les identités** (authentification mutuelle par PSK ou certificats)
3. **Les clés de session** (via Diffie-Hellman)
4. **Les sélecteurs de trafic** (quels sous-réseaux passent dans le tunnel)
5. **La durée de vie des clés** (rekey toutes les 4h dans cette config)

---

## 6. POURQUOI LE LOG COLLECTOR EST DANS LE LAN SERVER

### Le problème technique

Les firewalls et serveurs doivent envoyer leurs logs quelque part via syslog (TCP/514).
Ce protocole fonctionne en mode push : la source envoie les logs vers une destination.

### Pourquoi pas uniquement dans MGMT ?

Si le Log Collector n'était que sur MGMT (192.168.99.0/24), les serveurs
(webserver 192.168.20.10, sshserver 192.168.20.11) devraient envoyer leurs logs
vers le réseau MGMT. Or les serveurs n'ont PAS d'interface MGMT — ils sont
uniquement dans LAN_SERVER.

### La solution dual-homed

Le Log Collector a deux interfaces réseau :

```
Log Collector
├── eth0 : 192.168.99.60 (réseau MGMT)
│   └── Reçoit les logs de : fw-isp, fw-client, fw-server (qui ont tous une interface MGMT)
└── eth1 : 192.168.20.60 (réseau LAN_SERVER)
    └── Reçoit les logs de : webserver (20.10), sshserver (20.11)
        qui n'ont PAS d'interface MGMT
```

Ainsi le Log Collector est accessible depuis les deux réseaux sans créer de route
entre LAN_SERVER et MGMT — l'isolation est préservée.

### Le problème rsyslog/watchdog sur sshserver

sshserver utilise systemd comme init system dans le container Debian.
Rsyslog dans ce contexte a un comportement particulier : il démarre mais n'active pas
le socket de reception UDP/TCP tant que systemd n'a pas confirmé que le service
est "healthy" via son mécanisme de watchdog (sd_notify).

Dans un container Docker sans systemd complet, ce handshake ne se fait jamais →
rsyslog attend indéfiniment → les logs ne sont jamais envoyés.

**La solution appliquée** : dans la config rsyslog de sshserver, on désactive le watchdog
systemd et on force le mode daemon classique :
```
$SystemLogSocketName /run/systemd/journal/syslog
$ModLoad imuxsock
```
Ou dans l'entrypoint.sh, on lance rsyslog avec `-n` (no daemon) directement
pour bypasser la dépendance systemd.

---

## 7. LOG COLLECTOR VS LOKI — Quelle différence ?

### Ce que fait rsyslog (Log Collector)

Rsyslog est un **collecteur de logs bruts**. Il reçoit des lignes de texte syslog
et les stocke dans des fichiers `/var/log/remote/`.

```
fw-client → "May 22 13:32:14 fw-client sshd[179]: Failed password for admin" → fichier texte
```

C'est un simple entonnoir : tout ce qui arrive est écrit dans un fichier. Rsyslog ne sait pas
analyser, chercher, filtrer, ni afficher quoi que ce soit.

### Ce que fait Loki

Loki est un **moteur de stockage et d'indexation de logs** optimisé pour les requêtes.
Il stocke les logs avec des labels (source, niveau, service) et permet de les requêter
avec le langage LogQL.

### La chaîne complète

```
Sources (firewalls, serveurs)
    ↓ TCP/514 syslog
Log Collector (rsyslog)
  stocke en fichiers /var/log/remote/*.log
    ↓ Promtail lit ces fichiers (tail -f)
Promtail
  ajoute des labels (job="fw-client", level="error")
  pousse vers Loki via HTTP
    ↓
Loki
  indexe par labels, stocke efficacement
  répond aux requêtes LogQL
    ↓ query
Grafana
  affiche les dashboards : top erreurs, timeline, alertes
```

**En résumé :**
- Rsyslog = boîte aux lettres (reçoit et stocke brut)
- Promtail = facteur (lit les fichiers et livre à Loki)
- Loki = bibliothèque indexée (stockage intelligent)
- Grafana = interface de lecture (visualisation)

Sans Loki, on ne pourrait que lire des fichiers texte bruts avec `grep` ou `tail`.
Avec Loki, on peut faire : "montre-moi tous les Failed password des 30 dernières minutes
depuis n'importe quelle source, triés par IP attaquante".

---

## 8. LE SEGMENT VOIP — À quoi ça sert vraiment ?

### Qu'est-ce que la VoIP ?

VoIP (Voice over IP) = téléphonie via réseau informatique. Les appels téléphoniques
sont transformés en paquets IP et transportés comme n'importe quelle donnée réseau.

Protocoles principaux :
- **SIP (UDP/5060)** — signalisation (établissement/fin d'appel)
- **RTP (UDP dynamique)** — transport de la voix (flux audio en temps réel)

### Pourquoi isoler la VoIP dans un VLAN séparé ?

**Raison 1 — Sécurité (écoute clandestine)**
Sans isolation, un attaquant sur LAN_USERS peut faire du ARP spoofing et capturer
les paquets RTP qui transitent sur le même segment L2.
RTP n'est pas chiffré par défaut → les conversations seraient enregistrables en clair.
Avec le VLAN_VOIP isolé, les paquets RTP ne traversent jamais LAN_USERS.

**Raison 2 — Qualité de service (QoS)**
La voix est sensible à la latence (>150ms = conversation difficile) et à la gigue (jitter).
Si un utilisateur télécharge un gros fichier sur LAN_USERS, cela peut saturer
la bande passante et dégrader les appels.
En isolant VOIP dans son propre segment, on peut appliquer des règles QoS
(priorité plus haute pour les paquets SIP/RTP) sans affecter le trafic utilisateur.

**Raison 3 — Segmentation des pannes**
Si LAN_USERS est compromis ou subit une attaque broadcast storm,
VOIP reste fonctionnel car isolé.

---

## 9. SÉCURITÉ EN 3 NIVEAUX — Périmètre, Interne, DMZ

### Pourquoi 3 niveaux ?

Le principe est celui de la **défense en profondeur** : même si un attaquant perce
une couche, il rencontre une nouvelle barrière. Il ne suffit pas de percer le périmètre
pour compromettre les données critiques.

### Niveau 1 — Périmètre (FW-ISP)

**Rôle** : filtrage entre Internet et les réseaux internes.
**Ce qu'il bloque** : tentatives de connexion directes vers LAN_SERVER,
scans de ports, protocoles dangereux (FTP en clair, Telnet...).
**Ce qu'il laisse passer** : uniquement HTTP/HTTPS vers la DMZ.

### Niveau 2 — Interne (FW-CLIENT + FW-SERVER)

**Rôle** : filtrage entre les différents segments internes.
**Ce qu'il bloque** : un utilisateur du LAN ne peut pas accéder directement
à LAN_SERVER sans passer par le tunnel IPsec et les ACLs de FW-SERVER.
**Ce qu'il laisse passer** : uniquement les flux autorisés par la matrice de flux.

### Niveau 3 — DMZ (gérée par FW-SERVER)

**Rôle** : zone tampon entre Internet et les serveurs internes.
Un serveur en DMZ peut être compromis sans que cela donne accès à LAN_SERVER.

---

## 10. LA DMZ — Flux, justification et le chemin du trafic

### Qu'est-ce que la DMZ (DeMilitarized Zone) ?

La DMZ est une zone réseau intermédiaire entre Internet et le réseau interne.
Elle héberge des services accessibles depuis Internet (web public, API publique...)
sans exposer le réseau interne.

### Pourquoi le trafic passe par FW-ISP → FW-SERVER → DMZ ?

**Question légitime** : si la DMZ est une zone "entre Internet et l'interne",
pourquoi le trafic passe-t-il par FW-SERVER (le firewall interne) pour y accéder ?

**Réponse** : dans cette architecture, la topologie est dictée par les contraintes Docker.
Docker ne supporte pas nativement plusieurs interfaces physiques avec VLAN 802.1Q.
La DMZ est donc un réseau bridge distinct, mais rattaché à FW-SERVER car c'est
lui qui contrôle les serveurs côté server.

**Le flux réel :**
```
Internet (200.0.0.50)
    ↓ HTTP port 80
FW-ISP (200.0.0.10) — HAProxy
HAProxy a une règle : "tout ce qui arrive sur port 80/443 → forward vers 192.168.50.10"
    ↓ forward HTTP vers 192.168.50.10
FW-SERVER reçoit ce paquet (il est sur wan_server_net avec FW-ISP)
FW-SERVER vérifie ses ACLs : "flux vers 192.168.50.10:80 autorisé ?"
    ↓ OUI → forward vers dmz-web
dmz-web (192.168.50.10) répond
    ↑ retour par le même chemin
```

**Pourquoi pas de lien direct entre DMZ et LAN_SERVER ?**
C'est précisément le but de la DMZ : dmz-web (192.168.50.10) ne peut pas
atteindre webserver (192.168.20.10) ou sshserver (192.168.20.11).
FW-SERVER applique des règles FORWARD qui bloquent DMZ → LAN_SERVER.

**Ce qui protège** : si un attaquant compromet dmz-web, il est bloqué par FW-SERVER
dès qu'il essaie d'atteindre LAN_SERVER. Il reste coincé dans la DMZ.

**Pourquoi le trafic interne ne passe pas par la DMZ ?**
Le trafic interne (client1 → webserver) passe par le tunnel IPsec directement :
LAN_CLIENT → FW-CLIENT → IPsec → FW-SERVER → LAN_SERVER.
La DMZ n'est pas sur ce chemin — c'est correct. La DMZ est uniquement
pour les services exposés à Internet, pas pour le trafic interne.

---

## 11. LES FIREWALLS — C'est quoi comme machine ?

### Debian 12-slim comme base

```dockerfile
FROM debian:12-slim
```

`debian:12-slim` est une image Docker minimaliste basée sur Debian 12 (Bookworm).
"slim" signifie qu'elle ne contient que le strict minimum (pas de man pages,
pas d'éditeurs, pas d'utilitaires non essentiels) — environ 75 Mo au lieu de 120 Mo.

### Ce qui en fait un firewall

Ce n'est pas Debian qui fait le firewall — ce sont les outils installés par-dessus :

```
Debian 12-slim (OS de base)
├── iptables / ipset → moteur de filtrage (= FortiOS / pfSense rules engine)
├── ip route, ip rule → routage avancé multi-chemin
├── strongSwan → daemon IPsec IKEv2 (= VPN IPsec FortiGate)
├── keepalived → daemon VRRP (= HA FortiGate / pfSense CARP)
├── conntrackd → synchronisation des sessions (= session sync FortiGate)
├── Squid → proxy web (= Web Filter FortiGate)
├── Suricata → IDS/IPS (= IPS FortiGate)
├── dnsmasq → DNS + DHCP (= DNS Resolver pfSense)
├── haproxy → load balancer (= HAProxy package pfSense)
└── rsyslog → envoi des logs (= log forwarding)
```

Le container a les capabilities `NET_ADMIN` et `SYS_MODULE` activées, ce qui lui
permet de modifier les règles iptables, les routes et les paramètres kernel (ip_forward=1).
C'est ce qui le différencie d'un container applicatif classique.

**En résumé** : c'est un Linux ordinaire transformé en appliance réseau par les outils
installés et les capabilities Docker — exactement comme pfSense est un FreeBSD
transformé en appliance, ou FortiOS est un Linux modifié par Fortinet.

---

## 12. SONDES UPTIME KUMA — Configuration complète

### Ce qui est configuré selon le rapport Phase 3

Les 10 sondes actives surveillent :

| # | Nom | Type | Cible |
|---|-----|------|-------|
| 1 | FW_ISP - DNS | DNS | web.labcyber.local → resolver 192.168.99.11 |
| 2 | FW_ISP - NTP | Ping | 192.168.99.11 |
| 3 | FW_ISP - HAProxy | HTTP | http://192.168.99.11 |
| 4 | FW_CLIENT - Mgmt | Ping | 192.168.99.10 (VIP) |
| 5 | FW_SERVER - Mgmt | Ping | 192.168.99.20 (VIP) |
| 6 | HA - FW_ISP backup | Ping | 192.168.99.12 |
| 7 | HA - FW_CLIENT backup | Ping | 192.168.99.22 |
| 8 | HA - FW_SERVER backup | Ping | 192.168.99.32 |
| 9 | SSHServer - SSH | TCP port | 192.168.20.11:22 |
| 10 | Webserver - HTTP | HTTP | http://192.168.20.10 |

Uptime Kuma est sur MGMT (192.168.99.50) et peut donc atteindre toutes ces cibles
via le réseau MGMT pour les firewalls, et via le routage MGMT → LAN_SERVER
pour les serveurs.

---

## 13. RÉCAPITULATIF DES FLUX PAR USAGE

### Flux 1 : Utilisateur interne → Serveur interne
```
client1 (192.168.10.10)
  → Squid proxy (192.168.10.1:3128) sur fw-client
  → Suricata inspecte
  → Tunnel IPsec ESP (10.10.0.2 → 10.20.0.2 via FW-ISP WAN)
  → FW-SERVER déchiffre, ACL → ACCEPT
  → webserver (192.168.20.10) ou sshserver (192.168.20.11)
```

### Flux 2 : Utilisateur interne → Internet
```
client1 (192.168.10.10)
  → Squid proxy sur fw-client (filtre URLs)
  → FW-CLIENT → FW-ISP (WAN CLIENT 10.10.0.0/24)
  → FW-ISP NAT MASQUERADE (200.0.0.10 → destination)
  → Internet
```

### Flux 3 : Internet → DMZ
```
Navigateur externe → 200.0.0.10:80
  → FW-ISP HAProxy (forward vers 192.168.50.10:80)
  → Routage via WAN_SERVER (10.20.0.0/24)
  → FW-SERVER ACL → ACCEPT vers DMZ
  → dmz-web (192.168.50.10)
  ✗ LAN_SERVER (192.168.20.x) bloqué par FW-SERVER ACL
```

### Flux 4 : Logs
```
fw-client/fw-server/fw-isp
  → Syslog TCP/514 → Log Collector (192.168.99.60)
webserver/sshserver
  → Syslog TCP/514 → Log Collector (192.168.20.60)
Log Collector (fichiers /var/log/remote/)
  → Promtail scrape → Loki (192.168.99.70)
  → Grafana query → dashboards SOC
```

### Flux 5 : HA heartbeats
```
fw-client (192.168.99.21) ←→ fw-client-2 (192.168.99.22)
  VRRP UDP/112 toutes les secondes
  conntrackd TCP sync sessions actives
  (tout via réseau MGMT uniquement)
```

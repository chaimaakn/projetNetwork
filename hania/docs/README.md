# 🛡️ Lab Cybersécurité Docker — Mini-Projet 4ème SSI

> **Adaptation Docker** du mini-projet « Sécurité des Réseaux et Infrastructures » (60 jours), conçue pour fonctionner sur une machine à ressources limitées (laptop ~8 Go RAM).

## 🎯 Objectif de cette adaptation

Reproduire le **socle pédagogique principal** du lab pfSense + 2× FortiGate + Kali, mais en utilisant uniquement **Docker** et des conteneurs Linux légers. Le périmètre validé couvre la segmentation réseau, le routage, le NAT, le DNS/NTP, le VPN IPsec, le DHCP, le proxy Squid, HAProxy, le monitoring, le hardening avance de Phase 2 et la base des démonstrations de pentest.

| Composant original | Remplacement Docker | Fonction |
|---|---|---|
| **pfSense** | `fw-isp` (Debian + iptables + dnsmasq + chrony + HAProxy) | Firewall ISP, DNS, NTP, load balancer |
| **FortiGate FW_CLIENT** | `fw-client` (Debian + iptables + strongSwan + dnsmasq + squid) | FW client, VPN IPsec, DHCP, filtrage web |
| **FortiGate FW_SERVER** | `fw-server` (Debian + iptables + strongSwan + chrony) | FW serveur, VPN IPsec, NTP |
| **VPN IPsec IKEv2** | strongSwan (AES-256, SHA-256, modp2048) | Équivalent pédagogique |
| **Kali Linux** | Image officielle `kalilinux/kali-rolling` | Identique |
| **Uptime Kuma** | Image officielle `louislam/uptime-kuma` | Identique |
| **VLANs (Phase 2)** | Réseaux Docker `bridge` séparés | `lan_client`, `vlan_voip`, `vlan_guest`, `lan_server`, `dmz`, `mgmt` déployés |

## ✅ Statut validé aujourd'hui

- Fonctionnel et vérifié : `fw-isp`, `fw-client`, `fw-server`, `client1`, `client2`, `voip1`, `guest1`, `kali`, `webserver`, `sshserver`, `dmz-web`, `internet-probe`, `uptime-kuma`
- Vérifié : routage entre zones, NAT Internet, DNS/NTP, IPsec, HTTP via VPN, SSH vers `sshserver`, HTTP DMZ, publication web via HAProxy, proxy Squid, monitoring et tests automatisés
- Les scripts actifs résolvent les interfaces dynamiquement a partir des IPs statiques du compose ; l'ordre `ethX` n'est plus une hypothèse de fonctionnement
- La segmentation Phase 2 coeur est integree : VLAN VOIP, VLAN GUEST, DMZ et matrice de flux testee
- Le hardening avance Phase 2 est livre : objets et groupes `ipset` sur `fw-client`, liste `blocked_domains.txt` versionnee pour Squid, garde-fous egress sur `fw-isp`
- Le jeu de validation couvre maintenant `test-connectivity.sh`, `test-vlan-matrix.sh`, `test-policy-hardening.sh` et `test-full-lab.sh`
- Les documents `PHASE2.md` et `PHASE3.md` servent maintenant de support pour les extensions suivantes et la campagne de validation offensive
- Evolutions possibles : `keepalived` / VRRP / CARP, `Wazuh`, `Suricata` et les blocs HA / IDS / SIEM restants de la roadmap

## 🗺️ Architecture déployée

```
                         ┌──────────────────────┐
                         │   Internet simulé    │
                         │   (200.0.0.0/24)     │
                         └──────────┬───────────┘
                                    │
                         ┌──────────▼───────────┐
                         │       FW_ISP         │
                         │   (pfSense-like)     │
                         │  200.0.0.10 / WAN    │
                         │  10.10.0.1  / cli    │
                         │  10.20.0.1  / srv    │
                         │  192.168.99.1 / mgmt │
                         └─────┬──────────┬─────┘
              10.10.0.0/24     │          │   10.20.0.0/24
                  ┌────────────┘          └────────────┐
                  │                                    │
        ┌─────────▼───────────┐              ┌─────────▼───────────┐
        │      FW_CLIENT      │◄═══ VPN ═══►│      FW_SERVER      │
        │  10.10.0.2   /WAN   │   IPsec     │  10.20.0.2   /WAN   │
        │ 192.168.10.1 /LAN   │   IKEv2     │ 192.168.20.1 /LAN   │
        │192.168.99.10 /mgmt  │             │192.168.99.20 /mgmt  │
        └─────────┬───────────┘              └─────────┬───────────┘
                  │                                    │
         ┌────────▼────────┐                ┌──────────▼──────────┐
         │   LAN_CLIENT    │                │     LAN_SERVER      │
         │ 192.168.10.0/24 │                │  192.168.20.0/24    │
         ├─────────────────┤                ├─────────────────────┤
         │ client1   .10   │                │ webserver  .10      │
         │ client2   .11   │                │ sshserver  .11      │
         │ kali      .50   │                │                     │
         └─────────────────┘                └─────────────────────┘
```

## 🚀 Démarrage rapide

### Pré-requis
- **Docker Engine ≥ 24.0**
- **Docker Compose v2** (`docker compose` et non `docker-compose`)
- **Linux** recommandé (Windows/Mac OK avec WSL2 / Docker Desktop)
- **4 Go RAM minimum**, 8 Go conseillé
- ~10 Go d'espace disque

### Vérification
```bash
docker --version           # Docker version 24+ 
docker compose version     # Compose v2.x
```

### Construction et lancement
```bash
cd hania/

# 1) Construire toutes les images (~10-15 min la 1ère fois)
docker compose build

# 2) Démarrer le lab
docker compose up -d

# 3) Vérifier que tout est UP
docker compose ps

# 4) Lancer les tests de validation
chmod +x scripts/test-connectivity.sh
chmod +x scripts/test-vlan-matrix.sh
chmod +x scripts/test-policy-hardening.sh
chmod +x scripts/test-full-lab.sh

# Smoke test
bash ./scripts/test-connectivity.sh

# Validation Phase 2
bash ./scripts/test-vlan-matrix.sh

# Validation du hardening avance
bash ./scripts/test-policy-hardening.sh

# Validation complete
bash ./scripts/test-full-lab.sh
```

### Accès aux conteneurs
```bash
# Shell sur les firewalls
docker exec -it fw-isp    bash
docker exec -it fw-client bash
docker exec -it fw-server bash

# Shell sur les postes
docker exec -it client1   bash
docker exec -it guest1    bash
docker exec -it voip1     bash
docker exec -it webserver bash
docker exec -it dmz-web   bash
docker exec -it internet-probe bash
docker exec -it kali      bash    # Pour la phase 3

# Logs en direct
docker compose logs -f fw-client
```

### Interface Uptime Kuma
- Ouvrir : http://localhost:3001
- Créer un compte au premier accès

## 📚 Documentation des Phases

| Document | Description |
|---|---|
| [`docs/PHASE1.md`](docs/PHASE1.md) | Jours 1-15 — Consolidation, audit et validation du socle actuel |
| [`docs/PHASE2.md`](docs/PHASE2.md) | Jours 16-30 — Extensions VLAN, ACLs avancées, filtrage web, HA |
| [`docs/PHASE3.md`](docs/PHASE3.md) | Jours 31-45 — Campagne de pentest et remédiation |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Dépannage des problèmes courants |
| [`docs/EQUIVALENCES.md`](docs/EQUIVALENCES.md) | Tableau de correspondance pfSense/FortiGate ↔ Docker |

## 🔐 Notes de sécurité importantes

1. **Ce lab est volontairement vulnérable** sur certains points (mots de passe SSH faibles, services exposés) pour permettre la Phase 3 (pentest). **Ne jamais exposer ces conteneurs sur Internet**.
2. Les conteneurs firewall tournent en `privileged: true` à cause des contraintes IPsec/iptables. C'est acceptable en lab mais **inacceptable en production**.
3. Le PSK IPsec présent dans le code doit être changé avant tout usage non-pédagogique.

## 🧹 Arrêt et nettoyage

```bash
# Arrêter le lab (préserve les données)
docker compose down

# Tout effacer (volumes inclus)
docker compose down -v

# Supprimer aussi les images
docker compose down -v --rmi all
```

## ⚠️ Limitations connues vs. lab original

| Point | Original | Docker | Impact |
|---|---|---|---|
| **HA pfSense (CARP)** | Possible | Extension optionnelle | Reste la grande brique Phase 2 non livree |
| **HA FortiGate** | Cluster complet | Extension optionnelle | Reste la grande brique Phase 2 non livree |
| **Inspection SSL/TLS profonde** | FortiGate native | Extension optionnelle | Squid SslBump demanderait une integration dediee |
| **Inspection paquet niveau ASIC** | FortiGate | Logiciel uniquement | Un IDS type Suricata peut enrichir le socle |
| **SIEM / corrélation** | Plateforme dédiée | Extension optionnelle | `Wazuh` reste la grande brique naturelle de Phase 4 |
| **Interface graphique** | GUI native | CLI + Uptime Kuma | Pédagogique différent mais formateur |

---

**Auteur original du sujet** : Dr. K. Zeraoulia — 4ème SSI 60J  
**Adaptation Docker** : générée pour environnement à ressources limitées
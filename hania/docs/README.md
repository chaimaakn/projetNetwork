# 🛡️ Lab Cybersécurité Docker — Mini-Projet 4ème SSI

> **Adaptation Docker** du mini-projet « Sécurité des Réseaux et Infrastructures » (60 jours), conçue pour fonctionner sur une machine à ressources limitées (laptop ~8 Go RAM).

## 🎯 Objectif de cette adaptation

Reproduire **fidèlement** le comportement pédagogique du lab pfSense + 2× FortiGate + Kali, mais en utilisant uniquement **Docker** et des conteneurs Linux légers. Toutes les **fonctionnalités** sont préservées :

| Composant original | Remplacement Docker | Fonction |
|---|---|---|
| **pfSense** | `fw-isp` (Debian + iptables + dnsmasq + chrony + HAProxy) | Firewall ISP, DNS, NTP, load balancer |
| **FortiGate FW_CLIENT** | `fw-client` (Debian + iptables + strongSwan + dnsmasq + squid) | FW client, VPN IPsec, DHCP, filtrage web |
| **FortiGate FW_SERVER** | `fw-server` (Debian + iptables + strongSwan + chrony) | FW serveur, VPN IPsec, NTP |
| **VPN IPsec IKEv2** | strongSwan (AES-256, SHA-256, PFS modp2048) | Identique |
| **Kali Linux** | Image officielle `kalilinux/kali-rolling` | Identique |
| **Uptime Kuma** | Image officielle `louislam/uptime-kuma` | Identique |
| **VLANs (Phase 2)** | Réseaux Docker `bridge` séparés | Isolation L2/L3 équivalente |

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
cd docker-cyber-lab/

# 1) Construire toutes les images (~10-15 min la 1ère fois)
docker compose build

# 2) Démarrer le lab
docker compose up -d

# 3) Vérifier que tout est UP
docker compose ps

# 4) Lancer les tests de validation (Phase 1)
chmod +x scripts/test-connectivity.sh
./scripts/test-connectivity.sh
```

### Accès aux conteneurs
```bash
# Shell sur les firewalls
docker exec -it fw-isp    bash
docker exec -it fw-client bash
docker exec -it fw-server bash

# Shell sur les postes
docker exec -it client1   bash
docker exec -it webserver bash
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
| [`docs/PHASE1.md`](docs/PHASE1.md) | Jours 1-15 — Consolidation & Documentation |
| [`docs/PHASE2.md`](docs/PHASE2.md) | Jours 16-30 — Segmentation VLAN, ACLs, filtrage web, HA |
| [`docs/PHASE3.md`](docs/PHASE3.md) | Jours 31-45 — Pentest complet & remédiation |
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
| **HA pfSense (CARP)** | Possible | Limité (pas de VRRP natif facile en Docker) | Phase 2 J27 : démonstration via 2 conteneurs avec keepalived |
| **HA FortiGate** | Cluster complet | Approche par 2 conteneurs + load balancer DNS | Phase 2 J28 |
| **Inspection SSL/TLS profonde** | FortiGate native | Squid SslBump (plus complexe à configurer) | Phase 2 J24 : version simplifiée |
| **Inspection paquet niveau ASIC** | FortiGate | Logiciel uniquement (Suricata) | Performance plus faible (peu impactant en lab) |
| **Interface graphique** | GUI native | CLI + Uptime Kuma | Pédagogique différent mais formateur |

---

**Auteur original du sujet** : Dr. K. Zeraoulia — 4ème SSI 60J  
**Adaptation Docker** : générée pour environnement à ressources limitées
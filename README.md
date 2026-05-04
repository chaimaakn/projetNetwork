# SSI-Lab — Infrastructure Sécurité Réseau
**4ème Année Ingénieure Sécurité | ContainerLab sur Kali Linux**

## Architecture

```
LAN-CLIENT (192.168.10.0/24)          LAN-SERVER (192.168.20.0/24)
┌─────────────────────┐               ┌──────────────────────────┐
│ pc-client           │               │ serveur-web              │
│ 192.168.10.10       │               │ 192.168.20.10 (nginx)    │
│                     │               │                          │
│ kali (pentest)      │               │ wazuh (SIEM)             │
│ 192.168.10.20       │               │ 192.168.20.20            │
└────────┬────────────┘               └───────────┬──────────────┘
         │                                        │
    fw-client (FRR)                          fw-server (FRR)
    eth1: 10.0.1.2                           eth1: 10.0.2.2
    br-client: 192.168.10.1                  br-server: 192.168.20.1
         │                                        │
         └──────────── fw-isp (FRR) ──────────────┘
                       eth1: 10.0.1.1
                       eth2: 10.0.2.1
```

## Prérequis

- Kali Linux (VM ou natif)
- Docker installé
- ContainerLab installé

## Installation

### 1. Installer Docker
```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable docker --now
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Installer ContainerLab
```bash
bash -c "$(curl -sL https://get.containerlab.dev)"
```

### 3. Cloner / copier le projet
```bash
mkdir ~/clab-projet
cd ~/clab-projet
# Copier topology.clab.yml et init-config.sh ici
chmod +x init-config.sh
```

## Utilisation

### Démarrer le lab
```bash
cd ~/clab-projet
sudo containerlab deploy -t topology.clab.yml
./init-config.sh
```

### Arrêter le lab
```bash
sudo containerlab destroy -t topology.clab.yml
```

### Redémarrer après reboot
```bash
cd ~/clab-projet
sudo containerlab deploy -t topology.clab.yml
./init-config.sh
```

> Les configs IP ne persistent pas — toujours relancer init-config.sh après deploy.

## Plan d'adressage

| Node         | Interface  | IP               | Rôle                  |
|--------------|------------|------------------|-----------------------|
| fw-isp       | eth1       | 10.0.1.1/30      | WAN vers fw-client    |
| fw-isp       | eth2       | 10.0.2.1/30      | WAN vers fw-server    |
| fw-client    | eth1       | 10.0.1.2/30      | WAN vers fw-isp       |
| fw-client    | br-client  | 192.168.10.1/24  | Gateway LAN-CLIENT    |
| fw-server    | eth1       | 10.0.2.2/30      | WAN vers fw-isp       |
| fw-server    | br-server  | 192.168.20.1/24  | Gateway LAN-SERVER    |
| pc-client    | eth1       | 192.168.10.10/24 | Machine utilisateur   |
| kali         | eth1       | 192.168.10.20/24 | Machine pentest       |
| serveur-web  | eth1       | 192.168.20.10/24 | Serveur nginx         |
| wazuh        | eth1       | 192.168.20.20/24 | SIEM (Phase 4)        |

## Règles de sécurité appliquées (Phase 1)

- `fw-client` et `fw-server` : politique FORWARD = **DROP** par défaut
- Seul `pc-client` (192.168.10.10) peut accéder au LAN-SERVER
- `kali` (192.168.10.20) est **bloqué** vers LAN-SERVER par défaut
- NAT activé sur fw-isp et fw-client pour l'accès Internet

## Tests de connectivité

```bash
# pc-client -> serveur-web (doit marcher)
docker exec clab-ssi-lab-pc-client ping -c 3 192.168.20.10

# pc-client -> wazuh (doit marcher)
docker exec clab-ssi-lab-pc-client ping -c 3 192.168.20.20

# kali -> serveur-web (doit être BLOQUÉ)
KALI_PID=$(docker inspect -f '{{.State.Pid}}' clab-ssi-lab-kali)
sudo nsenter -t $KALI_PID -n -- ping -c 3 192.168.20.10

# Audit Nmap depuis kali
sudo nsenter -t $KALI_PID -n -- nmap -sV 192.168.20.0/24
```

## Phases du projet

| Phase | Jours  | Contenu                              | Statut |
|-------|--------|--------------------------------------|--------|
| 1     | J1-J15 | Déploiement, audit, hardening de base| ✅ Done |
| 2     | J16-J30| VLANs, ACLs avancées, segmentation   | 🔄 Todo |
| 3     | J31-J45| Pentest complet, rapport d'audit     | 🔄 Todo |
| 4     | J46-J60| SOC, SIEM Wazuh, Haute Disponibilité | 🔄 Todo |

## Outils utilisés

| Outil        | Usage                        | Image Docker              |
|--------------|------------------------------|---------------------------|
| FRRouting    | Firewall / Routeur (x3)      | frrouting/frr:latest      |
| Alpine       | PC Client                    | alpine:3.18               |
| Kali Linux   | Pentest                      | kalilinux/kali-rolling    |
| Nginx        | Serveur Web                  | nginx:alpine              |
| Wazuh        | SIEM (Phase 4)               | wazuh/wazuh-manager:4.7.0 |

## Auteurs
Projet pédagogique — Sécurité des Réseaux | Dr. K. Zeraoulia

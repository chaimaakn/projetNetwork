# projetNetwork

Ce dépôt contient aujourd'hui deux pistes techniques distinctes :

- `hania/` : l'implémentation Docker réellement maintenue et validée.
- `topology.clab.yml`, `topology2.clab.yml`, `init-config2.sh` : traces de travail ContainerLab conservées à titre de référence, mais non alignées avec l'état final validé du lab.

## État actuel du lab Docker

Le périmètre opérationnel dans `hania/` couvre :

- segmentation WAN / LAN / management et Phase 2 coeur (`vlan_voip_net`, `vlan_guest_net`, `dmz_net`) via réseaux Docker `bridge`
- firewalls Linux `iptables` avec ACLs objet via `ipset`
- VPN site-à-site IPsec `strongSwan`
- DNS et NTP centralisés sur `fw-isp`
- DHCP côté client, proxy Squid, IDS Suricata et publication HTTP via HAProxy
- durcissement avancé Phase 2 : liste de domaines Squid versionnée et garde-fous egress sur `fw-isp`
- haute disponibilité Phase 2 : paire pfSense-like `fw-isp` / `fw-isp-2` avec `keepalived`, paires FortiGate-like `fw-client` / `fw-client-2` et `fw-server` / `fw-server-2` avec `keepalived` + `conntrackd`
- monitoring léger avec Uptime Kuma
- poste d'attaque Kali et scripts de validation (`test-connectivity.sh`, `test-vlan-matrix.sh`, `test-policy-hardening.sh`, `test-suricata.sh`, `test-ha.sh`, `test-full-lab.sh`)

Extensions possibles à partir de ce socle :

- SOC / SIEM `Wazuh`
- scénarios avancés de Phase 2/4 décrits dans les documents de roadmap

## Démarrage rapide

```bash
cd hania

docker compose build
docker compose up -d
docker compose ps

# Smoke test
bash ./scripts/test-connectivity.sh

# Validation Phase 2
bash ./scripts/test-vlan-matrix.sh

# Validation du hardening avance
bash ./scripts/test-policy-hardening.sh

# Validation IDS / Suricata
bash ./scripts/test-suricata.sh

# Validation HA
bash ./scripts/test-ha.sh

# Validation complete
bash ./scripts/test-full-lab.sh
```

## Vérifications recommandées avant commit

```bash
docker compose ps
bash ./scripts/test-vlan-matrix.sh
bash ./scripts/test-policy-hardening.sh
bash ./scripts/test-suricata.sh
bash ./scripts/test-ha.sh
bash ./scripts/test-full-lab.sh
docker exec fw-client ipsec statusall
docker exec client1 curl -s http://192.168.20.10
docker exec client1 curl -s http://192.168.50.10
docker exec client1 nc -zv 192.168.20.11 22
```

## Documentation utile

- vue d'ensemble : `hania/docs/README.md`
- dépannage : `hania/docs/TROUBLESHOOTING.md`
- équivalences pédagogiques : `hania/docs/EQUIVALENCES.md`
- roadmaps / supports : `hania/docs/PHASE1.md`, `hania/docs/PHASE2.md`, `hania/docs/PHASE3.md`

## Environnement conseillé

- Docker Engine / Docker Desktop récent
- `docker compose` v2
- Linux natif ou Windows avec WSL2 / Docker Desktop

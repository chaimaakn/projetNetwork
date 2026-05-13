# 🎓 Soutenance Finale — Trame de Démonstration

> **But** : dérouler une soutenance claire, courte et défendable, en montrant uniquement des preuves déjà versionnées et validées dans le dépôt.

## Format conseillé

- **Durée totale** : 15 à 20 minutes
- **Structure** : 5 minutes architecture, 8 minutes démonstration, 5 minutes sécurité / choix techniques, 2 minutes conclusion
- **Règle** : toujours relier une fonctionnalité à une preuve concrète (`docker compose ps`, script de test, dashboard, log, capture d'écran)

## Déroulé recommandé

### 1. Contexte et architecture

À montrer :
- segmentation WAN / LAN / VLAN / DMZ / management
- rôle des trois couples firewall : `fw-isp*`, `fw-client*`, `fw-server*`
- rôle des hôtes métier : `webserver`, `sshserver`, `dmz-web`, `client1`, `kali`
- logique d'équivalence avec pfSense / FortiGate via `iptables`, `strongSwan`, `keepalived`, `conntrackd`

Appui documentaire :
- `README.md`
- `docs/README.md`
- `docs/EQUIVALENCES.md`

### 2. Validation du socle

Commandes utiles :

```bash
cd hania

docker compose ps
bash ./scripts/test-connectivity.sh
bash ./scripts/test-vlan-matrix.sh
bash ./scripts/test-policy-hardening.sh
```

Message à porter :
- le lab n'est pas une maquette figée ; il est validé par scripts
- la segmentation et les règles de flux sont démontrées, pas seulement décrites

### 3. Haute disponibilité

Commandes utiles :

```bash
bash ./scripts/test-ha.sh
```

Points à verbaliser :
- `keepalived` maintient les VIPs historiques
- `conntrackd` réplique les états côté FortiGate-like
- la publication publique et le tunnel VPN survivent aux bascules

Preuves à montrer :
- sortie du script HA
- accès public HAProxy maintenu
- reprise du tunnel IPsec après bascule

### 4. Phase 3 — Pentest et remédiation

Commandes utiles :

```bash
bash ./scripts/test-phase3-hardening.sh
```

Points à verbaliser :
- la surface SSH a été réduite au strict nécessaire
- `sshserver` est livré durci (`PermitRootLogin no`, `PasswordAuthentication no`, `fail2ban`)
- `webserver` et `dmz-web` n'exposent plus SSH
- les scénarios offensifs restent documentés mais ne correspondent plus à l'état par défaut du dépôt

Appui documentaire :
- `docs/PHASE3.md`
- `scripts/test-pentest.sh`

### 5. Phase 4 — SOC / SIEM

Commandes utiles :

```bash
bash ./scripts/test-log-centralization.sh
bash ./scripts/test-siem-phase4.sh
curl -fsS -u admin:labcyber-admin http://127.0.0.1:3002/api/search?query=LabCyber
curl -fsS http://127.0.0.1:3110/prometheus/api/v1/rules
```

Interfaces à ouvrir :
- `Uptime Kuma` : http://localhost:3001
- `Grafana` : http://localhost:3002

Ce qu'il faut montrer :
- remontée centralisée des logs vers `log-collector`
- ingestion SIEM via `Promtail`
- dashboards `LabCyber SOC Overview` et `LabCyber HA & VPN`
- règles chargées :
  - `SSHAuthenticationFailuresBurst`
  - `KeepalivedMasterTransitionObserved`
  - `FirewallKernelDropsObserved`
  - `SuricataLabAlertObserved`

### 6. Clôture par la régression complète

Commande finale :

```bash
bash ./scripts/test-full-lab.sh
```

Message à porter :
- le projet final est industrialisé à l'échelle du lab
- les phases ne sont pas des livrables isolés ; elles sont rejouées ensemble sans régression

## Questions probables du jury

### Pourquoi Docker et pas les appliances d'origine ?

Réponse courte :
- pour rendre le sujet exécutable sur un laptop limité
- pour conserver les concepts réseau / sécurité sans dépendre d'hyperviseurs lourds
- pour versionner toute l'infrastructure et les validations

### Pourquoi `keepalived` et `conntrackd` ?

Réponse courte :
- `keepalived` apporte l'équivalent pédagogique des VIPs / VRRP
- `conntrackd` couvre la synchro d'état L3/L4, suffisante pour le périmètre du lab
- on ne prétend pas reproduire FGCP ou CARP à l'identique

### Pourquoi `Loki + Promtail + Grafana` ?

Réponse courte :
- stack plus légère qu'un SIEM full-size pour un projet étudiant
- suffisante pour centraliser, requêter, corréler et montrer des dashboards
- base saine pour monter ensuite vers `Wazuh` ou `OpenSearch`

## Check-list avant passage

- `docker compose ps` est propre
- `bash ./scripts/test-full-lab.sh` est vert
- Grafana est accessible sur `localhost:3002`
- Uptime Kuma est accessible sur `localhost:3001`
- les dashboards Grafana s'affichent
- les règles Loki répondent sur l'API
- vous savez expliquer 3 choix techniques et 3 limites assumées

## Pièces à joindre au rendu

- `README.md`
- `hania/docs/README.md`
- `hania/docs/PHASE1.md`
- `hania/docs/PHASE2.md`
- `hania/docs/PHASE3.md`
- `hania/docs/PHASE4.md`
- `hania/docs/SOUTENANCE.md`
- `.github/workflows/lab-regression.yml`

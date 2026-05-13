# 📘 PHASE 4 — SOC, SIEM & Haute Disponibilité

> **Objectif** : livrer une brique SOC exploitable dans le lab final, avec centralisation des logs, backend SIEM léger, règles de détection, dashboards de supervision et validation automatique sans régression sur la HA.

> **Positionnement** : le dépôt livre maintenant une **phase 4 complète en mode SIEM léger**. Le choix d'implémentation privilégie une chaîne moderne et raisonnable pour un laptop de projet : `rsyslog` pour la collecte, `Loki` pour l'indexation orientée logs, `Promtail` pour l'ingestion de fichiers et `Grafana` pour les dashboards.

## ✅ Statut courant

- `log-collector` écoute en TCP/UDP 514 sur `mgmt_net` et `lan_server_net`
- `fw-isp`, `fw-isp-2`, `fw-client`, `fw-client-2`, `fw-server`, `fw-server-2` et `sshserver` forwardent leurs journaux via `rsyslog`
- `Promtail` ingère les journaux centralisés et les alertes `Suricata` depuis les fichiers du dépôt
- `Loki` expose le backend de requête et charge des règles d'alerte versionnées
- `Grafana` provisionne la datasource `LabCyber Loki` et deux dashboards : `LabCyber SOC Overview` et `LabCyber HA & VPN`
- la validation automatisée est couverte par `scripts/test-log-centralization.sh`, `scripts/test-siem-phase4.sh` puis `scripts/test-full-lab.sh`

## 🏗️ Architecture livrée

| Couche | Composant | Rôle |
|---|---|---|
| Collecte primaire | `log-collector` | réception rsyslog TCP/UDP 514 et persistance des journaux par hôte / programme |
| Ingestion SIEM | `promtail` | lecture des fichiers centralisés et des `fast.log` Suricata |
| Stockage / requête | `loki` | moteur de recherche LogQL, règles d'alerte, API de consultation |
| Supervision | `grafana` | dashboards SOC / HA et datasource provisionnée |

### Sources observées

| Source | Transport | Chaîne SIEM | Exemple de journaux observés |
|---|---|---|---|
| `fw-isp*` | rsyslog TCP 514 | `log-collector` → `promtail` → `loki` | `kernel.log`, `Keepalived.log`, `rsyslogd.log` |
| `fw-client*` | rsyslog TCP 514 + fichiers Suricata | `log-collector` / `fast.log` → `promtail` → `loki` | `charon.log`, `Keepalived.log`, alertes IDS |
| `fw-server*` | rsyslog TCP 514 | `log-collector` → `promtail` → `loki` | `charon.log`, `Keepalived.log`, `kernel.log` |
| `sshserver` | rsyslog TCP 514 | `log-collector` → `promtail` → `loki` | `sshd.log`, `passwd.log`, `rsyslogd.log` |

### Règles livrées

- `SSHAuthenticationFailuresBurst`
- `KeepalivedMasterTransitionObserved`
- `FirewallKernelDropsObserved`
- `SuricataLabAlertObserved`

## 🚀 Démarrage et validation

```bash
cd hania

docker compose up -d --build log-collector loki promtail grafana fw-isp fw-isp-2 fw-client fw-client-2 fw-server fw-server-2 sshserver

# Validation centralisation
bash ./scripts/test-log-centralization.sh

# Validation SIEM
bash ./scripts/test-siem-phase4.sh

# Validation globale
bash ./scripts/test-full-lab.sh
```

### Points d'accès utiles

- `Grafana` : http://localhost:3002
- `Loki API` : http://localhost:3110
- `Uptime Kuma` : http://localhost:3001

### Vérifications manuelles utiles

```bash
# Santé Grafana
curl -fsS -u admin:labcyber-admin http://127.0.0.1:3002/api/health

# Dashboards provisionnés
curl -fsS -u admin:labcyber-admin 'http://127.0.0.1:3002/api/search?query=LabCyber'

# Règles Loki chargées
curl -fsS http://127.0.0.1:3110/prometheus/api/v1/rules
```

## 📌 Ce que cette phase 4 apporte vraiment

- une **preuve technique** de centralisation des logs des composants critiques
- un **backend SIEM léger** interrogeable et versionné dans le dépôt
- des **règles de détection** concrètes pour SSH, HA, drops firewall et IDS
- des **dashboards de supervision** directement montrables en soutenance
- une intégration propre dans la régression complète du lab, sans casser la haute disponibilité existante

## 🔜 Suite naturelle

La prochaine montée en gamme logique est d'ajouter un SOC plus riche au-dessus de cette base déjà exploitable :

1. `Wazuh` ou `OpenSearch` si vous voulez une brique SIEM plus lourde avec UI et workflow sécurité avancés.
2. Notifications externes sur les alertes Loki/Grafana.
3. Rétention longue durée, rotation explicite et archivage.
4. Normalisation plus poussée des logs web et applicatifs.
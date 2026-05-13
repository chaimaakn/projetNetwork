# 📘 PHASE 4 — Centralisation des Logs & Observabilité

> **Objectif** : sortir d'une lecture en silo des journaux locaux et poser une première brique SOC légère, immédiatement testable et sans dépendance lourde.

> **Positionnement** : cette phase 4 ne livre pas un SIEM complet. Le dépôt embarque volontairement un **collecteur rsyslog central léger** (`log-collector`) pour agréger les journaux clés du lab, valider la télémétrie et préparer une montée en gamme vers `Wazuh` ou `ELK`.

## ✅ Statut courant

- `log-collector` écoute en TCP/UDP 514 sur `mgmt_net` et `lan_server_net`
- `fw-isp`, `fw-isp-2`, `fw-client`, `fw-client-2`, `fw-server`, `fw-server-2` et `sshserver` forwardent leurs journaux via `rsyslog`
- les journaux centralisés sont persistés sous `monitoring/log-collector/logs/`
- la validation automatisée est couverte par `scripts/test-log-centralization.sh` puis par `scripts/test-full-lab.sh`

## 🏗️ Architecture livrée

| Source | Transport | Cible | Exemple de journaux collectés |
|---|---|---|---|
| `fw-isp*` | rsyslog TCP 514 | `log-collector` | `kernel.log`, `Keepalived.log`, `rsyslogd.log` |
| `fw-client*` | rsyslog TCP 514 | `log-collector` | `charon.log`, `Keepalived.log`, `rsyslogd.log` |
| `fw-server*` | rsyslog TCP 514 | `log-collector` | `charon.log`, `Keepalived.log`, `rsyslogd.log` |
| `sshserver` | rsyslog TCP 514 | `log-collector` | `sshd.log`, `passwd.log`, `rsyslogd.log` |

Les fichiers sont rangés dynamiquement par hôte et programme :

```text
monitoring/log-collector/logs/
  fw-isp/kernel.log
  fw-client/charon.log
  fw-server/Keepalived.log
  sshserver/sshd.log
```

## 🚀 Démarrage et validation

```bash
cd hania

docker compose up -d --build log-collector fw-isp fw-isp-2 fw-client fw-client-2 fw-server fw-server-2 sshserver

# Validation dédiée
bash ./scripts/test-log-centralization.sh

# Validation globale
bash ./scripts/test-full-lab.sh
```

### Vérifications manuelles utiles

```bash
# Le collecteur écoute bien
docker exec log-collector ss -ltnu | grep ':514 '

# Emission d'un marqueur depuis un firewall
docker exec fw-isp logger -t manual-test "PHASE4_MANUAL_MARKER"

# Vérification côté collecteur
docker exec log-collector grep -R "PHASE4_MANUAL_MARKER" /var/log/remote
```

## 📌 Ce que cette phase 4 apporte vraiment

- une **preuve technique** que les composants critiques remontent leurs événements vers un point central
- une base d'**audit post-incident** plus crédible que des fichiers locaux dispersés
- un socle léger pour enrichir ensuite les usages : règles de corrélation, alerting, dashboards, rétention

## 🔜 Suite naturelle

La prochaine montée en gamme logique est d'ajouter un backend SOC plus riche au-dessus de ce flux central :

1. `Wazuh` pour la détection, les règles et les dashboards sécurité.
2. Rétention/rotation explicite des journaux centralisés.
3. Alertes sur motifs critiques : brute-force SSH, drops `iptables`, transitions HA, erreurs IPsec.
4. Normalisation des journaux applicatifs web si vous voulez élargir au-delà de la télémétrie sécurité.
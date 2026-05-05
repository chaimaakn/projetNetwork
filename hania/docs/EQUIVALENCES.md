# 🔄 Tableau d'Équivalences : pfSense / FortiGate ↔ Docker

> Pour rédiger les rapports de soutenance et faire le lien avec la formation théorique.

## pfSense → fw-isp (Docker)

| Fonction pfSense | Menu pfSense | Équivalent Docker |
|---|---|---|
| Firewall rules | Firewall > Rules | `iptables` dans `fw-isp/rules.sh` |
| NAT outbound | Firewall > NAT > Outbound | `iptables -t nat POSTROUTING MASQUERADE` |
| Port forward | Firewall > NAT > Port Forward | `iptables -t nat PREROUTING DNAT` |
| DNS Resolver | Services > DNS Resolver | `dnsmasq` (`/etc/dnsmasq.conf`) |
| DHCP Server | Services > DHCP Server | `dnsmasq` avec `dhcp-range` |
| NTP Server | Services > NTP | `chronyd` (`/etc/chrony/chrony.conf`) |
| HAProxy | Services > HAProxy | `haproxy` (`/etc/haproxy/haproxy.cfg`) |
| Multi-WAN / Gateway groups | System > Routing > Gateway Groups | `iproute2` ip rule + ip route policy |
| CARP / VRRP HA | Firewall > Virtual IPs | `keepalived` (à ajouter en Phase 2) |
| Logs | Status > System Logs | `/var/log/fw/*` + rsyslog |
| User Manager | System > User Manager | Comptes Unix `/etc/passwd` |
| Aliases | Firewall > Aliases | `ipset` |
| Captive Portal | Services > Captive Portal | nginx + auth (à ajouter si besoin) |
| pfBlockerNG | Package | listes ipset + cron |

## FortiGate → fw-client / fw-server (Docker)

| Fonction FortiGate | Menu FortiOS | Équivalent Docker |
|---|---|---|
| IPv4 Policy | Policy & Objects > IPv4 Policy | `iptables FORWARD` rules |
| Address Object | Policy & Objects > Addresses | `ipset` |
| Service Object | Policy & Objects > Services | `iptables --dport` ou ipset bitmap:port |
| Schedule | Policy & Objects > Schedules | cron + iptables -A/-D scriptés |
| IPsec VPN (Phase 1) | VPN > IPsec Tunnels > Phase 1 | `strongswan` ipsec.conf section `ike=` |
| IPsec VPN (Phase 2) | VPN > IPsec Tunnels > Phase 2 | `strongswan` ipsec.conf section `esp=`, `leftsubnet=` |
| Pre-shared Key | VPN > IPsec Tunnels > Auth | `/etc/ipsec.secrets` |
| DHCP Server | Network > Interfaces > DHCP | `dnsmasq` (mode DHCP) |
| Web Filter | Security Profiles > Web Filter | `squid` + ACL + blocked_domains.txt |
| Application Control | Security Profiles > Application Control | `suricata` ou `nDPI` |
| IPS | Security Profiles > IPS | `suricata` avec règles ET/Pro |
| SSL Inspection | Security Profiles > SSL/SSH Inspection | `squid` SslBump (complexe) |
| Antivirus | Security Profiles > AntiVirus | ClamAV + e2guardian |
| Logging | Log & Report | rsyslog → fichier ou SIEM (Phase 4) |
| HA Active-Passive | System > HA | `keepalived` + `conntrackd` |
| SD-WAN | Network > SD-WAN | `iproute2` policy routing + scripting |
| FortiGuard | System > FortiGuard | N/A (services payants Fortinet) |

## CLI FortiOS → CLI strongSwan/iptables

| Commande FortiOS | Équivalent Docker |
|---|---|
| `get vpn ipsec tunnel summary` | `ipsec statusall` |
| `diagnose vpn ike gateway list` | `ipsec listsas` |
| `get system status` | `uname -a; uptime` |
| `show firewall policy` | `iptables -L FORWARD -n -v --line-numbers` |
| `diagnose sniffer packet any` | `tcpdump -i any` |
| `get router info routing-table all` | `ip route show table all` |
| `execute ping <ip>` | `ping <ip>` |
| `execute traceroute <ip>` | `traceroute <ip>` |
| `diagnose firewall iprope show` | `iptables -L -v -n` |
| `get system performance status` | `top; vmstat; iostat` |

## Mapping pédagogique des concepts

| Concept formation | Implémentation Docker | Commentaire |
|---|---|---|
| **Firewall stateful** | `iptables -m state --state ESTABLISHED,RELATED` | Identique au FortiGate |
| **NAT/PAT** | `iptables -t nat POSTROUTING MASQUERADE` | Sémantique identique |
| **VLAN 802.1Q** | Réseaux Docker `bridge` séparés | Isolation L2 équivalente fonctionnellement |
| **Trunk** | Conteneur connecté à plusieurs networks | Pas de tagging réel mais effet équivalent |
| **VPN IPsec IKEv2** | strongSwan | Implémentation Linux native = ce qu'utilise FortiGate sous le capot |
| **Phase 1 IKE** | section `ike=aes256-sha256-modp2048` | Algos identiques |
| **Phase 2 ESP** | section `esp=aes256-sha256-modp2048` | Algos identiques |
| **PFS** | `pfs=yes` + DH group ≥ 14 | Identique |
| **DPD** | `dpdaction=restart` | Identique |
| **Web Filter URL category** | squid `dstdomain` ACL | Pédagogique : montre la mécanique |
| **Application Control** | Suricata + signatures | Plus formateur (on voit les règles) |
| **HA Active/Passive** | keepalived + conntrackd | VRRP au lieu de FGCP propriétaire |
| **Multi-WAN failover** | iproute2 + nfqueue scripting | Concept identique, syntaxe différente |
| **Logging centralisé** | rsyslog → Wazuh/ELK | Phase 4 |

## Limites de l'analogie

⚠️ Ce que Docker NE peut PAS reproduire fidèlement :

1. **Performance ASIC FortiGate** : un FortiGate physique a des chips dédiés (NP, CP) pour le crypto et le packet inspection. En Docker, tout est software.
2. **HA FGCP propriétaire Fortinet** : le protocole de cluster Fortinet n'est pas open. On simule avec keepalived + conntrackd.
3. **FortiGuard signatures** : services Fortinet payants, non disponibles. Remplacés par règles open-source (Suricata, Emerging Threats).
4. **Inspection SSL/TLS native** : possible avec Squid SslBump mais beaucoup plus complexe à mettre en œuvre que sur FortiGate.
5. **CARP pfSense** : Docker bridge ne supporte pas natif le multicast CARP. On utilise VRRP via keepalived.

---

## Comment utiliser ce tableau dans les soutenances

À chaque démo, **dire les deux noms** :
> « Ici je crée une politique IPv4, équivalent FortiGate du `Policy & Objects > IPv4 Policy`. En Docker je l'écris avec `iptables -A FORWARD ...`. La sémantique est identique : matching 5-tuple, action ACCEPT/DROP, stateful tracking. »

Cela démontre la **maîtrise des concepts** au-delà de l'outil.
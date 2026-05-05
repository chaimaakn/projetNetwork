# 🔧 Guide de Dépannage

## Problème 1 : `docker compose build` échoue sur `kalilinux/kali-rolling`

**Cause** : image volumineuse, parfois lente à télécharger.

**Solution** :
```bash
# Pré-télécharger
docker pull kalilinux/kali-rolling

# Puis relancer
docker compose build
```

Si `apt-get` échoue dans la build Kali :
```bash
# Modifier attacker/Dockerfile pour ajouter un mirroir plus rapide
RUN sed -i 's|http://kali.download/kali|http://mirror.serverion.com/kali|g' /etc/apt/sources.list
```

---

## Problème 2 : VPN IPsec ne s'établit pas

**Diagnostic** :
```bash
# Vérifier les modules kernel
docker exec fw-client lsmod | grep -E "esp|ah|xfrm"
# Si rien → le kernel hôte ne supporte pas IPsec

# Voir les logs charon
docker exec fw-client tail -100 /var/log/syslog | grep -i charon
docker exec fw-client ipsec statusall
```

**Solutions** :

1. **Linux** : charger les modules sur l'hôte
```bash
sudo modprobe esp4 ah4 xfrm4_tunnel
```

2. **Docker Desktop (Mac/Windows)** : IPsec est limité dans LinuxKit. Alternatives :
   - Utiliser **WireGuard** à la place (plus simple, fonctionne en user-space)
   - Voir section "Alternative WireGuard" plus bas

3. **PSK différents** entre les deux côtés : vérifier `/etc/ipsec.secrets` est identique

4. **Charon ne démarre pas** :
```bash
docker exec fw-client ipsec restart
sleep 5
docker exec fw-client ipsec statusall
```

---

## Problème 3 : `client1` ne peut pas joindre `webserver`

**Diagnostic en cascade** :
```bash
# 1. Le VPN est-il UP ?
docker exec fw-client ipsec statusall | grep ESTABLISHED

# 2. Les routes sont-elles bonnes ?
docker exec client1 ip route
# Doit afficher : default via 192.168.10.1

# 3. Le forwarding est-il actif ?
docker exec fw-client cat /proc/sys/net/ipv4/ip_forward
# Doit être 1

# 4. iptables n'est-il pas trop restrictif ?
docker exec fw-client iptables -L FORWARD -n -v
# Vérifier que les règles autorisent 192.168.10.0/24 -> 192.168.20.0/24

# 5. Tcpdump pour voir le trafic
docker exec fw-client tcpdump -i any -n host 192.168.10.10 and host 192.168.20.10
```

---

## Problème 4 : Conflit de réseau Docker

```
ERROR: Pool overlaps with other one on this address space
```

**Solution** :
```bash
# Lister les réseaux existants
docker network ls
docker network prune

# Ou changer les subnets dans docker-compose.yml
# Ex: 10.10.0.0/24 → 172.30.10.0/24
```

---

## Problème 5 : Performance / RAM insuffisante

Si la machine a < 8 Go RAM, désactiver des services :

```yaml
# Dans docker-compose.yml, commenter temporairement :
# - kali (très gourmand)
# - uptime-kuma
# - client2
```

Pour récupérer Kali plus tard, utiliser une image plus légère :
```dockerfile
FROM kalilinux/kali-last-release   # Plus stable
# Ou base Debian + outils essentiels seulement
FROM debian:12-slim
RUN apt-get update && apt-get install -y nmap hydra nikto netcat-openbsd
```

---

## Problème 6 : `iptables: command not found` à l'intérieur d'un conteneur

```bash
# Vérifier que iptables est bien installé
docker exec fw-client which iptables
docker exec fw-client apt list --installed | grep iptables

# Si manquant : reconstruire l'image
docker compose build fw-client --no-cache
```

---

## Problème 7 : Permissions sur scripts/

```bash
# Sous Windows : les bits exécutables ne se propagent pas
chmod +x scripts/*.sh
chmod +x fw-*/entrypoint.sh
chmod +x fw-*/rules.sh
```

---

## Problème 8 : Squid ne filtre pas les sites

```bash
# Vérifier que squid tourne
docker exec fw-client ps aux | grep squid

# Vérifier les logs
docker exec fw-client tail -f /var/log/squid/access.log

# Tester en forçant le proxy
docker exec client1 curl -x http://192.168.10.1:3128 -I http://www.facebook.com
# Doit retourner 403 si bloqué
```

Si le filtrage ne marche pas :
```bash
# Recharger la config sans redémarrer
docker exec fw-client squid -k reconfigure

# Vérifier la config
docker exec fw-client squid -k parse
```

---

## Alternative WireGuard (si IPsec impossible)

Si l'environnement (Mac, Windows, Docker Desktop) bloque IPsec, basculer en WireGuard.

**Modifier `fw-client/Dockerfile`** :
```dockerfile
RUN apt-get install -y wireguard-tools
```

**Créer `fw-client/wg0.conf`** :
```
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.99.0.1/30
ListenPort = 51820

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
AllowedIPs = 192.168.20.0/24, 10.99.0.2/32
Endpoint = 10.20.0.2:51820
PersistentKeepalive = 25
```

**Démarrage** :
```bash
docker exec fw-client wg-quick up wg0
docker exec fw-client wg
```

---

## Logs centraux

Tous les logs sont dans `./<service>/logs/` (volumes montés).

```bash
# Tail temps réel
tail -f fw-client/logs/startup.log
tail -f fw-isp/logs/dnsmasq.log

# Logs Docker
docker compose logs -f --tail=50 fw-client
docker compose logs --since 5m
```

---

## Reset complet du lab

```bash
# Tout arrêter + supprimer + nettoyer
docker compose down -v --rmi local
docker system prune -af --volumes

# Reconstruire from scratch
docker compose build --no-cache
docker compose up -d
```
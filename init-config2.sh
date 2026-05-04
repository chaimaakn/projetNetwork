#!/bin/bash
# init-config.sh — SSI-Lab
# A relancer apres chaque "containerlab deploy"
# Les configs IP ne persistent pas dans les containers

echo "================================================"
echo "   SSI-Lab — Configuration reseau"
echo "================================================"

# ── fw-isp ──────────────────────────────────────────
echo "[1/7] Configuration fw-isp..."
docker exec clab-ssi-lab-fw-isp sh -c "
  ip addr add 10.0.1.1/30 dev eth1 2>/dev/null || true
  ip addr add 10.0.2.1/30 dev eth2 2>/dev/null || true
  ip link set eth1 up
  ip link set eth2 up
  ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true
  ip route add 192.168.10.0/24 via 10.0.1.2 2>/dev/null || true
  ip route add 192.168.20.0/24 via 10.0.2.2 2>/dev/null || true
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
"

# ── fw-client ────────────────────────────────────────
echo "[2/7] Configuration fw-client..."
docker exec clab-ssi-lab-fw-client sh -c "
  ip addr add 10.0.1.2/30 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.0.1.1 dev eth1
  ip route add 192.168.20.0/24 via 10.0.1.1 2>/dev/null || true
  iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE 2>/dev/null || true
  ip link add name br-client type bridge 2>/dev/null || true
  ip link set eth2 master br-client 2>/dev/null || true
  ip link set eth3 master br-client 2>/dev/null || true
  ip addr add 192.168.10.1/24 dev br-client 2>/dev/null || true
  ip link set br-client up
  iptables -P FORWARD DROP
  iptables -A FORWARD -s 192.168.10.10 -i br-client -o eth1 -j ACCEPT
  iptables -A FORWARD -s 192.168.10.20 -i br-client -o eth1 -j DROP
  iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
"

# ── fw-server ────────────────────────────────────────
echo "[3/7] Configuration fw-server..."
docker exec clab-ssi-lab-fw-server sh -c "
  ip addr add 10.0.2.2/30 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
  ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true
  ip route add default via 10.0.2.1 dev eth1
  ip route add 192.168.10.0/24 via 10.0.2.1 2>/dev/null || true
  iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE 2>/dev/null || true
  ip link add name br-server type bridge 2>/dev/null || true
  ip link set eth2 master br-server 2>/dev/null || true
  ip link set eth3 master br-server 2>/dev/null || true
  ip addr add 192.168.20.1/24 dev br-server 2>/dev/null || true
  ip link set br-server up
  iptables -P FORWARD DROP
  iptables -A FORWARD -i eth1 -o br-server -j ACCEPT
  iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
"

# ── pc-client ────────────────────────────────────────
echo "[4/7] Configuration pc-client..."
docker exec clab-ssi-lab-pc-client sh -c "
  ip addr add 192.168.10.10/24 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 192.168.10.1 dev eth1
"

# ── serveur-web ──────────────────────────────────────
echo "[5/7] Configuration serveur-web..."
docker exec clab-ssi-lab-serveur-web sh -c "
  ip addr add 192.168.20.10/24 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 192.168.20.1 dev eth1
"

# ── kali (via nsenter car pas de iproute2) ───────────
echo "[6/7] Configuration kali..."
KALI_PID=$(docker inspect -f '{{.State.Pid}}' clab-ssi-lab-kali)
sudo nsenter -t $KALI_PID -n -- ip route del default 2>/dev/null || true
sudo nsenter -t $KALI_PID -n -- ip route add default via 192.168.10.1 dev eth1

# ── wazuh (via nsenter car pas de iproute2) ──────────
echo "[7/7] Configuration wazuh..."
WAZUH_PID=$(docker inspect -f '{{.State.Pid}}' clab-ssi-lab-wazuh)
sudo nsenter -t $WAZUH_PID -n -- ip route del default 2>/dev/null || true
sudo nsenter -t $WAZUH_PID -n -- ip route add default via 192.168.20.1 dev eth1

# ── Tests automatiques ───────────────────────────────
echo ""
echo "================================================"
echo "   Tests de connectivite"
echo "================================================"

docker exec clab-ssi-lab-pc-client ping -c 1 -W 1 192.168.10.1  > /dev/null && echo "OK  pc-client  -> fw-client"       || echo "FAIL pc-client  -> fw-client"
docker exec clab-ssi-lab-pc-client ping -c 1 -W 1 192.168.20.10 > /dev/null && echo "OK  pc-client  -> serveur-web"     || echo "FAIL pc-client  -> serveur-web"
docker exec clab-ssi-lab-pc-client ping -c 1 -W 1 192.168.20.20 > /dev/null && echo "OK  pc-client  -> wazuh"           || echo "FAIL pc-client  -> wazuh"
sudo nsenter -t $KALI_PID -n -- ping -c 1 -W 1 192.168.10.1     > /dev/null && echo "OK  kali       -> fw-client"       || echo "FAIL kali       -> fw-client"
sudo nsenter -t $KALI_PID -n -- ping -c 1 -W 1 192.168.20.10    > /dev/null && echo "FAIL kali      -> serveur-web (doit etre bloque !)" || echo "OK  kali       -> serveur-web BLOQUE"

echo ""
echo "================================================"
echo "   Lab pret !"
echo "================================================"
echo ""
echo "Acces aux containers :"
echo "  docker exec -it clab-ssi-lab-fw-client sh"
echo "  docker exec -it clab-ssi-lab-fw-server sh"
echo "  docker exec -it clab-ssi-lab-fw-isp sh"
echo "  docker exec -it clab-ssi-lab-pc-client sh"
echo "  docker exec -it clab-ssi-lab-serveur-web sh"

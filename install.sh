#!/bin/bash
set -e

echo "[FW] Настройка hostname"
hostnamectl set-hostname fw.ws.kz

echo "[FW] Установка пакетов"
apt update
apt install -y nftables wireguard squid

echo "[FW] Включение маршрутизации"
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p

echo "[FW] Настройка сети"
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
 address 1.1.1.10
 netmask 255.255.255.0

auto eth1
iface eth1 inet static
 address 10.1.10.1
 netmask 255.255.255.0

auto eth2
iface eth2 inet static
 address 10.1.20.1
 netmask 255.255.255.0

auto eth3
iface eth3 inet static
 address 10.1.30.1
 netmask 255.255.255.0
EOF

systemctl restart networking

echo "[FW] nftables"
cat > /etc/nftables.conf <<EOF
table inet filter {
 chain input {
  type filter hook input priority 0;
  policy drop;
  ct state established,related accept
  iif lo accept
  tcp dport {22,80,443} accept
 }

 chain forward {
  type filter hook forward priority 0;
  policy drop;
  iif eth1 accept
  iif eth2 accept
 }

 chain output {
  type filter hook output priority 0;
  policy accept;
 }
}

table ip nat {
 chain postrouting {
  type nat hook postrouting priority 100;
  oif eth0 masquerade
 }
}
EOF

systemctl enable nftables
systemctl restart nftables

echo "[FW] WireGuard"
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.1.30.1/24
PrivateKey = $(cat /etc/wireguard/private.key)
ListenPort = 51820
EOF

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "[FW] Squid (прозрачный прокси)"
cat > /etc/squid/squid.conf <<EOF
http_port 3128 transparent
request_header_add X-Secured-By ws-proxy
EOF

systemctl restart squid

echo "[FW] DONE"
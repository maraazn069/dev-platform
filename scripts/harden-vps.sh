#!/bin/bash
# ================================================================
# harden-vps.sh — Hardening one-shot untuk VPS Ubuntu 22.04 / 24.04
#
# Pakai: sudo bash scripts/harden-vps.sh
#
# Yang dilakukan:
#   1. fail2ban: jail SSH (bantu lawan brute-force)
#   2. unattended-upgrades: auto-install security patch
#   3. /etc/docker/daemon.json: log rotation default
#   4. sysctl: hardening jaringan dasar
#   5. SSH: disable root login + password auth (HANYA kalau key terdeteksi!)
#   6. Reload semua service
#
# Aman dijalankan ulang (idempotent).
# ================================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Harap jalankan sebagai root: sudo bash scripts/harden-vps.sh"
  exit 1
fi

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[1/6] Install fail2ban + unattended-upgrades + auditd...${NC}"
apt update -qq
DEBIAN_FRONTEND=noninteractive apt install -y -qq fail2ban unattended-upgrades apt-listchanges

echo -e "${YELLOW}[2/6] Konfigurasi fail2ban (jail SSH)...${NC}"
cat > /etc/fail2ban/jail.d/devplatform.conf <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 4
bantime  = 6h
EOF
systemctl enable fail2ban >/dev/null
systemctl restart fail2ban
echo -e "${GREEN}✓ fail2ban aktif (lihat: fail2ban-client status sshd)${NC}"

echo -e "${YELLOW}[3/6] Konfigurasi unattended-upgrades (auto security patch)...${NC}"
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable unattended-upgrades >/dev/null
systemctl restart unattended-upgrades
echo -e "${GREEN}✓ Security patch akan auto-install harian${NC}"

echo -e "${YELLOW}[4/6] Konfigurasi Docker daemon (log rotation default)...${NC}"
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then
  cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s)
fi
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "no-new-privileges": true,
  "userland-proxy": false
}
EOF
systemctl restart docker
echo -e "${GREEN}✓ Docker daemon di-restart dengan log rotation${NC}"

echo -e "${YELLOW}[5/6] Konfigurasi sysctl (hardening jaringan)...${NC}"
cat > /etc/sysctl.d/99-devplatform.conf <<'EOF'
# IP spoof protection
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1

# Don't accept source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Don't accept ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Don't send ICMP redirects
net.ipv4.conf.all.send_redirects = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 4096

# Log martians (paket aneh)
net.ipv4.conf.all.log_martians = 1

# Ignore broadcast pings (smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Increase file watchers (dibutuhkan code-server / vite)
fs.inotify.max_user_watches = 524288
fs.file-max = 200000
EOF
sysctl --system >/dev/null
echo -e "${GREEN}✓ sysctl hardening aktif${NC}"

echo -e "${YELLOW}[6/6] Hardening SSH...${NC}"
# Cek dulu: kalau user yang jalanin tidak punya authorized_keys, JANGAN disable password,
# nanti dia ke-lock-out total!
SSH_USER=$(logname 2>/dev/null || echo "")
SAFE_TO_DISABLE_PW=false
if [ -n "$SSH_USER" ] && [ -f "/home/$SSH_USER/.ssh/authorized_keys" ] && [ -s "/home/$SSH_USER/.ssh/authorized_keys" ]; then
  SAFE_TO_DISABLE_PW=true
fi
# Kalau ada key di /root juga aman
if [ -f "/root/.ssh/authorized_keys" ] && [ -s "/root/.ssh/authorized_keys" ]; then
  SAFE_TO_DISABLE_PW=true
fi

SSH_CONFIG="/etc/ssh/sshd_config.d/99-devplatform.conf"
if $SAFE_TO_DISABLE_PW; then
  cat > "$SSH_CONFIG" <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
MaxAuthTries 4
EOF
  systemctl reload ssh || systemctl reload sshd
  echo -e "${GREEN}✓ SSH password auth DIMATIKAN (key terdeteksi). Pakai SSH key.${NC}"
else
  cat > "$SSH_CONFIG" <<'EOF'
PermitRootLogin prohibit-password
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
MaxAuthTries 4
EOF
  systemctl reload ssh || systemctl reload sshd
  echo -e "${RED}⚠ SSH password auth MASIH AKTIF — tidak ada SSH key terdeteksi.${NC}"
  echo -e "${RED}  Tambahkan SSH key dulu, lalu jalankan ulang script ini.${NC}"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Hardening VPS selesai${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Cek status:"
echo "  fail2ban-client status sshd"
echo "  systemctl status unattended-upgrades"
echo "  cat /etc/sysctl.d/99-devplatform.conf"
echo ""
echo "Backup harian: pasang dengan  sudo bash scripts/install-backup-cron.sh"

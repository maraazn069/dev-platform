#!/bin/bash
# ================================================================
# install-vps.sh — Installer otomatis Self-Hosted Dev Platform
#
# Cara pakai (satu perintah dari SSH):
#   bash <(curl -fsSL https://raw.githubusercontent.com/USERMU/REPO/main/scripts/install-vps.sh)
#
# Atau setelah clone:
#   sudo bash scripts/install-vps.sh
# ================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
echo "  ██████╗ ███████╗██╗   ██╗    ██████╗ ██╗      █████╗ ████████╗"
echo "  ██╔══██╗██╔════╝██║   ██║    ██╔══██╗██║     ██╔══██╗╚══██╔══╝"
echo "  ██║  ██║█████╗  ██║   ██║    ██████╔╝██║     ███████║   ██║   "
echo "  ██║  ██║██╔══╝  ╚██╗ ██╔╝    ██╔═══╝ ██║     ██╔══██║   ██║   "
echo "  ██████╔╝███████╗ ╚████╔╝     ██║     ███████╗██║  ██║   ██║   "
echo "  ╚═════╝ ╚══════╝  ╚═══╝      ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   "
echo -e "${NC}"
echo -e "${BOLD}  Self-Hosted Dev Platform — Installer Otomatis${NC}"
echo -e "  Platform coding mandiri untuk 1-10 user belajar"
echo ""
echo -e "${YELLOW}────────────────────────────────────────────────${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan sebagai root: sudo bash scripts/install-vps.sh${NC}"
  exit 1
fi

if ! command -v apt &> /dev/null; then
  echo -e "${RED}Script ini hanya untuk Ubuntu/Debian.${NC}"
  exit 1
fi

# ---- Tanya konfigurasi dasar ----
echo -e "${BOLD}Konfigurasi Platform${NC}"
echo ""

read -p "$(echo -e ${YELLOW})Domain utama (contoh: dev.domainku.com): $(echo -e ${NC})" DOMAIN
read -p "$(echo -e ${YELLOW})Email untuk HTTPS/Let's Encrypt: $(echo -e ${NC})" LETSENCRYPT_EMAIL
read -p "$(echo -e ${YELLOW})Timezone (Enter untuk Asia/Jakarta): $(echo -e ${NC})" TZ_INPUT
TZ="${TZ_INPUT:-Asia/Jakarta}"

echo ""
echo -e "${BOLD}Konfigurasi Database${NC}"
echo ""
read -p "$(echo -e ${YELLOW})Password PostgreSQL (Enter untuk auto-generate): $(echo -e ${NC})" PG_PASS
if [ -z "$PG_PASS" ]; then PG_PASS=$(openssl rand -base64 20); fi

read -p "$(echo -e ${YELLOW})Password MySQL root (Enter untuk auto-generate): $(echo -e ${NC})" MYSQL_ROOT_PASS
if [ -z "$MYSQL_ROOT_PASS" ]; then MYSQL_ROOT_PASS=$(openssl rand -base64 20); fi

read -p "$(echo -e ${YELLOW})Email login pgAdmin (Enter untuk admin@local.dev): $(echo -e ${NC})" PGADMIN_EMAIL
if [ -z "$PGADMIN_EMAIL" ]; then PGADMIN_EMAIL="admin@local.dev"; fi

read -p "$(echo -e ${YELLOW})Password pgAdmin (Enter untuk auto-generate): $(echo -e ${NC})" PGADMIN_PASSWORD
if [ -z "$PGADMIN_PASSWORD" ]; then PGADMIN_PASSWORD=$(openssl rand -base64 16); fi

echo ""
echo -e "${BOLD}Akun Admin Portal${NC}"
echo -e "${YELLOW}Akun ini untuk login ke https://DOMAIN/admin (kelola user, project, dll)${NC}"
read -p "$(echo -e ${YELLOW})Username admin portal (Enter untuk 'admin'): $(echo -e ${NC})" ADMIN_USERNAME
if [ -z "$ADMIN_USERNAME" ]; then ADMIN_USERNAME="admin"; fi

while true; do
  read -s -p "$(echo -e ${YELLOW})Password admin portal (min 10 karakter, ketik manual): $(echo -e ${NC})" ADMIN_PASSWORD
  echo ""
  if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 14)
    echo -e "${GREEN}✓ Auto-generate password admin: ${YELLOW}$ADMIN_PASSWORD${NC}"
    echo -e "${RED}  CATAT BAIK-BAIK PASSWORD INI!${NC}"
    break
  fi
  # Bersihkan \r dari Windows paste
  ADMIN_PASSWORD=$(echo "$ADMIN_PASSWORD" | tr -d '\r')
  if [ ${#ADMIN_PASSWORD} -lt 10 ]; then
    echo -e "${RED}⚠ Password kependekan (${#ADMIN_PASSWORD} karakter). Minimal 10. Ulangi.${NC}"
    continue
  fi
  read -s -p "$(echo -e ${YELLOW})Ulangi password admin: $(echo -e ${NC})" ADMIN_PASSWORD2
  echo ""
  ADMIN_PASSWORD2=$(echo "$ADMIN_PASSWORD2" | tr -d '\r')
  if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD2" ]; then
    echo -e "${RED}⚠ Password tidak cocok. Ulangi.${NC}"
    continue
  fi
  break
done

read -p "$(echo -e ${YELLOW})Email admin portal (Enter untuk skip): $(echo -e ${NC})" ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-}"

echo ""
echo -e "${BOLD}Akses Remote Database${NC}"
echo -e "${YELLOW}Daftarkan IP publik laptop kamu untuk konek MySQL/PostgreSQL via DBeaver/Workbench."
echo -e "Cek IP publik kamu: ${BOLD}curl ifconfig.me${NC} (jalankan di laptop kamu, bukan VPS!)"
echo -e "Format: pisah koma, contoh: 203.0.113.5,198.51.100.10"
echo -e "${RED}Kosongkan untuk SKIP firewall whitelist (port 3306/5432 hanya bisa dari localhost VPS).${NC}"
read -p "$(echo -e ${YELLOW})IP yang boleh konek DB (Enter untuk skip): $(echo -e ${NC})" DB_REMOTE_IPS

read -p "$(echo -e ${YELLOW})Idle timeout login portal dalam menit (Enter untuk 60): $(echo -e ${NC})" IDLE_TIMEOUT_INPUT
IDLE_TIMEOUT_MIN="${IDLE_TIMEOUT_INPUT:-60}"

MYSQL_PASS=$(openssl rand -base64 16)
SESSION_SECRET=$(openssl rand -base64 32)

echo ""
echo -e "${YELLOW}────────────────────────────────────────────────${NC}"
echo -e "${BOLD}Memulai instalasi...${NC}"
echo -e "${YELLOW}────────────────────────────────────────────────${NC}"
echo ""

# [1/8] Update sistem
echo -e "${CYAN}[1/8]${NC} Update sistem..."
apt update -qq && apt upgrade -y -qq
echo -e "${GREEN}✓ Sistem diperbarui${NC}"

# [2/8] Install dependensi
echo -e "${CYAN}[2/8]${NC} Install dependensi dasar..."
DEBIAN_FRONTEND=noninteractive apt install -y -qq curl wget git nano ufw fail2ban htop unzip openssl unattended-upgrades apt-listchanges
echo -e "${GREEN}✓ Dependensi terinstall${NC}"

# Aktifkan fail2ban (jail SSH default ada)
cat > /etc/fail2ban/jail.d/devplatform.conf <<'F2BEOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
maxretry = 4
bantime = 6h
F2BEOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1
echo -e "${GREEN}✓ fail2ban aktif (jail sshd)${NC}"

# Aktifkan unattended-upgrades (auto security patch)
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUEOF
systemctl enable unattended-upgrades >/dev/null 2>&1
systemctl restart unattended-upgrades >/dev/null 2>&1
echo -e "${GREEN}✓ Auto-update security patch aktif${NC}"

# [3/8] Install Docker
echo -e "${CYAN}[3/8]${NC} Install Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh -s -- -q
  systemctl enable docker && systemctl start docker
  echo -e "${GREEN}✓ Docker terinstall${NC}"
else
  echo -e "${GREEN}✓ Docker sudah ada${NC}"
fi

# Konfigurasi Docker daemon (log rotation default + live restore)
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DOCKEREOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "no-new-privileges": true,
  "userland-proxy": false
}
DOCKEREOF
systemctl restart docker
echo -e "${GREEN}✓ Docker daemon dikonfigurasi (log rotation + live restore)${NC}"

# [4/8] Docker Compose
echo -e "${CYAN}[4/8]${NC} Install Docker Compose..."
if ! docker compose version &> /dev/null 2>&1; then
  apt install -y -qq docker-compose-plugin
fi
echo -e "${GREEN}✓ Docker Compose siap${NC}"

# [5/8] Certbot (Nginx dihandle Docker, bukan sistem)
echo -e "${CYAN}[5/8]${NC} Install Certbot..."
apt install -y -qq certbot
# Pastikan sistem nginx tidak jalan (konflik dengan Docker nginx di port 80)
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
echo -e "${GREEN}✓ Certbot siap (sistem nginx dinonaktifkan)${NC}"

# [6/8] Firewall
echo -e "${CYAN}[6/8]${NC} Konfigurasi firewall..."
ufw --force reset > /dev/null
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow 22/tcp > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443/tcp > /dev/null

if [ -n "$DB_REMOTE_IPS" ]; then
  # Whitelist HANYA IP yang user daftarkan untuk port DB
  # Bersihkan \r (Windows paste), spasi, tab, newline dari input
  DB_REMOTE_IPS_CLEAN=$(echo "$DB_REMOTE_IPS" | tr -d '\r\t' | tr -s ' ')
  IFS=', ' read -ra IP_ARR <<< "$DB_REMOTE_IPS_CLEAN"
  for IP_RAW in "${IP_ARR[@]}"; do
    # Trim whitespace + carriage return per item
    IP=$(echo "$IP_RAW" | xargs | tr -d '\r')
    [ -z "$IP" ] && continue
    # Validasi format IPv4 (dengan/tanpa CIDR)
    if [[ ! "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]]; then
      echo -e "${YELLOW}⚠ Skip IP tidak valid: '$IP' (harus format 1.2.3.4 atau 1.2.3.0/24)${NC}"
      continue
    fi
    # Pakai || true supaya 1 IP gagal tidak crash semua install
    if ufw allow from "$IP" to any port 3306 proto tcp > /dev/null 2>&1 \
       && ufw allow from "$IP" to any port 5432 proto tcp > /dev/null 2>&1; then
      echo -e "${GREEN}✓ Whitelist DB akses: $IP${NC}"
    else
      echo -e "${YELLOW}⚠ Gagal whitelist '$IP' (cek format), lanjutkan...${NC}"
    fi
  done
  # Update var supaya .env nyimpan versi bersih
  DB_REMOTE_IPS="$DB_REMOTE_IPS_CLEAN"
  echo -e "${GREEN}✓ Firewall aktif (22, 80, 443) + DB hanya untuk IP whitelist${NC}"
else
  echo -e "${YELLOW}⚠ Tidak ada IP whitelist DB. Port 3306/5432 TIDAK terbuka dari internet.${NC}"
  echo -e "${YELLOW}  Untuk akses DB dari laptop, edit nanti: sudo ufw allow from <IP> to any port 3306 proto tcp${NC}"
  echo -e "${GREEN}✓ Firewall aktif (22, 80, 443)${NC}"
fi
ufw --force enable > /dev/null

# [7/8] Clone atau setup repo
echo -e "${CYAN}[7/8]${NC} Setup direktori project..."
mkdir -p /opt/devplatform/data
mkdir -p /opt/devplatform/configs
chmod 755 /opt/devplatform

# Kalau belum ada repo (mode one-liner), clone dari GitHub
if [ ! -f "docker-compose.yml" ]; then
  echo ""
  read -p "$(echo -e ${YELLOW})URL GitHub repo kamu (contoh: https://github.com/user/repo): $(echo -e ${NC})" REPO_URL
  cd /opt/devplatform
  git clone "$REPO_URL" platform
  cd platform
fi

echo -e "${GREEN}✓ Direktori siap${NC}"

# [8/8] Buat file .env
echo -e "${CYAN}[8/8]${NC} Membuat file .env..."
cat > .env <<EOF
# ================================================================
# .env — Konfigurasi Self-Hosted Dev Platform
# File ini TIDAK boleh di-commit ke GitHub (sudah ada di .gitignore)
# ================================================================

DOMAIN=$DOMAIN
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
SESSION_SECRET=$SESSION_SECRET
TZ=$TZ
PROTOCOL=http

# Idle timeout login portal (menit)
IDLE_TIMEOUT_MIN=$IDLE_TIMEOUT_MIN

# Whitelist IP yang boleh akses DB remote (kosong = hanya localhost)
DB_REMOTE_IPS=$DB_REMOTE_IPS

# Resource limits per code-server container
CODE_SERVER_MEM=2g
CODE_SERVER_CPUS=1.5
CODE_SERVER_PIDS=300

# Database PostgreSQL
POSTGRES_PASSWORD=$PG_PASS

# Database MySQL
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS
MYSQL_PASSWORD=$MYSQL_PASS

# pgAdmin (web UI PostgreSQL)
PGADMIN_EMAIL=$PGADMIN_EMAIL
PGADMIN_PASSWORD=$PGADMIN_PASSWORD

# Akun admin portal (di-set saat install, TIDAK force-change kalau diisi manual)
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_EMAIL=$ADMIN_EMAIL

# Direktori data & backup
DATA_DIR=/opt/devplatform/data
BACKUP_ROOT=/opt/devplatform/backups
EOF
chmod 600 .env
echo -e "${GREEN}✓ File .env dibuat${NC}"

# Generate nginx.conf dengan domain yang benar
echo -e "${CYAN}Membuat konfigurasi Nginx...${NC}"
cat > nginx/nginx.conf << 'NGINXEOF'
events {
    worker_connections 1024;
}

http {
    # Pakai Docker internal DNS supaya hostname container di-resolve
    # SAAT REQUEST datang, bukan saat nginx startup (mencegah crash kalau
    # container upstream belum siap saat boot).
    resolver 127.0.0.11 valid=30s ipv6=off;

    server {
        listen 80;
        server_name __DOMAIN__;

        client_max_body_size 50M;

        location / {
            set $upstream_portal "devplatform-portal:3000";
            proxy_pass http://$upstream_portal;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 60s;
            proxy_connect_timeout 10s;
        }
    }

    server {
        listen 80;
        server_name mysql.__DOMAIN__;
        client_max_body_size 256M;

        location / {
            set $upstream_pma "devplatform-phpmyadmin:80";
            proxy_pass http://$upstream_pma;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    server {
        listen 80;
        server_name pgadmin.__DOMAIN__;
        client_max_body_size 50M;

        location / {
            set $upstream_pga "devplatform-pgadmin:80";
            proxy_pass http://$upstream_pga;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Script-Name "";
        }
    }

    server {
        listen 80;
        server_name files.__DOMAIN__;
        client_max_body_size 2048M;

        location / {
            set $upstream_fb "devplatform-filebrowser:80";
            proxy_pass http://$upstream_fb;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
        }
    }

    server {
        listen 80 default_server;
        server_name _;
        return 301 http://__DOMAIN__$request_uri;
    }
}
NGINXEOF
sed -i "s|__DOMAIN__|$DOMAIN|g" nginx/nginx.conf
echo -e "${GREEN}✓ nginx.conf dibuat untuk domain: $DOMAIN${NC}"

# Build & start semua service
echo ""
echo -e "${CYAN}Menjalankan semua service...${NC}"
chmod +x scripts/*.sh
docker compose up -d --build

# Tunggu portal ready baru nginx bisa connect
echo -e "${CYAN}Menunggu portal siap...${NC}"
sleep 20

# Pastikan nginx terhubung ke network yang benar
NETWORK_NAME=$(docker network ls --filter name=devplatform --format "{{.Name}}" | head -1)
if [ -n "$NETWORK_NAME" ]; then
  docker network connect "$NETWORK_NAME" nginx-proxy 2>/dev/null || true
fi

# Restart nginx supaya load config terbaru
docker compose restart nginx
sleep 3

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "IP-VPS-mu")

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ================================================"
echo "  ✓ Instalasi berhasil!"
echo "  ================================================"
echo -e "${NC}"
echo -e "${BOLD}Akses Platform:${NC}"
echo -e "  Via domain  : ${CYAN}http://$DOMAIN${NC}"
echo -e "  Via IP      : ${CYAN}http://$SERVER_IP${NC} (redirect ke domain)"
echo ""
echo -e "${BOLD}Login Default:${NC}"
echo -e "  Admin  : username ${YELLOW}$ADMIN_USERNAME${NC}  / password ${YELLOW}(yang kakak set saat install)${NC}"
echo -e "  User 1 : username ${YELLOW}user1${NC}  / password ${YELLOW}user1234${NC}"
echo ""
echo -e "${BOLD}Kredensial Database (simpan baik-baik!):${NC}"
echo -e "  PostgreSQL password : ${YELLOW}$PG_PASS${NC}"
echo -e "  MySQL root password : ${YELLOW}$MYSQL_ROOT_PASS${NC}"
echo ""
echo -e "${BOLD}Web UI Database & File:${NC}"
echo -e "  phpMyAdmin (MySQL)   : ${CYAN}https://mysql.$DOMAIN${NC}  (root / $MYSQL_ROOT_PASS)"
echo -e "  pgAdmin (PostgreSQL) : ${CYAN}https://pgadmin.$DOMAIN${NC}"
echo -e "    Login email      : ${YELLOW}$PGADMIN_EMAIL${NC}"
echo -e "    Login password   : ${YELLOW}$PGADMIN_PASSWORD${NC}"
echo -e "  File Browser         : ${CYAN}https://files.$DOMAIN${NC}"
echo -e "    Login pertama    : ${YELLOW}admin / admin${NC}  ${RED}(WAJIB ganti password setelah login!)${NC}"
echo ""
echo -e "${YELLOW}Langkah selanjutnya (WAJIB):${NC}"
echo -e "  1. Pastikan DNS ${BOLD}$DOMAIN${NC} → ${BOLD}$SERVER_IP${NC} sudah aktif"
echo -e "  2. Aktifkan HTTPS  : ${CYAN}sudo bash scripts/setup-https.sh${NC}"
echo -e "  3. Pasang backup   : ${CYAN}sudo bash scripts/install-backup-cron.sh${NC}  (auto backup harian 02:30)"
echo -e "  4. Hardening VPS   : ${CYAN}sudo bash scripts/harden-vps.sh${NC}  (sysctl + SSH key-only)"
echo -e "  5. Tambah user     : ${CYAN}sudo bash scripts/add-user.sh namauser password port${NC}"
echo -e "  6. ${RED}WAJIB: Login ke portal & ganti password admin/user1 (akan otomatis diminta)${NC}"
echo ""
echo -e "${BOLD}Akses DB Remote (DBeaver/Workbench):${NC}"
if [ -n "$DB_REMOTE_IPS" ]; then
  echo -e "  IP whitelist aktif : ${GREEN}$DB_REMOTE_IPS${NC}"
else
  echo -e "  ${YELLOW}Belum ada whitelist IP. Edit nanti dengan ufw allow from <IP> to any port 3306 / 5432${NC}"
fi
echo ""

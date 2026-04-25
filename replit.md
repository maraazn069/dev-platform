# Self-Hosted Dev Platform

Platform coding mandiri berbasis Docker untuk 1-10 user belajar, mirip Replit/VSCode.dev.

## Stack
- **Portal**: Node.js 20 + Express (login, dashboard, admin panel)
- **VS Code**: code-server (linuxserver/code-server) per user via Docker
- **Database**: PostgreSQL 15 + MySQL 8 (shared, tiap user punya schema/db sendiri)
- **Reverse Proxy**: Nginx (Docker container, bukan sistem)
- **SSL**: Let's Encrypt wildcard via Cloudflare DNS challenge
- **Monitoring**: Portainer, Adminer

## Struktur File Penting

```
├── docker-compose.yml          # Semua service (portal, nginx, postgres, mysql, adminer, portainer)
├── Dockerfile.portal           # Build image portal Node.js (port 3000)
├── nginx/nginx.conf            # Template - di-overwrite oleh install-vps.sh
├── server/
│   ├── index.js               # Express app (PORT=3000, /health endpoint)
│   └── routes/
│       ├── api.js             # Projects API (pakai PROTOCOL env untuk URL)
│       ├── auth.js            # Login/logout
│       ├── dashboard.js       # Dashboard user
│       └── admin.js           # Admin panel
├── public/
│   ├── login.html
│   ├── dashboard.html
│   └── admin.html
└── scripts/
    ├── install-vps.sh          # Installer otomatis (generate nginx.conf + .env)
    ├── setup-https.sh          # Setup wildcard SSL via Cloudflare
    ├── add-user.sh             # Tambah user + buat container code-server
    ├── remove-user.sh          # Hapus user
    ├── list-users.sh           # List semua user
    └── create-project.sh       # Buat project folder
```

## Variabel Environment (.env)

| Variabel | Keterangan |
|----------|-----------|
| `DOMAIN` | Domain utama (contoh: dev.netprem.org) |
| `LETSENCRYPT_EMAIL` | Email untuk SSL cert |
| `PROTOCOL` | `http` atau `https` (otomatis diubah oleh setup-https.sh) |
| `SESSION_SECRET` | Secret key session Express |
| `POSTGRES_PASSWORD` | Password PostgreSQL |
| `MYSQL_ROOT_PASSWORD` | Password root MySQL |
| `MYSQL_PASSWORD` | Password user admin MySQL |
| `TZ` | Timezone (default: Asia/Jakarta) |

## Default Login
- Admin: `admin` / `admin123`
- User 1: `user1` / `user1234`

## Cara Deploy ke VPS Baru

### 1. Push ke GitHub (dari Replit terminal)
```bash
git add -A
git commit -m "update: ready for deploy"
git remote set-url origin https://TOKEN@github.com/maraazn069/dev-platform.git
git push origin main
```

### 2. Install di VPS (Ubuntu 24.04)
```bash
# Hapus semua kalau reinstall
docker compose down -v 2>/dev/null || true
cd ~ && rm -rf dev-platform

# Clone dan install
git clone https://github.com/maraazn069/dev-platform
cd dev-platform
sudo bash scripts/install-vps.sh
```

### 3. Setup HTTPS (setelah portal jalan)
```bash
cd ~/dev-platform
sudo bash scripts/setup-https.sh
# Butuh Cloudflare API Token (Zone → DNS → Edit)
```

### 4. Tambah User
```bash
cd ~/dev-platform
sudo bash scripts/add-user.sh namauser password123
```

## Catatan Teknis
- Nginx dihandle Docker (bukan sistem nginx) — sistem nginx harus disabled
- Docker network: `dev-platform_devplatform` (auto-detect di add-user.sh)
- Portal healthcheck: `GET /health` → `{"status":"ok"}`
- Nginx tunggu portal healthy sebelum start (`depends_on: service_healthy`)
- Wildcard SSL cert cover semua subdomain `*.DOMAIN` sekaligus
- Setelah HTTPS aktif, portal rebuild otomatis dengan `PROTOCOL=https`

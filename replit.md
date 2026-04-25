# Self-Hosted Dev Platform

## Deskripsi

Platform coding mandiri di VPS sendiri untuk 1-10 user, tujuan belajar. Mirip Replit tapi self-hosted dan gratis.

## Fitur

- Portal login terpusat (halaman login + dashboard user + panel admin)
- VS Code di browser (code-server) per user via subdomain
- Multi-project per user (bisa punya banyak project folder)
- Monitoring resource real-time (CPU, RAM per container user)
- Shared PostgreSQL (tiap user punya schema sendiri)
- Shared MySQL (tiap user punya database sendiri)
- Adminer: Web UI untuk akses database di browser
- Cloudflare Tunnel: akses database dari luar (via tools seperti DBeaver, TablePlus)
- Auto-update containers (Watchtower)
- Docker management UI (Portainer)
- HTTPS gratis via Let's Encrypt

## Arsitektur

```
Client Browser
     │
     ▼
Nginx (HTTPS reverse proxy)
     │
     ├── dev.domainmu.com      → Portal (Node.js Express, port 3000)
     ├── namauser.domainmu.com → code-server user (port 808x)
     └── db-admin.domainmu.com → Adminer (port 8888)
     
Internal Services:
- PostgreSQL (port 5432, localhost only)
- MySQL (port 3306, localhost only)
- Portainer (port 9000, localhost only)

External access ke DB:
- Cloudflare Tunnel → db.domainmu.com → PostgreSQL/MySQL
```

## Halaman Portal

- `/login` — Halaman login (semua user)
- `/dashboard` — Dashboard user (list project, info DB, ganti password)
- `/admin` — Panel admin (monitoring resource, kelola user & project)

## Struktur File

```
├── server/
│   ├── index.js              # Express app utama
│   ├── data/users.json       # Database user portal (auto-generated)
│   └── routes/
│       ├── auth.js           # Login, logout, ganti password
│       ├── dashboard.js      # Dashboard user
│       ├── admin.js          # CRUD user, project management
│       └── api.js            # Docker stats, DB info, projects API
├── public/
│   ├── login.html            # Halaman login
│   ├── dashboard.html        # Dashboard user
│   └── admin.html            # Panel admin dengan monitoring
├── docker-compose.yml        # Portal + Nginx + PostgreSQL + MySQL + Adminer + Portainer
├── Dockerfile.portal         # Image Docker untuk portal
├── nginx/nginx.conf          # Reverse proxy config
├── .env.example              # Template environment
└── scripts/
    ├── setup.sh              # Setup VPS baru (Docker, Nginx, firewall)
    ├── add-user.sh           # Tambah user (container + PG schema + MySQL DB)
    ├── remove-user.sh        # Hapus user
    ├── list-users.sh         # List user aktif
    ├── create-project.sh     # Buat folder project baru
    ├── init-postgres.sql     # Init script PostgreSQL
    └── init-mysql.sql        # Init script MySQL
```

## Akun Default Admin

- Username: `admin`
- Password: `admin123` (WAJIB diganti setelah deploy)

## Dependencies

- Node.js 20
- express, express-session, bcryptjs, uuid

## User Preferences

- Bahasa komunikasi: Indonesia
- Tujuan: Belajar, bukan komersial
- Target: 1-10 user, VPS 4 vCPU / 56 GB RAM

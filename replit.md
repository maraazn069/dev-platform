# Self-Hosted Dev Platform

## Deskripsi

Project ini adalah kumpulan file konfigurasi dan script untuk membangun platform coding mandiri di VPS sendiri, mirip Replit, untuk 1-10 orang tujuan belajar.

## Arsitektur

- **Replit App** (server/index.js): Dashboard panduan setup berbasis Express + HTML statis, port 5000
- **VPS Deployment**: Docker Compose + code-server (VS Code di browser) per user + Nginx reverse proxy + Let's Encrypt HTTPS

## Struktur File

```
├── server/index.js          # Express server untuk dashboard panduan
├── public/index.html        # Halaman dashboard panduan (UI)
├── docker-compose.yml       # Service Docker untuk VPS (Nginx, Portainer, Watchtower)
├── nginx/nginx.conf         # Konfigurasi reverse proxy Nginx
├── .env.example             # Template environment variables
├── scripts/
│   ├── setup.sh             # Install Docker, Nginx, firewall di VPS baru
│   ├── add-user.sh          # Tambah user baru (buat container code-server)
│   ├── remove-user.sh       # Hapus user
│   └── list-users.sh        # Lihat daftar user aktif
└── README.md                # Panduan lengkap deploy ke VPS
```

## Cara Pakai

### Di Replit (preview dashboard)
- App berjalan di port 5000 dan menampilkan panduan setup

### Deploy ke VPS
1. Push repo ke GitHub
2. Clone di VPS: `git clone https://github.com/USERNAME/REPO`
3. Setup: `sudo bash scripts/setup.sh`
4. Isi config: `cp .env.example .env && nano .env`
5. Jalankan: `docker compose up -d`
6. Tambah user: `sudo bash scripts/add-user.sh namauser`

## Dependencies

- Node.js 20
- express ^4.18.2

## User Preferences

- Bahasa komunikasi: Indonesia
- Tujuan: Belajar, bukan komersial
- Target: 1-10 user
- VPS: 4 vCPU / 56 GB RAM, Ubuntu

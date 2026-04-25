# 📘 Perintah Penting — Dev Platform

Catatan lengkap perintah yang sering dipakai untuk mengelola platform.
Domain produksi: **dev.netprem.org** | VPS: **20.200.209.228** | GitHub: **maraazn069/dev-platform**

---

## 1️⃣ Push Update dari Replit ke GitHub

Lakukan ini **setiap kali ada perubahan code di Replit** yang ingin di-deploy ke VPS.

### Cara Cepat (lewat tombol Git di Replit)
1. Buka tab **Git** di sidebar kiri Replit (icon cabang).
2. Tulis pesan commit, contoh: `update tampilan database`
3. Klik **Commit & Push**.

### Cara Manual (lewat Replit Shell)
```bash
# Lihat file apa saja yang berubah
git status

# Tambah semua perubahan
git add .

# Commit dengan pesan jelas
git commit -m "deskripsi perubahan singkat"

# Push ke GitHub branch main
git push origin main
```

### Kalau Push Ditolak (push protection / secret terdeteksi)
GitHub bisa menolak kalau ada token/password ke-detect. Solusi:
```bash
# Pastikan attached_assets/ ada di .gitignore (folder ini sering ada token lama)
echo "attached_assets/" >> .gitignore

# Hapus dari staging kalau sudah ter-track
git rm -r --cached attached_assets/ 2>/dev/null

git add .gitignore
git commit -m "exclude attached_assets"
git push origin main
```

---

## 2️⃣ Pull Update dari GitHub ke VPS (via SSH)

Lakukan ini di **VPS** setelah push ke GitHub.

### Login SSH ke VPS
```bash
ssh user@20.200.209.228
# atau pakai username Azure kamu
```

### Pull Perubahan Terbaru
```bash
cd ~/dev-platform

# Lihat ada update apa
git fetch origin
git log HEAD..origin/main --oneline

# Pull (kalau ada perubahan di .env yang konflik, backup dulu)
git pull origin main
```

### Kalau Ada Konflik Lokal
```bash
# Cek file mana yang konflik
git status

# Backup lokal lalu reset (HATI-HATI: perubahan lokal di VPS akan hilang!)
git stash
git pull origin main
git stash pop   # restore perubahan lokal kalau perlu
```

---

## 3️⃣ Reinstall / Update Server di VPS

### 🔄 Opsi A — Update Cepat (data DB & user TIDAK hilang)
Pakai ini kalau cuma update code/UI/config kecil.
```bash
cd ~/dev-platform
git pull origin main

# Stop semua container (data volume tetap aman)
sudo docker compose down

# Rebuild image yang berubah (portal biasanya)
sudo docker compose build portal

# Pull image baru kalau ada (phpmyadmin, pgadmin, dll)
sudo docker compose pull

# Start ulang semua
sudo docker compose up -d

# Cek status
sudo docker ps
sudo docker logs devplatform-portal --tail 30
```

### 🆕 Opsi B — Reinstall Bersih (⚠️ HAPUS semua data DB & user!)
Pakai ini kalau mau install ulang dari nol.
```bash
cd ~/dev-platform
git pull origin main

# Hapus semua container + volume (data DB, project user HILANG semua)
sudo docker compose down -v

# Hapus folder data lama kalau perlu
sudo rm -rf server/data/users.json

# Install ulang (akan tanya domain, password DB, dll)
sudo bash scripts/install-vps.sh

# Setup HTTPS (butuh Cloudflare API token Zone.DNS)
sudo bash scripts/setup-https.sh
```

### 🔧 Opsi C — Update Saja + Tambah Service Baru
Pakai ini kalau ada service baru di docker-compose (mis. phpmyadmin/pgadmin baru ditambah).
```bash
cd ~/dev-platform
git pull origin main

# Tambah env baru (kalau perlu, contoh PGADMIN_PASSWORD)
grep -q "PGADMIN_PASSWORD" .env || echo "PGADMIN_PASSWORD=$(openssl rand -base64 16)" | sudo tee -a .env
grep -q "PGADMIN_EMAIL" .env || echo "PGADMIN_EMAIL=admin@netprem.org" | sudo tee -a .env

# Catat password yang di-generate!
grep PGADMIN .env

# Stop, pull image baru, start
sudo docker compose down
sudo docker compose pull
sudo docker compose up -d --build

# Update nginx config supaya subdomain baru ke-route
sudo bash scripts/setup-https.sh
```

---

## 4️⃣ Tambah / Hapus User (⭐ Sekarang dari Admin Panel — No SSH!)

Mulai versi **multi-DB per user**, semua dilakukan dari **Admin Panel di browser**:

1. Login admin di https://dev.netprem.org → menu **Panel Admin**
2. Klik **➕ Tambah User**, isi username + nama + password (+ email opsional)
3. Tunggu ~10 detik (portal otomatis: bikin container code-server, generate password
   MySQL & PostgreSQL random, bikin database `<username>_default`, register subdomain
   nginx, reload nginx)
4. Setelah sukses, **muncul kredensial DB di modal** — copy & kasih ke user
5. User login → buka dashboard → tab **Database Saya** untuk lihat sendiri

### Tombol per User di Admin Panel
| Tombol | Fungsi |
|--------|--------|
| **+ Project** | Tambah folder project baru di code-server user |
| **🔑** | Reset password login portal |
| **🐘 DB** | Lihat password MySQL & PostgreSQL user (untuk troubleshoot) |
| **⚙️ Repair DB** | (muncul kalau user lama belum punya kredensial DB) Generate ulang password DB |
| **Hapus** | Hapus user + container + database MySQL + database PostgreSQL + folder project — **PERMANEN** |

### Manual via SSH (Hanya untuk Emergency)
Kalau admin panel down, masih bisa manual:
```bash
# Tambah user manual (cara lama — tidak generate kredensial DB)
cd ~/dev-platform
sudo bash scripts/add-user.sh namauser passwordnya 8082

# Setelah portal up lagi, klik "Repair DB" di admin panel untuk generate kredensial
```

### Akses Database Remote dari Laptop
Setiap user dapat akses MySQL & PostgreSQL dari laptop (DBeaver, MySQL Workbench, psql, dll):

| Field | MySQL | PostgreSQL |
|-------|-------|------------|
| Host | `dev.netprem.org` | `dev.netprem.org` |
| Port | `3306` | `5432` |
| User | `<username>` | `<username>` |
| Password | (di dashboard) | (di dashboard) |
| Default DB | `<username>_default` | `<username>_default` |

⚠️ Pastikan firewall VPS allow port `3306` & `5432` (otomatis di-set oleh `install-vps.sh`).
Cek dengan:
```bash
sudo ufw status | grep -E "3306|5432"
```

### Auto-Login phpMyAdmin
Di dashboard user, klik **🚀 Buka phpMyAdmin (auto-login)** — browser akan langsung
masuk tanpa perlu isi username/password. Dibuat dengan auto-submit form ke
`mysql.dev.netprem.org` pakai kredensial user.

### pgAdmin (Manual Add Server)
pgAdmin tidak support SSO (kena CSRF), jadi user harus:
1. Klik **🚀 Buka pgAdmin (instruksi)** di dashboard → halaman tampil step-by-step
2. Login pgAdmin pakai admin email/password (sama untuk semua user)
3. Right-click `Servers` → Register → Server → isi host/port/user/password sesuai instruksi

---

## 5️⃣ Cek Status & Debug

### Cek Semua Container
```bash
sudo docker ps                          # yang running
sudo docker ps -a                       # semua (termasuk yang stop)
sudo docker stats --no-stream           # CPU & RAM tiap container
```

### Lihat Log
```bash
# Portal (Express)
sudo docker logs devplatform-portal --tail 50 -f

# Nginx
sudo docker logs nginx-proxy --tail 50 -f

# PostgreSQL
sudo docker logs devplatform-postgres --tail 30

# MySQL
sudo docker logs devplatform-mysql --tail 30

# phpMyAdmin
sudo docker logs devplatform-phpmyadmin --tail 30

# pgAdmin
sudo docker logs devplatform-pgadmin --tail 30

# Code-server user tertentu
sudo docker logs codeserver-user1 --tail 30
```

### Restart Service Tertentu
```bash
sudo docker restart devplatform-portal
sudo docker restart nginx-proxy
sudo docker compose restart phpmyadmin pgadmin
```

### Test HTTPS dari VPS
```bash
curl -I https://dev.netprem.org
curl -I https://mysql.dev.netprem.org
curl -I https://pgadmin.dev.netprem.org
```

---

## 6️⃣ Database — Akses & Backup

### Lihat Password DB
```bash
cat ~/dev-platform/.env | grep -E "POSTGRES|MYSQL|PGADMIN"
```

### Akses CLI Langsung
```bash
# PostgreSQL sebagai admin
sudo docker exec -it devplatform-postgres psql -U postgres -d devplatform

# MySQL sebagai root
sudo docker exec -it devplatform-mysql mysql -uroot -p
```

### Backup Database
```bash
# PostgreSQL backup
sudo docker exec devplatform-postgres pg_dumpall -U postgres > backup_pg_$(date +%F).sql

# MySQL backup semua database
sudo docker exec devplatform-mysql mysqldump -uroot -p --all-databases > backup_mysql_$(date +%F).sql
```

### Restore Database
```bash
# PostgreSQL restore
cat backup_pg_2026-04-25.sql | sudo docker exec -i devplatform-postgres psql -U postgres

# MySQL restore
cat backup_mysql_2026-04-25.sql | sudo docker exec -i devplatform-mysql mysql -uroot -p
```

---

## 7️⃣ SSL / HTTPS Renewal

Sertifikat Let's Encrypt valid 90 hari. Auto-renew sudah aktif (tanggal 1 & 15 setiap bulan via cron).

### Cek Status Sertifikat
```bash
sudo certbot certificates
```

### Renew Manual (kalau perlu)
```bash
sudo certbot renew --dry-run    # test dulu
sudo certbot renew              # renew beneran
sudo docker restart nginx-proxy # reload nginx
```

---

## 8️⃣ URL Penting

| Service | URL |
|---------|-----|
| 🌐 Portal Login | https://dev.netprem.org |
| 👤 Dashboard User | https://dev.netprem.org/dashboard |
| 🛠️ Admin Panel | https://dev.netprem.org/admin |
| 💻 VS Code User | https://USERNAME.dev.netprem.org |
| 🐬 phpMyAdmin | https://mysql.dev.netprem.org |
| 🐘 pgAdmin | https://pgadmin.dev.netprem.org |
| 🐳 Portainer | http://20.200.209.228:9000 (SSH tunnel only) |

---

## 9️⃣ Login Default (Ganti Setelah Install!)

| Akun | Username | Password |
|------|----------|----------|
| Admin Portal | `admin` | `admin123` |
| User Demo | `user1` | `user1234` |

⚠️ **WAJIB** ganti password ini setelah login pertama via menu Pengaturan Akun di dashboard.

---

## 🔟 Troubleshooting Cepat

### Portal tidak bisa diakses
```bash
sudo docker logs devplatform-portal --tail 50
sudo docker compose restart portal
```

### Nginx error / 502 Bad Gateway
```bash
sudo docker logs nginx-proxy --tail 50
# Cek nginx.conf valid
sudo docker exec nginx-proxy nginx -t
sudo docker compose restart nginx
```

### HTTPS tidak jalan / sertifikat error
```bash
sudo certbot certificates
sudo bash scripts/setup-https.sh   # regenerate config
```

### Database tidak bisa connect dari code-server
```bash
# Pastikan container di network yang sama
sudo docker network inspect dev-platform_devplatform | grep Name

# Test ping antar container
sudo docker exec codeserver-user1 ping -c 2 devplatform-postgres
```

### Disk penuh
```bash
df -h
sudo docker system prune -a --volumes   # ⚠️ hapus image/volume tidak terpakai
```

---

## 🆘 Reset Password Lupa

### Reset Password Admin Portal
```bash
ssh user@20.200.209.228
cd ~/dev-platform
sudo nano server/data/users.json
# Hapus user admin, restart portal — admin akan dibuat ulang dengan default
sudo docker restart devplatform-portal
```

### Reset Password Database
```bash
# Edit .env lalu restart container DB (data tetap aman selama volume tidak dihapus)
sudo nano ~/dev-platform/.env
sudo docker compose restart postgres mysql
```

---

## 📝 Catatan Keamanan

- File `.env` **JANGAN** di-commit ke GitHub (sudah ada di `.gitignore`)
- Folder `attached_assets/` **JANGAN** di-commit (sering ada secret/token)
- Backup `.env` ke tempat aman (password manager)
- Backup folder `/opt/devplatform/data/` rutin (data project user)
- Backup database rutin (lihat bagian 6)
- Ganti password default `admin` & `user1` setelah install pertama

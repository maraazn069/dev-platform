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

## 3️⃣ Install / Reinstall / Update Server di VPS

### 🆕 Opsi 0 — VPS BARU dari Nol (Fresh Ubuntu 22.04 / 24.04)
Pakai ini kalau VPS Azure baru dibuat (belum pernah ada Docker / dev-platform).
**Support: Ubuntu 22.04 LTS (Jammy) & 24.04 LTS (Noble)** — script otomatis install
Docker via repo resmi, jadi versi Ubuntu mana saja yang masih supported jalan.
```bash
# 1. SSH login ke VPS
ssh root@20.200.209.228

# 2. Update sistem dasar + install Git
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget

# 3. Clone repo dari GitHub (dapat versi terbaru otomatis)
cd ~
git clone https://github.com/maraazn069/dev-platform.git
cd dev-platform

# 4. Jalankan installer (otomatis install Docker, generate .env, build container)
#    Script akan tanya: domain, email admin, password admin awal, dll
sudo bash scripts/install-vps.sh

# 5. Pastikan DNS Cloudflare sudah aktif:
#    A   dev.netprem.org      → 20.200.209.228
#    A   *.dev.netprem.org    → 20.200.209.228 (wildcard untuk subdomain user)
#    Cek: nslookup dev.netprem.org

# 6. Aktifkan HTTPS wildcard (butuh Cloudflare API Token: Zone.DNS Read+Edit)
sudo bash scripts/setup-https.sh

# 7. Hardening sekali jalan (fail2ban, sysctl, disable root SSH, dll)
sudo bash scripts/harden-vps.sh

# 8. Pasang cron backup harian otomatis
sudo bash scripts/install-backup-cron.sh

# 9. Cek semua service hidup
sudo docker ps
curl -I https://dev.netprem.org
curl -I https://files.dev.netprem.org
```
Setelah selesai, **semua login pakai 1 password admin** yang kakak ketik saat install:

| Service | URL | Username/Email |
|---|---|---|
| Portal | `https://dev.netprem.org` | `admin` |
| File Browser | `https://files.dev.netprem.org` | `admin` |
| pgAdmin | `https://pgadmin.dev.netprem.org` | `admin@dev.netprem.org` (email, bukan "admin") |
| phpMyAdmin | `https://mysql.dev.netprem.org` | `root` (paksaan dari MySQL) |
| PostgreSQL remote | `20.200.209.228:5432` | `postgres` |
| MySQL remote | `20.200.209.228:3306` | `root` |

⚠️ **Tidak ada lagi `admin/admin` default** — installer langsung set password admin ke semua service di atas.

---

### 🔄 Opsi A — Update Cepat (data DB & user TIDAK hilang)
Pakai ini kalau cuma update code/UI/config kecil.
```bash
cd ~/dev-platform
git pull origin main

# Stop semua container (data volume tetap aman)
sudo docker compose down

# Rebuild image yang berubah (portal biasanya)
sudo docker compose build portal

# Pull image baru kalau ada (phpmyadmin, pgadmin, filebrowser, dll)
sudo docker compose pull

# Start ulang semua
sudo docker compose up -d

# Kalau ada service baru di compose (mis. filebrowser), nginx perlu di-update
sudo bash scripts/setup-https.sh

# Cek status
sudo docker ps
sudo docker logs devplatform-portal --tail 30
```

---

### 🆕 Opsi B — Reinstall Bersih (⚠️ HAPUS semua data DB & user!)
Pakai ini kalau mau install ulang dari nol di VPS yang sudah pernah ada dev-platform.
**SEMUA database, project user, audit log, dan file workspace akan HILANG.**
```bash
cd ~/dev-platform

# 1. (OPSIONAL TAPI SANGAT DISARANKAN) backup dulu sebelum hapus
sudo bash scripts/backup.sh
ls -lh /opt/devplatform/backups/  # verifikasi backup ada

# 2. Tarik update terbaru dari GitHub
git pull origin main

# 3. Hapus semua container + volume (data DB, project user HILANG semua)
sudo docker compose down -v

# 4. Hapus folder data user + audit log + project list
sudo rm -rf server/data/users.json
sudo rm -rf server/data/audit.log
sudo rm -rf server/data/projects.json
sudo rm -rf /opt/devplatform/data/*

# 5. (OPSIONAL) hapus .env supaya re-generate password baru
sudo mv .env .env.backup-$(date +%Y%m%d) 2>/dev/null

# 6. Install ulang (akan tanya domain, password DB, dll)
sudo bash scripts/install-vps.sh

# 7. Setup HTTPS (butuh Cloudflare API token Zone.DNS Read+Edit)
sudo bash scripts/setup-https.sh

# 8. Cek hasil
sudo docker ps
curl -I https://dev.netprem.org
curl -I https://files.dev.netprem.org
```
Setelah reinstall semua login pakai 1 password yang kakak set saat installer (lihat tabel di Opsi 0).

---

### ⚡ Opsi WIPE — Hapus TOTAL & Install Ulang (1 blok perintah)
**Untuk reset bersih dari nol — copy-paste 1x jadi tinggal jalan.**
⚠️ SEMUA database, file user, sertifikat HTTPS, dan .env akan HILANG. Backup dulu kalau perlu.

**PENTING:** Login VPS pakai user biasa (BUKAN root) supaya `git` gak bikin file `.git/objects` jadi milik root. Kalau kakak SSH-nya pakai `root`, ganti `$(whoami):$(whoami)` di bawah jadi `root:root`.

```bash
# Step 1: Update kode dari GitHub DULU (TANPA sudo, supaya .git tetap milik user)
cd ~/dev-platform
git checkout -- scripts/ 2>/dev/null   # buang local changes pada script (kalau ada)
git pull origin main

# Step 2: Stop semua container + hapus data lama
sudo bash scripts/backup.sh 2>/dev/null
sudo docker compose down -v --remove-orphans 2>/dev/null
sudo docker rm -f $(sudo docker ps -aq --filter "label=devplatform.user") 2>/dev/null
sudo docker rmi -f devplatform-codeserver:latest 2>/dev/null
sudo docker volume prune -f && sudo docker network prune -f
sudo rm -rf server/data/users.json server/data/audit.log server/data/projects.json /opt/devplatform/data/* /opt/devplatform/letsencrypt/*
sudo mv .env .env.backup-$(date +%Y%m%d-%H%M) 2>/dev/null

# Step 3: Pastikan .git tetap milik user (jaga-jaga)
sudo chown -R $(whoami):$(whoami) ~/dev-platform/.git

# Step 4: Install ulang
sudo bash scripts/install-vps.sh
sudo bash scripts/setup-https.sh
```
Setelah selesai, login pakai 1 password admin (lihat tabel di Opsi 0).

**📧 Tentang email admin:** boleh pakai email apa aja (gmail, yahoo, dll), gak harus dari domain. Contoh: `maraazn069@gmail.com` valid. Email cuma dipakai buat login pgAdmin dan kontak.

---

### 🆘 Opsi CSP-FIX — Tombol di Admin/Dashboard tidak bisa diklik (Browser Console: CSP violation)
Kalau tombol "Ganti Password", "Keluar", "Tambah User", "Refresh", dll **tidak ada
respon** saat diklik, dan di DevTools Console muncul:
```
Executing inline event handler violates the following Content Security Policy
directive 'script-src-attr 'none''.
```
Itu karena helmet CSP terlalu ketat (block semua `onclick=` inline). Fix sudah ada
di server/index.js terbaru (allow `'unsafe-hashes'`). Update VPS:
```bash
cd ~/dev-platform
git pull origin main
sudo docker compose build portal
sudo docker compose up -d portal
sudo docker logs devplatform-portal --tail 10
# Refresh browser dengan Ctrl+Shift+R supaya cache CSP lama hilang
```

---

### 🆘 Opsi nginx-FIX — nginx-proxy stuck "Restarting" / browser ERR_CONNECTION_REFUSED
Kalau install sukses tapi `dev.netprem.org` browser nya **ERR_CONNECTION_REFUSED**,
biasanya nginx-proxy crash di startup karena coba resolve hostname container yg
belum siap. Cek dulu:
```bash
sudo docker ps | grep nginx-proxy        # status: harus "Up", bukan "Restarting"
sudo docker logs nginx-proxy --tail 30   # cek error message
```
Kalau lihat error `host not found in upstream "devplatform-..."` → itu bug DNS
resolution. **Fix permanen sudah ada di script terbaru** (pakai variable proxy_pass).
Jalankan:
```bash
cd ~/dev-platform
git pull origin main

# Re-generate nginx config dengan template baru (tanpa hapus data!)
# Cara paling cepat: hapus file nginx config + restart nginx
sudo rm -f nginx/nginx.conf

# Re-generate nginx.conf dari template (extract dari install-vps.sh tanpa hapus apa-apa)
DOMAIN=$(grep "^DOMAIN=" .env | cut -d= -f2)
sudo bash -c "sed -n '/cat > nginx\/nginx.conf << .NGINXEOF./,/^NGINXEOF$/p' scripts/install-vps.sh | sed '1d;\$d' | sed 's|__DOMAIN__|$DOMAIN|g' > nginx/nginx.conf"

# Restart nginx
sudo docker compose restart nginx
sudo docker ps | grep nginx-proxy        # harus "Up", bukan "Restarting"
sudo docker logs nginx-proxy --tail 10   # tidak boleh ada error

# Tes akses
curl -I http://dev.netprem.org           # harus 200 atau 301
```

**Atau cara paling sederhana — re-run install-vps.sh** (data DB & user TIDAK hilang
karena volume tetap aman, kecuali kakak `compose down -v`):
```bash
cd ~/dev-platform
git pull origin main
sudo bash scripts/install-vps.sh    # akan overwrite nginx.conf dengan versi terbaru
```

---

### 🆘 Opsi B-FIX — Recovery dari Error "Bad source address" / ".env tidak ditemukan"
Kalau `install-vps.sh` gagal di tengah dengan pesan **`ERROR: Bad source address`**
lalu lanjut **`File .env tidak ditemukan`**, itu karena IP yang kakak input untuk
DB whitelist ada karakter aneh (biasanya `\r` dari paste Windows clipboard, atau
spasi/karakter tersembunyi). Script keluar sebelum sempat bikin `.env`.

**Cara atasi (script terbaru sudah auto-handle, tapi kalau masih kena):**
```bash
cd ~/dev-platform

# 1. Pull versi script terbaru (sudah ada validasi IP + skip yang invalid)
git pull origin main

# 2. Reset firewall yang setengah jadi
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# 3. Hapus file setengah jadi (kalau ada)
sudo rm -f .env nginx/nginx.conf

# 4. Re-run installer — saat ditanya "IP yang boleh konek DB", PILIH SALAH SATU:
#    - Tekan Enter (kosong) saja → bisa edit .env nanti tambah whitelist manual
#    - Ketik IP MANUAL (jangan paste dari Windows!), contoh: 203.0.113.45
#    - Multiple IP: 203.0.113.45,1.2.3.4 (pisahkan koma, TANPA spasi)
sudo bash scripts/install-vps.sh

# 5. Lanjut HTTPS seperti biasa
sudo bash scripts/setup-https.sh
```

**Tips paste IP dari Windows:**
- Jangan langsung Ctrl+V dari Notepad/Word (sering bawa `\r\n`)
- Pakai PowerShell/PuTTY paste lalu hapus karakter di akhir (Backspace 1x sebelum Enter)
- Atau ketik manual paling aman

**Cek .env setelah install berhasil:**
```bash
cat .env | grep -E "DOMAIN|DB_REMOTE|MYSQL_ROOT|POSTGRES"
```

---

### 🔧 Opsi C — Update + Tambah Service Baru (data AMAN)
Pakai ini kalau ada service baru di `docker-compose.yml` (mis. filebrowser, pgadmin, dll baru ditambah).
```bash
cd ~/dev-platform
git pull origin main

# Tambah env baru kalau perlu (contoh untuk pgadmin)
grep -q "PGADMIN_PASSWORD" .env || echo "PGADMIN_PASSWORD=$(openssl rand -base64 16)" | sudo tee -a .env
grep -q "PGADMIN_EMAIL" .env || echo "PGADMIN_EMAIL=admin@netprem.org" | sudo tee -a .env

# Catat password yang di-generate!
grep PGADMIN .env

# Pull image baru + start service baru saja (tidak restart yang lain)
sudo docker compose pull
sudo docker compose up -d                # akan create container baru, skip yang sudah ada

# Update nginx supaya subdomain baru ke-route (mis. files.DOMAIN, pgadmin.DOMAIN)
sudo bash scripts/setup-https.sh

# Verifikasi
sudo docker ps | grep -E "filebrowser|pgadmin"
curl -I https://files.dev.netprem.org
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

⚠️ **Akses DB sekarang DI-WHITELIST per IP** (lebih aman). Hanya IP yang ada di
`DB_REMOTE_IPS` di `.env` yang bisa konek.

**Tambah IP baru ke whitelist:**
```bash
# Cek IP publik laptop kamu (jalankan di laptop, BUKAN di VPS!)
curl ifconfig.me

# Di VPS, tambahkan:
sudo ufw allow from 203.0.113.5 to any port 3306 proto tcp
sudo ufw allow from 203.0.113.5 to any port 5432 proto tcp
sudo ufw reload

# Cek hasilnya
sudo ufw status numbered | grep -E "3306|5432"
```

**Hapus IP dari whitelist:**
```bash
sudo ufw status numbered             # cari nomor rule
sudo ufw delete <nomor>
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

## 6️⃣ Database — Akses & Backup Otomatis

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

### 🔁 Backup Otomatis Harian (REKOMENDASI)
Setelah install platform, daftarkan cron backup sekali saja:
```bash
cd ~/dev-platform
sudo bash scripts/install-backup-cron.sh
```

Setelah dipasang, setiap hari jam **02:30** waktu server otomatis backup:
- Semua database PostgreSQL (`pg_dumpall` → gzip)
- Semua database MySQL (`mysqldump --all-databases` → gzip)
- Folder workspace user `/opt/devplatform/data/` (kecuali `.trash` & `node_modules`)
- Folder portal data (`users.json`, `audit.log`, settings)
- Snapshot `.env` (chmod 600)

**Retention:**
- 7 backup harian terakhir → `/opt/devplatform/backups/daily/`
- 4 backup mingguan (Minggu) → `/opt/devplatform/backups/weekly/`
- 6 backup bulanan (tgl 1) → `/opt/devplatform/backups/monthly/`

**Cek status & jalankan manual:**
```bash
sudo crontab -l                                       # cek cron terdaftar
sudo bash ~/dev-platform/scripts/backup.sh            # jalankan sekarang
ls -lh /opt/devplatform/backups/daily/                # lihat hasil backup
tail -f /var/log/devplatform-backup.log               # lihat log backup
```

### Backup Manual Cepat (kalau perlu sebelum update)
```bash
sudo bash ~/dev-platform/scripts/backup.sh
# Output: /opt/devplatform/backups/daily/<timestamp>/
```

### Restore dari Backup
```bash
# Pilih folder backup
ls /opt/devplatform/backups/daily/
BK=/opt/devplatform/backups/daily/20260425-023000

# Restore PostgreSQL (--clean --if-exists sudah ada di dump)
gunzip -c $BK/postgres-all.sql.gz | sudo docker exec -i devplatform-postgres psql -U postgres

# Restore MySQL (semua database)
gunzip -c $BK/mysql-all.sql.gz | sudo docker exec -i devplatform-mysql mysql -uroot -p$MYSQL_ROOT_PASSWORD

# Restore workspace user
sudo tar -xzf $BK/workspace.tar.gz -C /opt/devplatform/

# Restore data portal (users.json, audit.log)
sudo tar -xzf $BK/portal-data.tar.gz -C ~/dev-platform/server/

# Restart semua container
cd ~/dev-platform && sudo docker compose restart
```

### Copy Backup ke Tempat Aman (offsite)
```bash
# Sync backup ke local laptop via rsync (jalankan di laptop)
rsync -avz --progress user@20.200.209.228:/opt/devplatform/backups/ ~/devplatform-backups/

# Atau ke S3/object storage (perlu aws-cli)
# aws s3 sync /opt/devplatform/backups/ s3://my-bucket/devplatform/
```

---

## 6B️⃣ Hardening VPS (Sekali Pasang)

Setelah install platform, **wajib** jalankan script hardening:
```bash
cd ~/dev-platform
sudo bash scripts/harden-vps.sh
```

Yang dilakukan otomatis:
- ✅ **fail2ban**: ban IP yang gagal login SSH 4× dalam 10 menit (ban 6 jam)
- ✅ **unattended-upgrades**: auto install security patch Ubuntu setiap hari
- ✅ **Docker daemon hardening**: log rotation 10MB×3 file, no-new-privileges, live-restore
- ✅ **sysctl hardening**: SYN flood protection, ICMP redirect off, IP spoof protection
- ✅ **SSH hardening**: disable password auth (HANYA kalau key terdeteksi — aman dari lock-out!)

**Cek hasil hardening:**
```bash
sudo fail2ban-client status sshd                    # lihat IP yang di-ban
sudo systemctl status unattended-upgrades           # cek auto-update aktif
sudo cat /etc/sysctl.d/99-devplatform.conf          # lihat sysctl rules
sudo cat /etc/ssh/sshd_config.d/99-devplatform.conf # lihat SSH config
```

**Unban IP yang ke-ban:**
```bash
sudo fail2ban-client set sshd unbanip 1.2.3.4
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
| 📁 File Browser | https://files.dev.netprem.org (admin only) |
| 🐳 Portainer | http://20.200.209.228:9000 (SSH tunnel only) |

---

## 9️⃣ Akun Admin Tunggal (Unified Login)

Mulai dari versi sekarang, **1 akun admin = 1 username + 1 email + 1 password** untuk SEMUA login admin:
Portal, File Browser, pgAdmin, **phpMyAdmin (root)**, **PostgreSQL remote (postgres)**, dan **MySQL remote (root)**
semuanya pakai password yang sama.

### Setup Pertama
- Installer nanya: username (default `admin`), email (default `admin@<domain>`), password (min 10 char, ketik manual).
- Password ini di-set ke: `ADMIN_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `POSTGRES_PASSWORD`, `PGADMIN_PASSWORD` (semua sama).
- Otomatis di-bootstrap ke File Browser & pgAdmin di akhir install.
- Tersimpan di `.env`.

### Tabel Login Cepat
| Service | URL | Username/Email | Password |
|---|---|---|---|
| Portal | `https://dev.netprem.org` | `admin` (atau yang kakak set) | password admin |
| File Browser | `https://files.dev.netprem.org` | `admin` (sama dgn Portal) | password admin |
| pgAdmin | `https://pgadmin.dev.netprem.org` | **email** yang kakak isi saat install (mis. `maraazn069@gmail.com`) | password admin |
| phpMyAdmin | `https://mysql.dev.netprem.org` | `root` (paksaan MySQL) | password admin |
| PostgreSQL remote | `20.200.209.228:5432` | `postgres` (paksaan PG) | password admin |
| MySQL remote | `20.200.209.228:3306` | `root` (paksaan MySQL) | password admin |

**⚠️ pgAdmin login pakai EMAIL, bukan kata "admin"** — pakai email yang kakak isi waktu installer (kalau pakai gmail ya gmail-nya itu, bukan domain).

### Ganti Password (Auto-Sync)
1. Login ke Portal `https://dev.netprem.org/dashboard`
2. Klik tombol **🔑 Ganti Password**
3. Isi password lama + baru → **Simpan**
4. Otomatis ke-sync ke File Browser & pgAdmin di latar belakang
5. Cek hasil sync di Admin → tab **Audit Log** (cari event `password.sync_admin`)

⚠️ Sync ini hanya jalan kalau yang ganti adalah user dengan role `admin`.

### Lupa Password Admin
```bash
ssh root@20.200.209.228
cd ~/dev-platform
sudo nano .env
# ubah ADMIN_PASSWORD=PasswordBaru12345
sudo rm -f server/data/users.json
sudo docker compose restart portal
sleep 5
sudo docker logs devplatform-portal --tail 5
# Harus muncul: "Admin user created: admin (password dari .env, tidak force-change)"

# Sync ke File Browser & pgAdmin manual
sudo docker compose stop filebrowser
sudo docker run --rm -v dev-platform_filebrowser_db:/database --entrypoint filebrowser \
  filebrowser/filebrowser:s6 users update admin --password "PasswordBaru12345" \
  --database /database/filebrowser.db
sudo docker compose start filebrowser

sudo docker exec devplatform-pgadmin /venv/bin/python /pgadmin4/setup.py update-password \
  --user admin@dev.netprem.org --password "PasswordBaru12345"
```

### Service Lain
- **Portainer** → setup admin sendiri saat buka URL pertama (`http://IP:9000`)
- **User VS Code** → tambah via Admin Panel atau `sudo bash scripts/add-user.sh namauser password port` — user diminta ganti password saat login pertama. Akses VS Code: `https://namauser.dev.netprem.org`
- Container code-server sekarang sudah terbundle: **unzip, zip, wget, vim, nano, git, python3, nodejs 20, npm, yarn, pnpm, build-essential, sqlite3** — siap pakai tanpa sudo.

---

## 🔟 Troubleshooting Cepat

### `git pull` error: "insufficient permission for adding an object to repository database .git/objects"
Penyebab: ada file di `.git/` yang jadi milik root (gara-gara `sudo git ...` atau `sudo rm -rf` yang nyentuh `.git`).
Fix:
```bash
sudo chown -R $(whoami):$(whoami) ~/dev-platform
sudo chmod -R u+rwX ~/dev-platform/.git
git pull origin main
```

### `git pull` error: "Your local changes to the following files would be overwritten by merge"
Penyebab: installer di run sebelumnya nge-edit file script (`install-vps.sh`/`add-user.sh`/`setup-https.sh`) di tempat, jadi git deteksi konflik.
Fix (buang perubahan lokal, percaya kode di GitHub):
```bash
cd ~/dev-platform
git checkout -- scripts/    # buang local changes di folder scripts
git pull origin main
git log -1 --oneline        # verifikasi commit terbaru
```

### Installer masih tampil versi lama (masih nanya password DB terpisah, dll)
Berarti `git pull` belum benar-benar update file. Cek dulu:
```bash
cd ~/dev-platform
git log -1 --oneline
# Bandingkan hash dengan commit terbaru di GitHub
grep -c "Konfigurasi Database" scripts/install-vps.sh
# HARUS 0 (versi baru) — kalau >0 berarti file masih versi lama, ulangi git pull
```

### Cara nuklir kalau .git rusak parah
```bash
cd ~
mv dev-platform dev-platform.broken-$(date +%s)
git clone https://github.com/maraazn069/dev-platform.git
cd dev-platform
sudo bash scripts/install-vps.sh
```

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

## 1️⃣1️⃣ Fitur Multi-Project (per User)

Setiap user sekarang bisa punya banyak project di code-server-nya sendiri,
dengan tombol **Buat / Rename / Hapus** dari dashboard.

- Akses: dashboard → tab **Project Saya**
- **Buat project**: tombol **+ Project Baru** → nama project (huruf, angka, dash, underscore)
- **Rename**: tombol pensil di kanan project
- **Hapus**: tombol X → modal minta **ketik ulang nama project** (anti misclick) →
  project dipindah ke `.trash/<nama>-<timestamp>/` (soft delete, masih bisa restore)
- **Restore**: tombol pulihkan dari section "Sampah" di dashboard
- **Hapus permanen**: kosongkan `.trash/` dengan
  `sudo rm -rf /opt/devplatform/data/<username>/.trash/*`

Folder fisik: `/opt/devplatform/data/<username>/<project>/`

**Q: Kalau 1 user punya banyak project, VS Code-nya tetap 1 atau dipisah?**
→ Tetap **1 container VS Code** per user (`codeserver-USERNAME`). Semua project ada di sidebar
sebagai folder di `/config/projects/`. User pindah project = klik **File → Open Folder** di VS Code.
Container terpisah per project = boros RAM (1 user = 1×2GB), gak masuk akal untuk 10 user.

**Q: AI di VS Code selain GitHub Copilot?**
Container code-server bisa pasang extension AI gratis/lebih murah. Cara install dari user (gak perlu admin):
1. Buka VS Code user → tab **Extensions** (Ctrl+Shift+X)
2. Cari & install salah satu:
   - **Continue** (`continue.continue`) — open source, bisa pakai Claude/Gemini/OpenAI/Ollama lokal. Konfigurasi: Ctrl+Shift+P → "Continue: Configure"
   - **Codeium** (`Codeium.codeium`) — gratis, mirip Copilot, login via browser
   - **Cody** (`sourcegraph.cody-ai`) — Sourcegraph, gratis tier ada
   - **Tabnine** (`TabNine.tabnine-vscode`) — gratis tier ada
3. API key (Claude/OpenAI/Gemini) diisi di settings extension masing-masing.
4. Untuk **Ollama** (model lokal di VPS), install dulu di host:
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull qwen2.5-coder:7b
   # extension Continue tinggal arahin ke http://host.docker.internal:11434
   ```
   ⚠️ Butuh RAM ekstra ~6-8GB untuk model 7B.

---

## 1️⃣1️⃣B Cara Jalanin Project & Lihat Preview (PHP / Node / Python)

User non-tech sering bingung: "PHP saya gimana jalaninnya? Apa otomatis muncul di subdomain?"
**Jawaban: tidak otomatis — kakak harus klik Run di terminal.** Tapi gampang banget, runtime sudah pre-installed jadi user TIDAK perlu `apt install` apa-apa.

### Apa saja yang sudah pre-installed di setiap container user

| Bahasa / Tool | Versi | Cara cek di terminal |
|---|---|---|
| **PHP** + ekstensi (sqlite, mysql, pgsql, mbstring, xml, zip, gd, curl, intl, bcmath) | 8.x | `php -v` |
| **Composer** (PHP package manager) | latest | `composer --version` |
| **Node.js** + npm + yarn + pnpm | 20.x | `node -v` |
| **Python 3** + pip + venv | 3.x | `python -V` |
| **MySQL client** (`mysql`) | 8.x | `mysql --version` |
| **PostgreSQL client** (`psql`) | latest | `psql --version` |
| **SQLite3**, **Git**, **build-essential**, vim, nano, jq, tree | — | — |

> User **tidak perlu** ngetik `sudo apt install php-mysql` lagi — semua sudah ada.
> Kalau install command muncul di chat AI, ABAIKAN. Itu saran AI yang gak tau image kakak udah pre-baked.

### Cara buka terminal di VS Code (code-server)

1. Buka project user (klik card project di dashboard portal).
2. Di VS Code yg terbuka, tekan **`` Ctrl+`  ``** (Ctrl + tilde) — atau menu **Terminal → New Terminal**.
3. Terminal muncul di bawah. Otomatis ada greeting yg nampilkan versi runtime.

### Jalanin project (cara cepat — pakai shortcut `run`)

```bash
# Di terminal VS Code, masuk ke folder project (kalau belum)
cd /config/projects/keuangan      # ganti 'keuangan' sesuai nama project

# Auto-detect & jalanin (PHP / Node / Python)
run
```

Script `run` otomatis deteksi tipe project:
- Ada `router.php` / `index.php` → `php -S 0.0.0.0:5000 router.php`
- Ada `package.json` → `npm run dev` atau `npm start`
- Ada `manage.py` → Django runserver
- Ada `app.py` / `main.py` → `python app.py` (auto `pip install -r requirements.txt`)
- Ada `index.html` → `python -m http.server 5000`

### Jalanin manual (kalau project butuh setup khusus)

```bash
# PHP — pakai built-in server di port 5000
cd /config/projects/keuangan
php -S 0.0.0.0:5000 router.php
# Atau dengan composer dulu kalau ada composer.json:
composer install
php -S 0.0.0.0:5000

# Node.js
cd /config/projects/web-app
npm install
npm run dev

# Python (Flask/FastAPI)
cd /config/projects/api
pip install -r requirements.txt
python app.py
```

### 🌐 Akses Preview di Browser

**Aturan PENTING:** project HARUS listen di `0.0.0.0` (BUKAN `localhost` atau `127.0.0.1`),
kalau tidak code-server gak bisa proxy ke luar container.

Setelah `run` jalan, buka URL ini di browser (ganti USERNAME & port):
```
https://USERNAME.dev.netprem.org/proxy/5000/
```

Contoh kalau user-nya `budi` dan project jalan di port 5000:
```
https://budi.dev.netprem.org/proxy/5000/
```

Kalau pakai port lain (mis. Vite di 5173), tinggal ganti angkanya:
```
https://budi.dev.netprem.org/proxy/5173/
```

> Code-server otomatis sediain HTTPS proxy ke port apapun yg listen di container.
> Trailing slash `/` di akhir URL **wajib** — kalau gak ada, asset (CSS/JS) bisa pecah.

### Konek ke Database dari project user

Database hostname di dalam container code-server:
- MySQL: `devplatform-mysql` (port 3306)
- PostgreSQL: `devplatform-postgres` (port 5432)

Username & password DB user bisa dilihat di portal: section **Database** → tombol **🔑 Lihat Credentials**.

Contoh PHP konek MySQL:
```php
$pdo = new PDO('mysql:host=devplatform-mysql;dbname=USERNAME_default;charset=utf8mb4',
               'USERNAME', 'PASSWORD_DARI_PORTAL');
```

Contoh dari terminal langsung query:
```bash
mysql -h devplatform-mysql -u USERNAME -p
psql -h devplatform-postgres -U USERNAME -d USERNAME_default
```

### ⚠️ Project tidak otomatis jalan saat user login

Setiap kali code-server container restart (mis. setelah idle timeout / VPS reboot), aplikasi user **mati** dan harus di-`run` ulang dari terminal. Ini normal — code-server itu **editor**, bukan production server.

Kalau mau project user **selalu hidup** sebagai service:
1. Beli/sewa VPS terpisah & deploy proper (cara production)
2. ATAU: pakai PM2 di terminal user (`npm i -g pm2 && pm2 start app.js && pm2 save`).
   ⚠️ PM2 mati waktu container di-restart, jadi gak benar-benar permanent.

Untuk skenario kakak (1-10 user belajar coding), user manual `run` saat butuh testing **adalah behavior yg paling mendekati Replit free tier**.

---

## 1️⃣2️⃣ Audit Log (Siapa Ngapain Kapan)

Semua aksi penting dicatat ke `server/data/audit.log` (JSONL append-only):
- Login sukses & gagal (dengan IP)
- Tambah / hapus user
- Buat / hapus database
- Ganti password
- Buat / hapus / rename project

**Lihat dari Admin Panel:**
1. Login admin → Panel Admin
2. Tab **Audit Log** (auto-refresh 30 detik) — filter berdasarkan user atau aksi

**Lihat raw log dari SSH:**
```bash
tail -f ~/dev-platform/server/data/audit.log              # live
cat ~/dev-platform/server/data/audit.log | tail -100      # 100 entry terakhir

# Filter login gagal
grep '"action":"login_failed"' ~/dev-platform/server/data/audit.log | tail -20
```

**Rotasi audit log** (kalau sudah > 100MB, rotate manual):
```bash
sudo mv ~/dev-platform/server/data/audit.log \
        ~/dev-platform/server/data/audit-$(date +%F).log
sudo docker restart devplatform-portal
```

---

## 1️⃣3️⃣ Kuota Disk per User

Dashboard user menampilkan **Kuota Disk** (dihitung dari `du` real-time terhadap
folder `/opt/devplatform/data/<username>/`). Tidak ada quota enforcement OS-level
(quota XFS), tapi:

- Container code-server dibatasi RAM `CODE_SERVER_MEM` (default 2GB) & CPU `1.5` core
- PIDs limit 300 supaya fork-bomb tidak crash VPS
- Admin bisa lihat penggunaan disk semua user di Panel Admin

Cek manual:
```bash
sudo du -sh /opt/devplatform/data/*/
```

---

## 1️⃣3️⃣B File Browser (Admin Only)

Web UI untuk admin browse, upload, download, edit, dan hapus file di
`/opt/devplatform/data/` (semua workspace user + folder `.trash`) tanpa SSH.

**Akses:**
- Lewat Panel Admin → tombol **🚀 Buka File Browser** (section File Browser),
  ATAU langsung di https://files.dev.netprem.org

**Login pertama:**
- Username & password: sama dengan admin Portal (di `.env` → `ADMIN_USERNAME`/`ADMIN_PASSWORD`).
  Kalau script install belum sempat bikin, jalanin `sudo bash scripts/sync-admin-password.sh`.

⚠️ **Kalau setelah login halaman kosong "It feels lonely here..."**
Itu karena scope user admin gak di-set ke `/srv`. Jalanin script di atas (versi terbaru
sudah otomatis pakai `--scope /srv`), atau manual:
```bash
cd ~/dev-platform
USR=$(sudo grep '^ADMIN_USERNAME=' .env | cut -d= -f2- | tr -d '"')
FB_VOL=$(sudo docker inspect devplatform-filebrowser --format '{{range .Mounts}}{{if eq .Destination "/database"}}{{.Name}}{{end}}{{end}}')
sudo docker stop devplatform-filebrowser
sudo docker run --rm -v "${FB_VOL}":/database --entrypoint /filebrowser \
  filebrowser/filebrowser:v2.30.0 users update "$USR" --scope /srv \
  --database /database/filebrowser.db
sudo docker start devplatform-filebrowser
```
Refresh browser → kakak harusnya liat folder semua user (admin, dll).

**Use case:**
- Restore file user yang ke-delete tidak sengaja (cek folder `.trash/<user>/`)
- Upload starter project / template ke workspace user
- Download project user untuk audit / backup manual
- Edit file config user (mis. `.env` di project) tanpa harus exec ke container
- Cek penggunaan disk per folder

**Reset / fix password admin filebrowser kalau lupa atau gak bisa login:**

⚠️ Image `filebrowser:s6` punya bug: binary-nya BUKAN di `/filebrowser` (issue #5167).
Project ini sekarang pakai image `filebrowser/filebrowser:v2.30.0` (non-s6) yang stabil.

Cara paling cepat (script otomatis baca `.env` & re-create user admin):
```bash
cd ~/dev-platform
sudo bash scripts/sync-admin-password.sh
```

Cara manual kalau script-nya error:
```bash
cd ~/dev-platform
PASS=$(sudo grep '^ADMIN_PASSWORD=' .env | cut -d= -f2-)
USR=$(sudo grep '^ADMIN_USERNAME=' .env | cut -d= -f2-)
USR=${USR:-admin}
FB_VOL=$(sudo docker inspect devplatform-filebrowser --format '{{range .Mounts}}{{if eq .Destination "/database"}}{{.Name}}{{end}}{{end}}')

sudo docker stop devplatform-filebrowser
# WAJIB pakai image v2.30.0 (non-s6), bukan :s6 — di :s6 binary /filebrowser GAK ADA
sudo docker run --rm -v "${FB_VOL}":/database --entrypoint /filebrowser \
  filebrowser/filebrowser:v2.30.0 users rm "$USR" --database /database/filebrowser.db 2>/dev/null || true
sudo docker run --rm -v "${FB_VOL}":/database --entrypoint /filebrowser \
  filebrowser/filebrowser:v2.30.0 users add "$USR" "$PASS" --perm.admin --database /database/filebrowser.db
sudo docker start devplatform-filebrowser
```

**Tambah user kedua di filebrowser** (mis. read-only viewer):
```bash
sudo docker exec devplatform-filebrowser \
  /filebrowser users add viewer "PasswordViewer123" \
  --perm.admin=false --perm.delete=false --perm.modify=false \
  --database /database/filebrowser.db
```

**Hapus / disable filebrowser** (kalau tidak mau dipakai):
```bash
sudo docker compose stop filebrowser
sudo docker compose rm -f filebrowser
# Hapus dari nginx config: hapus block server_name files.DOMAIN; reload nginx
```

---

## 1️⃣3️⃣C Panel Admin — Pengaturan, Backup, & Layanan (No SSH!)

Halaman `https://dev.netprem.org/admin` sekarang punya 3 section baru paling bawah:

### ⚙️ Pengaturan Platform
Edit konfigurasi platform tanpa SSH ke `.env`. Yang bisa diubah dari web:

| Setting | Gunanya | Default |
|---|---|---|
| `IDLE_TIMEOUT_MIN` | Berapa menit container code-server idle sebelum mati otomatis | 60 |
| `CODE_SERVER_MEM` | Batas RAM per container user (mis. `2g`) | 2g |
| `CODE_SERVER_CPUS` | Batas CPU core per container user | 1.5 |
| `CODE_SERVER_PIDS` | Max process per container (anti fork-bomb) | 300 |
| `DB_REMOTE_IPS` | IP/CIDR yang boleh konek ke MySQL/PG dari luar VPS | (kosong = semua) |
| `TZ` | Timezone semua container | Asia/Jakarta |

⚠️ Yang **read-only** dari web (harus SSH edit `.env`):
- `DOMAIN` (ganti = harus regen sertifikat HTTPS)
- `ADMIN_USERNAME`, `ADMIN_EMAIL` (ganti = harus migrate user data)
- `PROTOCOL`, password DB (kepanjangan dampaknya, harus paham resiko)

Setelah klik **💾 Simpan Pengaturan**, beberapa setting baru aktif setelah Portal direstart — klik tombol **🔄 Restart** di section "Layanan" di bawahnya, atau jalankan: `sudo docker compose restart portal`.

### 💾 Backup Database & Workspace
- **Buat Backup Sekarang** — klik tombol, server jalanin pg_dumpall + mysqldump + tar workspace + copy `.env`. Hasil disimpan di `/opt/devplatform/backups/manual/<timestamp>/`. Butuh 1-3 menit tergantung ukuran data.
- **Tabel daftar backup** — semua backup (manual + harian/mingguan/bulanan dari cron) tampil dengan ukuran & list file.
- **⬇ Download** — klik untuk turunin `.tar.gz` ke laptop kakak. Gak perlu SSH/SFTP lagi.
- **🗑 Hapus** — buat hapus backup lama (rotation otomatis dari cron sudah ada, tapi bisa di-trigger manual).

⚠️ **Restore** belum ada di web (resiko terlalu tinggi). Untuk restore:
```bash
# Di VPS, dari folder backup yang sudah didownload ulang ke /tmp/restore/<ts>/
sudo bash scripts/restore.sh /tmp/restore/<ts>/    # TODO: belum dibuat — contact admin
# Atau manual:
sudo gunzip -c /tmp/restore/postgres-all.sql.gz | sudo docker exec -i devplatform-postgres psql -U postgres
sudo gunzip -c /tmp/restore/mysql-all.sql.gz | sudo docker exec -i devplatform-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD"
sudo tar -xzf /tmp/restore/workspace.tar.gz -C /opt/devplatform/
```

### 🔧 Tombol "Repair Container" (Fix 502 Tanpa SSH)

Per user di tabel admin sekarang ada tombol **🔧 Repair Container**. Klik kalau:
- User tiba-tiba 502 di subdomain (container hilang/crash)
- Habis upgrade image code-server (apply image baru ke container existing)
- Container nyangkut/freeze

Apa yang terjadi: server inspect container existing → ambil PASSWORD env → stop+rm → run baru pakai image terbaru. Password code-server dipertahankan, jadi user gak perlu re-login. Memakan ~5 detik.

⚠️ Kalau container sudah ke-hapus total (gak bisa baca PASSWORD-nya), system generate password baru → ditampilkan di alert browser. Catat & kasih ke user.

---

## 1️⃣3️⃣D Backup ke Cloudflare R2 (Disaster Recovery)

Tujuan: kalau VPS mati / pindah VPS / install ulang → 1 command langsung punya semua data lama.

### Setup Sekali (5 menit)

1. Login Cloudflare → R2 → **Create Bucket**: `devplatform-backups`
2. R2 → **Manage R2 API Tokens** → Create Token
   - Permissions: **Object Read & Write**
   - Specify bucket: `devplatform-backups`
   - Save: Access Key ID, Secret Access Key, Account ID
3. Edit `/opt/devplatform/.env`, tambahkan:
   ```
   R2_ACCOUNT_ID=xxxxxxxxxxxx
   R2_ACCESS_KEY=xxxxxxxxxxxx
   R2_SECRET_KEY=xxxxxxxxxxxx
   R2_BUCKET=devplatform-backups
   ```
4. Install awscli + test backup manual:
   ```bash
   sudo apt install -y awscli
   sudo bash scripts/backup-to-r2.sh
   ```
5. Pasang cron (auto backup harian jam 2 pagi):
   ```bash
   sudo bash scripts/install-backup-cron.sh
   ```

### Yang Di-backup
- MySQL semua database (gzipped sql)
- PostgreSQL semua database (gzipped sql)
- Workspace user (`/opt/devplatform/data/`, exclude `node_modules` dll)
- Config (`users.json`, `.env`, `docker-compose.yml`, audit log)
- Nginx site configs
- SSL certs (`/etc/letsencrypt/`)

Retention: simpan 14 hari terakhir + anchor tanggal 1 tiap bulan.

### Restore di VPS Baru / Reinstall

Di VPS baru (atau VPS lama habis reinstall):

```bash
# 1) Clone repo
sudo git clone https://github.com/maraazn069/dev-platform /opt/devplatform
cd /opt/devplatform

# 2) Buat .env minimal yang isinya R2 credentials saja
sudo cp .env.example .env
sudo nano .env   # isi R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET

# 3) Install awscli
sudo apt install -y awscli docker.io docker-compose-plugin

# 4) Restore (akan auto download backup terakhir, restore DB+workspace+config+SSL)
sudo bash scripts/restore-from-r2.sh
# Atau dari host name lain:
RESTORE_FROM_HOST=potato-old sudo bash scripts/restore-from-r2.sh

# 5) Restore akan otomatis: docker compose up -d + recreate semua container code-server
# Selesai. Login portal: https://<DOMAIN>/
```

## 1️⃣3️⃣E Migrasi ke Struktur Subdomain Lengkap (Opsi C)

> Cuma perlu **sekali** kalau VPS lama-mu masih pakai struktur lama
> (`dev.netprem.org` sebagai DOMAIN). Skip kalau install baru — `install-vps.sh`
> sudah pakai struktur Opsi C dari awal.

### Apa Itu Opsi C?
- **Portal**: `https://netprem.org` (apex)
- **VS Code per user**: `https://<user>.netprem.org`
- **Preview project**: `https://<project>.<user>.netprem.org`
   → semua route ke port **3000** dalam container user
   → user jalankan `npm run dev` / `python -m http.server 3000` / dst di project
- **Cert**: `*.netprem.org` (depth-1) + per-user `*.<user>.netprem.org` (depth-2)
- DNS Cloudflare yang harus dipasang:
  - `netprem.org` A → IP VPS (apex)
  - `*.netprem.org` A → IP VPS
  - **per user**: `*.<user>.netprem.org` A → IP VPS  *(satu CNAME wildcard nested per user)*

### Langkah Migrasi

```bash
# 1) Backup dulu (WAJIB!)
cd /opt/devplatform
sudo bash scripts/backup-to-r2.sh

# 2) Update DNS Cloudflare
#    - netprem.org A → IP VPS (kalau belum)
#    - *.netprem.org A → IP VPS (kalau belum)
#    Tambahan:
#    - Per user yg ada (cek di admin panel): *.<user>.netprem.org A → IP VPS
#    Proxy boleh ON, tapi cert request ke LE perlu DNS-01 → token Cloudflare jalan via API.

# 3) Update .env DOMAIN ke apex
sudo nano .env
# Pastikan: DOMAIN=netprem.org   (bukan dev.netprem.org)

# 4) Jalankan migrator
sudo bash scripts/migrate-to-opsi-c.sh
# Script akan:
#   - Re-issue *.netprem.org cert (kalau belum ada)
#   - Mount nginx/users folder ke nginx container
#   - Regenerate nginx.conf dengan include /etc/nginx/users/*.conf
#   - Loop user: request *.<user>.netprem.org cert + tulis user.conf
#   - Restart nginx + portal

# 5) Pasang cert-queue worker (auto issue cert kalau ada user baru)
sudo bash scripts/install-backup-cron.sh
```

### Verifikasi
- Portal: `https://netprem.org` → halaman login
- User test: `https://<user>.netprem.org` → VS Code
- Preview: jalankan `python3 -m http.server 3000` di terminal VS Code,
   buka `https://app.<user>.netprem.org` (kalau project namanya "app")

### Cert Per-User Manual (Kalau Cron Belum Aktif / Mau Buru-Buru)

```bash
sudo bash scripts/provision-user-cert.sh alice
# Output: cert *.alice.netprem.org diterbitkan
# Trigger admin panel klik 🔧 Repair Container untuk regenerate alice.conf
```

### Catatan Limit Let's Encrypt
- LE rate limit: **50 cert/registered-domain/week**.
- Kalau punya 10 user → cuma 10 cert depth-2 + 1 cert wildcard depth-1 = 11 issuance, AMAN.
- Cert auto-renew tiap 60 hari (oleh certbot timer).

### Rollback ke Struktur Lama
Kalau ada masalah, balik ke `dev.<DOMAIN>` style:
1. Restore .env DOMAIN lama
2. `sudo bash scripts/setup-https.sh` (regenerate nginx.conf tanpa include)
3. Hapus mount `nginx/users` dari docker-compose.yml secara manual
4. `sudo docker compose up -d nginx portal`

---

### Update Fitur Tanpa Kehilangan Data

```bash
cd /opt/devplatform
sudo git pull origin main
# Kalau ada update Dockerfile codeserver:
sudo bash scripts/recreate-all-codeserver.sh
# Restart portal aja kalau cuma server-side change:
sudo docker compose restart portal
```
Data user (di `/opt/devplatform/data/` + database volumes) AMAN. Kalau ada doubt, backup manual dulu sebelum git pull:
```bash
sudo bash scripts/backup-to-r2.sh
```

### Diagnose 502 (Kalau Repair Container Gak Cukup)

```bash
sudo bash scripts/diagnose-502.sh test     # cek user spesifik
sudo bash scripts/diagnose-502.sh --all    # cek semua user
```
Output ngasih tau: container ada/jalan, network bener, nginx ada config, dll.

### 🐳 Layanan & Container
List semua container kritis (Portal, Nginx, Postgres, MySQL, pgAdmin, phpMyAdmin, FileBrowser) dengan status real-time + tombol **🔄 Restart** per service. Berguna kalau:
- Nginx ngasih 502 → klik Restart Nginx
- pgAdmin lambat → klik Restart pgAdmin
- File Browser hang → klik Restart File Browser

⚠️ Restart Portal akan bikin halaman ini hang ~10 detik (Portal restart = web admin mati sebentar). Refresh browser setelah 10-15 detik.

---

## 1️⃣3️⃣F Uninstall Total + Install Fresh

> Pakai kalau VPS udah berantakan (bug-bug lama, container conflict, data corrupt) dan
> mau mulai dari nol. Source code repo + cert Let's Encrypt **tetap aman** (kecuali pakai `--nuke`).

### Yang Dihapus
- Semua container `devplatform-*` & `codeserver-*`
- Semua docker volume (mysql_data, postgres_data, codeserver-*-config)
- Semua data user di `/opt/devplatform/data/`
- Semua nginx user conf + cert-queue
- Cron jobs (cert-queue, backup) + log files
- `users.json` di-reset (backup `.uninstalled-*` dibuat otomatis)

### Yang Dipertahankan (Default)
- ✅ Cert Let's Encrypt `/etc/letsencrypt/live/*` (hindari rate-limit 5×/week)
- ✅ `/etc/cloudflare/cloudflare.ini` (token API)
- ✅ File `.env` (password DB tetap sama setelah reinstall)
- ✅ Source code repo di `/opt/devplatform`

### Cara Pakai

```bash
cd /opt/devplatform
sudo git pull origin main          # ambil script uninstall terbaru

# 1) Uninstall (interactive, ketik UNINSTALL untuk konfirmasi)
sudo bash scripts/uninstall-fresh.sh

# 2) Install fresh
sudo bash scripts/install-vps.sh         # bootstrap docker + nginx
sudo bash scripts/setup-https.sh         # issue *.netprem.org cert
sudo bash scripts/migrate-to-opsi-c.sh   # set struktur Opsi C
sudo bash scripts/install-backup-cron.sh # pasang cron cert-queue + backup

# 3) Login portal https://netprem.org → admin/admin → ganti password → tambah user
```

### Mode Nuclear (Hapus Cert + .env Juga)

```bash
sudo bash scripts/uninstall-fresh.sh --nuke
# ⚠️ Cert akan di-issue ulang → kena rate-limit kalau >5×/week
# ⚠️ Password DB akan baru semua → user lama tidak bisa login DB tanpa reset
```

### Skip Konfirmasi (Otomatisasi)

```bash
sudo bash scripts/uninstall-fresh.sh --force
```

---

## 1️⃣3️⃣G Multi-Port Preview (Selain Port 3000)

Default preview project route ke port **3000** (npm run dev, dst). Kalau dev server jalan
di port lain, tambahin suffix `-<port>` di subdomain.

| Subdomain                                 | Route ke port           | Contoh use case                    |
|-------------------------------------------|-------------------------|------------------------------------|
| `myapp.user1.netprem.org`                 | `3000` (default)        | `npm run dev`                      |
| `myapp-8000.user1.netprem.org`            | `8000`                  | `python -m http.server 8000`       |
| `myapp-5173.user1.netprem.org`            | `5173`                  | `vite dev`                         |
| `myapp-8080.user1.netprem.org`            | `8080`                  | `php -S 0.0.0.0:8080`              |
| `api-4000.user1.netprem.org`              | `4000`                  | Backend Express                    |

**Range port valid:** `3000–9999` (nginx regex `[3-9][0-9]{3}`).

**Catatan:**
- Project name harus huruf kecil + angka aja, **tanpa** dash di nama project sendiri
  (karena dash dipakai untuk separator port).
- ❌ TIDAK BISA: `my-app.user1.netprem.org` (dash di nama project akan di-parse sebagai port)
- ✅ BISA: `myapp.user1.netprem.org` atau `myapp-8000.user1.netprem.org`

---

## 1️⃣4️⃣ Force Change Password

User baru (atau yang di-reset password) **wajib ganti password** di login pertama:
- Saat login, langsung di-redirect ke `/change-password-required`
- Tidak bisa akses dashboard sebelum ganti
- Password baru harus lulus policy:
  - Minimal 10 karakter
  - Harus ada huruf besar, kecil, angka, simbol
  - TIDAK boleh sama dengan username
  - TIDAK boleh ulangi karakter sama 4×
  - TIDAK boleh password umum (123456789, password, dll)

User lama yang sudah pernah login akan otomatis diminta ganti hanya kalau admin
me-reset passwordnya.

---

## 📝 Catatan Keamanan

### Wajib Dilakukan
- ✅ File `.env` **JANGAN** di-commit ke GitHub (sudah ada di `.gitignore`)
- ✅ Folder `attached_assets/` **JANGAN** di-commit (sering ada secret/token)
- ✅ Backup `.env` ke tempat aman (password manager)
- ✅ Pasang cron backup harian: `sudo bash scripts/install-backup-cron.sh`
- ✅ Hardening VPS sekali: `sudo bash scripts/harden-vps.sh`
- ✅ Password admin di-set saat install (tidak ada default `admin123` lagi)
- ✅ Tambah user baru via `add-user.sh` atau Panel Admin (user diminta ganti password saat login pertama)
- ✅ Ganti password default File Browser `admin/admin` setelah login pertama
- ✅ Ganti password default Portainer setelah setup pertama
- ✅ Whitelist IP DB di `.env` (`DB_REMOTE_IPS`) — jangan biarkan kosong di production

### Variabel Penting di .env (Cek Setelah Install)
| Variabel | Default | Keterangan |
|----------|---------|-----------|
| `IDLE_TIMEOUT_MIN` | 60 | User di-logout otomatis setelah X menit idle |
| `DB_REMOTE_IPS` | (kosong) | IP yang boleh konek MySQL/PG dari luar |
| `CODE_SERVER_MEM` | 2g | RAM limit per container code-server |
| `CODE_SERVER_CPUS` | 1.5 | CPU limit per container code-server |
| `CODE_SERVER_PIDS` | 300 | PID limit per container (anti fork-bomb) |
| `BACKUP_ROOT` | /opt/devplatform/backups | Lokasi backup |

### Pengamanan Aplikasi (Otomatis Aktif)
- 🔒 CSRF double-submit cookie (semua POST/DELETE diperiksa)
- 🔒 Helmet CSP, HSTS (saat HTTPS), X-Frame-Options
- 🔒 Rate limit login 10×/15 menit per IP
- 🔒 bcrypt cost 12 untuk password storage
- 🔒 Session rolling (renewed setiap request) + idle timeout
- 🔒 Audit log untuk semua aksi sensitif
- 🔒 Soft-delete project (anti misclick, bisa restore dari .trash)
- 🔒 Container resource limits (RAM/CPU/PID)
- 🔒 fail2ban jail SSH (lewat `harden-vps.sh`)

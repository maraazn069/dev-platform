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

### 🐳 Layanan & Container
List semua container kritis (Portal, Nginx, Postgres, MySQL, pgAdmin, phpMyAdmin, FileBrowser) dengan status real-time + tombol **🔄 Restart** per service. Berguna kalau:
- Nginx ngasih 502 → klik Restart Nginx
- pgAdmin lambat → klik Restart pgAdmin
- File Browser hang → klik Restart File Browser

⚠️ Restart Portal akan bikin halaman ini hang ~10 detik (Portal restart = web admin mati sebentar). Refresh browser setelah 10-15 detik.

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

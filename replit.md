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

## Update Sesi (Apr 25, 2026)
### Keamanan Diperkuat
- **Helmet**: security headers (X-Frame-Options, HSTS, X-Content-Type-Options, dll)
- **Rate limit login**: 10 percobaan / 15 menit per IP
- **Session secure**: cookie HttpOnly + SameSite=Lax + Secure (saat HTTPS), regenerate session ID setelah login
- **SESSION_SECRET**: dari env var, di-generate otomatis saat install (`openssl rand -base64 32`)
- **Body size limit**: 1mb

### Fitur Akun User
- Endpoint baru: `/auth/me`, `/auth/change-email`
- Dashboard tampilkan username + email + tombol ubah email/password
- Modal "Ubah Email" minta password verifikasi
- Modal "Ganti Password" auto-clear field setelah sukses

### Database Info Diperbaiki
- Hostname pakai container name: `devplatform-postgres`, `devplatform-mysql` (akses dari code-server)
- Tampilkan contoh perintah `psql`/`mysql` siap copy
- Link Adminer (db-admin.DOMAIN) dari admin panel
- Hapus semua mention "Cloudflare Tunnel" dari UI/script

### Field User Baru
- `email` ditambah ke users.json schema (default kosong, opsional)

## Update Sesi (Apr 25 - Lanjutan)
### Ganti Adminer → phpMyAdmin + pgAdmin
- **phpMyAdmin** (gaya cPanel) untuk MySQL → `https://mysql.DOMAIN`
  - Auto-connect ke `devplatform-mysql`, upload limit 256M
- **pgAdmin** untuk PostgreSQL → `https://pgadmin.DOMAIN`
  - Login dengan email + password (di-set saat install, default admin@local.dev / random)
  - Volume `pgadmin_data` untuk menyimpan koneksi tersimpan
- Nginx route baru: `mysql.DOMAIN` & `pgadmin.DOMAIN` (HTTP + HTTPS)
- Wildcard cert `*.DOMAIN` cover otomatis
- UI portal & dashboard tampilkan tombol "🚀 Buka phpMyAdmin/pgAdmin"
- `.env` baru: `PGADMIN_EMAIL`, `PGADMIN_PASSWORD`

## Update Sesi (Apr 25 - Multi-DB Per User) ⭐ ARSITEKTUR BARU
### Tujuan
Setiap user punya kredensial DB sendiri, bisa create/drop database dari dashboard,
akses remote dari laptop (DBeaver/Workbench), dan auto-login ke phpMyAdmin tanpa isi password.

### Perubahan Infrastruktur
- **Dockerfile.portal** install `docker-cli` + `openssl` → portal bisa exec ke container
  MySQL/Postgres/nginx untuk provision user secara real-time (no manual shell command)
- **docker-compose.yml**:
  - Mount `/var/run/docker.sock` ke portal (kontrol Docker)
  - Mount `/opt/devplatform/data` ke portal (buat folder user)
  - Mount nginx config rw (auto-tambah subdomain user)
  - MySQL & Postgres expose ke `0.0.0.0:3306` & `0.0.0.0:5432` (bind-address 0.0.0.0)
  - Pass `POSTGRES_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `PGADMIN_EMAIL`, `PGADMIN_PASSWORD` ke portal env
- **scripts/install-vps.sh**: ufw allow `3306/tcp` & `5432/tcp`

### Backend Services Baru
- `server/services/dockerExec.js`: helper exec command di container
- `server/services/userManager.js`:
  - `provisionUser({username, password, displayName, email})` — buat user portal +
    generate password MySQL/PG (16 byte random), CREATE USER di kedua DB, buat default
    database `<username>_default`, GRANT ALL, jalankan container code-server, tambah
    nginx subdomain
  - `removeUser(username)` — DROP USER + DROP database semua, hapus container, hapus
    nginx config, hapus folder data, hapus dari users.json
  - `createDatabase(username, type, name)` — buat DB baru `<username>_<name>`, GRANT ALL
  - `dropDatabase(username, type, name)` — DROP DB (default tidak bisa dihapus)
  - `repairUserCredentials(username)` — generate ulang password MySQL/PG untuk user lama
  - `getCredentials(username)`, `safeDbName()`, `isValidName()`
- `server/services/nginxManager.js`: `ensureUserSubdomain(username, port)` — append
  block server `username.DOMAIN` ke nginx config + reload

### Endpoint API Baru
- `GET /api/db/info` → host/port remote + internal + user/password user yg login
- `GET /api/databases` → list database user (mysql + pg)
- `POST /api/databases {type, name}` → buat database baru
- `DELETE /api/databases/:type/:name` → hapus database (default protected)
- `GET /api/launch/phpmyadmin?db=NAME` → halaman auto-submit form login phpMyAdmin
  (browser POST `pma_username` + `pma_password` → user langsung masuk)
- `GET /api/launch/pgadmin` → halaman instruksi connect (pgAdmin tidak support SSO
  karena CSRF token, jadi tampilkan kredensial admin + step-by-step add server)
- `POST /admin/users/repair-db {username}` → regenerate kredensial DB user lama
- `GET /admin/users/:username/credentials` → admin lihat password DB user

### UI Dashboard User (Database Saya)
- Section **Database Saya** dengan card MySQL & PostgreSQL
- Tombol **"+ Buat Database"** modal (pilih type + nama)
- List database dengan tombol **Buka** (auto-login phpMyAdmin) & **Hapus**
- Section **Akses Remote** dengan info host/port/user/password (toggle show/hide
  password, tombol Copy, command CLI siap copy untuk `mysql`/`psql`)
- Tombol launcher **🚀 Buka phpMyAdmin (auto-login)** & **🚀 Buka pgAdmin (instruksi)**

### UI Admin Panel
- Modal **Tambah User** sekarang menampilkan kredensial yang baru di-generate
  (login portal + MySQL pw + PG pw) — admin bisa copy & kasih ke user
- Tombol per user:
  - **🐘 DB** → modal lihat kredensial DB + list database user
  - **⚙️ Repair DB** (muncul kalau `hasDbCredentials = false`, untuk user lama yang
    dibuat sebelum sistem multi-DB)
- Hapus semua referensi `shellCommand` (dulu admin harus copy command ke SSH;
  sekarang portal lakukan semua via docker.sock)

### Konvensi Penamaan Database
- Format: `<username>_<dbname>` (huruf kecil, angka, underscore, max 31 karakter)
- Default DB tiap user: `<username>_default` (auto-create saat provision, tidak bisa
  dihapus — diproteksi server-side)
- **MySQL grant (isolasi ketat)**: `ALL PRIVILEGES ON \`<username>\\_%\`.* TO user`
  — user TIDAK punya CREATE/DROP/SHOW DATABASES di `*.*`. Database dibuat oleh portal
  pakai root account; user cuma bisa CRUD di DB miliknya sendiri.
- **PostgreSQL**: role login WITHOUT CREATEDB. Database dibuat portal pakai postgres
  superuser. Mencegah user bikin DB sembarangan via psql remote.
- Akibatnya: user yg pakai DBeaver/Workbench tidak bisa "DROP DATABASE alice_default"
  walaupun port 3306/5432 publik.

### Hardening Keamanan Tambahan
- `dockerExec.js` pakai `dockerExecStdin()` — SQL dipipe via stdin, bukan via shell
  argument. Tidak ada `sh -c` lagi → no shell injection meskipun SQL berisi karakter aneh.
- `dropDatabase()` validasi `isValidName()` + cek `default` server-side (bukan cuma UI).
- `removeUser()` enumerasi DB aktual dari `information_schema.schemata` & `pg_database`
  pakai pattern `<username>_%` (bukan trust users.json), terminate koneksi PG aktif,
  drop folder data, dan TIDAK menghapus user dari users.json kalau ada error
  (set `deletionPending` flag supaya bisa retry manual).
- pgAdmin admin email/password TIDAK dirender di halaman user — admin dapat lewat
  `GET /admin/pgadmin-credentials` (admin-only) untuk dishare manual ke user.

### Default Login
- Admin: `admin` / `admin123`
- User 1 (lama): `user1` / `user1234` — perlu klik **Repair DB** di admin panel
  supaya dapat kredensial DB

## Update Sesi (Apr 25 - Hardening Komprehensif) ⭐ PRODUCTION READY
### Tujuan
Pengetatan keamanan menyeluruh, fitur multi-project per user, audit log, backup
otomatis, dan hardening VPS.

### Backend Hardening
- **CSRF middleware** (`server/middleware/csrf.js`) — double-submit cookie pattern,
  cookie `devplatform.csrf` (httpOnly:false supaya JS bisa baca), header
  `X-CSRF-Token` wajib di POST/PUT/DELETE. Exempt: `/auth/login`, `/health`, `/csrf-token`
- **Helmet diperketat**: CSP konservatif, HSTS (saat HTTPS), referrerPolicy
- **Session rolling**: cookie diperpanjang setiap request, idle timeout via
  `IDLE_TIMEOUT_MIN` env (default 60 menit) — middleware cek `lastActivity`
- **Body size**: tetap 1MB
- **Bcrypt cost 12** untuk password user (provisionUser, resetPassword)

### Password Policy + Force Change
- `server/services/passwordPolicy.js` `validateStrong({password, username})`:
  - Min 10 char, harus uppercase + lowercase + digit + symbol
  - Tidak boleh berisi username (substring)
  - Tidak boleh repeat char ≥4×
  - Blacklist password umum (top common passwords)
- Default users (admin/admin123, user1/user1234) seeded dengan
  `mustChangePassword=true` saat fresh install. Runtime migration: user lama yang
  belum punya `passwordChangedAt` di-flag `mustChangePassword=true` automatically
- Middleware dashboard cek flag → redirect ke `/change-password-required`
- Halaman `public/change-password-required.html` dengan **live policy checker**
  (warna hijau real-time per requirement)

### Audit Log
- `server/services/auditLog.js` — append-only JSONL ke `server/data/audit.log`
- Logged: login_success, login_failed, logout, user_added, user_removed,
  password_changed, password_reset, db_created, db_dropped, project_created,
  project_renamed, project_deleted, project_restored
- Endpoint admin `GET /admin/audit?limit=100&user=foo&action=login_failed` (paginated)
- Tab **Audit Log** di admin.html, auto-refresh 30 detik, filter by user/action

### Multi-Project per User
- `server/services/projectManager.js`: list/create/rename/softDelete/restore
- Soft delete pindah folder ke `<userdata>/.trash/<name>-<timestamp>/`
- Restore baca isi `.trash/`, pindah balik (skip kalau nama sudah ada)
- Validasi nama: `^[a-zA-Z0-9_-]{1,40}$`, tidak boleh `..`, tidak boleh nama reserved
- Routes `/api/my/projects` (GET list, POST create, PATCH rename, DELETE soft-delete,
  POST `/restore` restore from trash)
- Dashboard UI: section **Project Saya** dengan grid card, tombol create/rename/delete,
  modal konfirmasi delete dengan **typed confirmation** (user harus ketik ulang nama)
- Section **Sampah** menampilkan trash items dengan tombol Pulihkan

### Container Resource Limits (anti-DoS noisy neighbor)
- `userManager.js createCodeServerContainer` tambah flag:
  - `--memory ${CODE_SERVER_MEM:-2g}` & `--memory-swap` sama (no swap leak)
  - `--cpus ${CODE_SERVER_CPUS:-1.5}`
  - `--pids-limit ${CODE_SERVER_PIDS:-300}` (anti fork-bomb)
  - `--security-opt no-new-privileges`
  - `--log-driver json-file --log-opt max-size=10m --log-opt max-file=3`
- `docker-compose.yml`: `deploy.resources.limits` ditambah ke portal (512M/.5cpu),
  postgres (2G/1cpu), mysql (2G/1cpu) + log rotation json-file 10-20MB

### Disk Usage Widget
- `server/services/diskUsage.js` — pakai `du -sb` per user folder
- Endpoint `GET /api/my/disk-usage` (cached 60 detik supaya tidak expensive)
- Dashboard menampilkan **Kuota Disk: X MB** dengan progress bar visual

### Ops Scripts Baru
- `scripts/backup.sh` — pg_dumpall + mysqldump --all-databases + tar workspace
  + tar portal data + copy .env (chmod 600). Retention: 7 daily, 4 weekly (Minggu),
  6 monthly (tgl 1). Output: `/opt/devplatform/backups/{daily,weekly,monthly}/<TS>/`
- `scripts/install-backup-cron.sh` — daftar cron 02:30 daily, pasang logrotate
  untuk `/var/log/devplatform-backup.log` (weekly, 8 file, compress)
- `scripts/harden-vps.sh` — fail2ban (jail SSH 4×/10m), unattended-upgrades
  (auto security patch), `/etc/docker/daemon.json` (log rotation, no-new-privileges,
  live-restore), sysctl (SYN flood, ICMP redirect off, IP spoof), SSH disable
  password auth **HANYA kalau key terdeteksi** (anti lock-out)
- `scripts/install-vps.sh` updated:
  - Prompt **DB_REMOTE_IPS** (whitelist IP)
  - Prompt **IDLE_TIMEOUT_MIN**
  - Auto-install fail2ban + unattended-upgrades
  - Auto-tulis `/etc/docker/daemon.json`
  - UFW: `ufw allow from <IP> to any port 3306/5432` per IP whitelist (BUKAN
    blanket allow 3306/5432) — kalau kosong, port DB tidak terbuka publik
  - chmod 600 `.env` setelah generate
  - Pesan akhir: hint jalankan setup-https + install-backup-cron + harden-vps

### .env.example Baru (Variabel Tambahan)
- `IDLE_TIMEOUT_MIN=60` — idle logout
- `DB_REMOTE_IPS=` — whitelist IP DB remote
- `CODE_SERVER_MEM=2g`, `CODE_SERVER_CPUS=1.5`, `CODE_SERVER_PIDS=300`
- `BACKUP_ROOT=/opt/devplatform/backups`

### File Browser (Admin Only)
- Service `filebrowser` (image `filebrowser/filebrowser:s6`) di docker-compose.yml
- Mount `/opt/devplatform/data:/srv` → admin bisa akses semua workspace user
- Volume `filebrowser_db` (config + auth db) + `filebrowser_config`
- Resource limits: 256M / 0.3 cpu (sangat ringan)
- Akses via subdomain `files.DOMAIN` (nginx route ditambah di install-vps.sh + setup-https.sh)
- Tombol launcher di admin.html section "File Browser" (warna hijau, target=_blank)
- Login pertama default `admin/admin` — image filebrowser/filebrowser:s6 auto-prompt
  ganti password di first login (built-in behavior)
- Use case: restore file user dari `.trash/`, upload template, edit config tanpa SSH

### Migration Notes (Existing VPS)
Saat user `git pull` di VPS lama, untuk dapat fitur baru:
1. `cd ~/dev-platform && git pull origin main`
2. Tambah variabel baru ke `.env` manual atau hapus & re-generate via install-vps.sh
3. `sudo docker compose down && sudo docker compose up -d --build portal`
4. **WAJIB** `sudo bash scripts/install-backup-cron.sh` (sekali)
5. **WAJIB** `sudo bash scripts/harden-vps.sh` (sekali)
6. Re-run `sudo bash scripts/install-vps.sh` (rerun aman, tidak destroy data)
   atau manual `ufw delete allow 3306` dan tambah whitelist per IP
7. Login admin → akan otomatis diminta ganti password (mustChangePassword migrasi
   runtime untuk user yang belum punya `passwordChangedAt`)

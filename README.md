# 🖥️ Self-Hosted Dev Platform

Platform coding mandiri di VPS — VS Code di browser, multi-user, PostgreSQL + MySQL, untuk belajar bareng.

---

## File Apa Saja yang Di-Upload ke GitHub?

**Semua file di-upload, kecuali yang ada di `.gitignore`:**

| Di-upload ✅ | TIDAK di-upload ❌ |
|---|---|
| `docker-compose.yml` | `.env` (berisi password!) |
| `Dockerfile.portal` | `server/data/users.json` (berisi hash password) |
| `nginx/nginx.conf` | `node_modules/` |
| `scripts/*.sh` | |
| `scripts/*.sql` | |
| `server/**` (kode sumber) | |
| `public/**` (tampilan) | |
| `.env.example` (template, aman) | |
| `setup-github.ps1` | |
| `README.md` | |

---

## 🪟 Cara Upload ke GitHub (dari Windows — PowerShell)

### Syarat awal
1. Sudah install [Git for Windows](https://git-scm.com/download/win)
2. Sudah punya akun GitHub dan buat repo baru (kosong, tanpa README)

### Langkah-langkah

**Buka PowerShell** di folder project ini, lalu jalankan:

```powershell
.\setup-github.ps1
```

Script akan tanya:
- URL repo GitHub kamu (contoh: `https://github.com/namauser/dev-platform.git`)
- Nama branch (default: `main`)
- Pesan commit (bisa Enter saja)

Setelah selesai, semua file terupload otomatis ke GitHub.

### Kalau PowerShell blokir script
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\setup-github.ps1
```

---

## 🖥️ Cara Install di VPS (dari SSH)

### Syarat VPS
- Ubuntu 22.04 LTS
- Akses root / sudo via SSH
- Domain yang sudah bisa kamu kelola DNS-nya

### Cara 1: Installer otomatis (paling mudah)

SSH ke VPS lalu jalankan **satu perintah** ini (ganti URL dengan repo GitHub kamu):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/USERNAMEMU/NAMA-REPO/main/scripts/install-vps.sh)
```

Script akan tanya domain, email, password database, lalu setup semuanya otomatis.

### Cara 2: Manual (lebih kontrol)

```bash
# 1. Login ke VPS via SSH
ssh root@IP_VPS_KAMU

# 2. Clone repo dari GitHub
git clone https://github.com/USERNAMEMU/NAMA-REPO.git
cd NAMA-REPO

# 3. Jalankan setup sistem (install Docker, Nginx, firewall)
sudo bash scripts/setup.sh

# 4. Buat file konfigurasi
cp .env.example .env
nano .env
# Isi: DOMAIN, LETSENCRYPT_EMAIL, POSTGRES_PASSWORD, MYSQL_ROOT_PASSWORD, SESSION_SECRET

# 5. Jalankan semua service
docker compose up -d --build

# 6. Cek semua container berjalan
docker ps
```

### Setelah service jalan

```bash
# Tambah user baru (format: username password port)
sudo bash scripts/add-user.sh budi password123 8082
sudo bash scripts/add-user.sh siti password456 8083

# Setup HTTPS (setelah DNS subdomain diarahkan ke IP VPS)
sudo certbot --nginx -d dev.domainmu.com
sudo certbot --nginx -d budi.dev.domainmu.com
sudo certbot --nginx -d siti.dev.domainmu.com

# Lihat semua user aktif
bash scripts/list-users.sh
```

---

## 🔑 Login Default

| Role | Username | Password |
|---|---|---|
| Admin | `admin` | `admin123` |
| User | `user1` | `user1234` |

**Wajib ganti password setelah login pertama!**

---

## 🌐 Setup DNS (Cloudflare)

Tambahkan A Record untuk setiap subdomain:

| Type | Name | Content | Proxy Status |
|---|---|---|---|
| A | `dev` | IP_VPS | Proxied ☁️ |
| A | `*.dev` | IP_VPS | DNS Only (abu-abu) |

> Gunakan **DNS Only** untuk wildcard subdomain user agar Let's Encrypt bisa bekerja.

---

## 🗄️ Koneksi Database

### Dari VS Code terminal (di dalam VPS)

**PostgreSQL:**
```bash
psql -h devplatform-postgres -U namauser -d devplatform
```

**MySQL:**
```bash
mysql -h devplatform-mysql -u namauser -p db_namauser
```

### Dari laptop (via SSH tunnel)
```bash
# PostgreSQL — buka di laptop, lalu connect ke localhost:5432
ssh -L 5432:localhost:5432 user@vps-ip

# MySQL — buka di laptop, lalu connect ke localhost:3306
ssh -L 3306:localhost:3306 user@vps-ip
```
Setelah tunnel jalan, pakai DBeaver/TablePlus/MySQL Workbench dengan host `localhost`.

### Web UI Database (gaya cPanel)

| Tool | URL | Untuk |
|------|-----|-------|
| 🐬 **phpMyAdmin** | `https://mysql.DOMAIN` | MySQL — UI lengkap untuk query, import/export, manage user, dll |
| 🐘 **pgAdmin** | `https://pgadmin.DOMAIN` | PostgreSQL — UI lengkap dengan query editor, ER diagram, dll |

---

## 🧑‍💻 Perintah Berguna

```bash
# Lihat semua container
docker ps

# Restart portal
docker restart devplatform-portal

# Log portal
docker logs devplatform-portal -f

# Log user tertentu
docker logs codeserver-budi -f

# Backup database PostgreSQL
docker exec devplatform-postgres pg_dump -U postgres devplatform > backup.sql

# Backup database MySQL
docker exec devplatform-mysql mysqldump -u root -p devplatform_shared > backup.sql
```

---

## 📁 Struktur File Project

```
self-hosted-dev-platform/
├── server/
│   ├── index.js              # Server utama
│   ├── data/                 # (tidak di-commit) users.json
│   └── routes/               # auth, dashboard, admin, api
├── public/
│   ├── login.html            # Halaman login
│   ├── dashboard.html        # Dashboard user
│   └── admin.html            # Panel admin
├── nginx/nginx.conf          # Reverse proxy
├── scripts/
│   ├── setup.sh              # Setup VPS
│   ├── install-vps.sh        # Installer otomatis (one-liner)
│   ├── add-user.sh           # Tambah user + setup DB
│   ├── remove-user.sh        # Hapus user
│   ├── list-users.sh         # List user aktif
│   ├── create-project.sh     # Tambah folder project
│   ├── init-postgres.sql     # Tabel contoh PostgreSQL
│   └── init-mysql.sql        # Tabel contoh MySQL
├── docker-compose.yml        # Semua service
├── Dockerfile.portal         # Image portal
├── setup-github.ps1          # Upload ke GitHub (Windows PowerShell)
├── .env.example              # Template konfigurasi (aman di-commit)
└── .gitignore                # File yang dikecualikan dari GitHub
```

# 🖥️ Self-Hosted Dev Platform

Platform coding mandiri di VPS kamu sendiri — VS Code di browser, multi-user, gratis, untuk belajar bareng.

## Spesifikasi yang Direkomendasikan

| Komponen | Minimum | Direkomendasikan (punyamu) |
|---|---|---|
| CPU | 2 vCPU | 4 vCPU ✅ |
| RAM | 8 GB | 56 GB ✅ |
| Storage | 50 GB SSD | 100 GB+ SSD |
| OS | Ubuntu 22.04 | Ubuntu 22.04 LTS |

VPS kamu (4 vCPU / 56 GB) lebih dari cukup untuk 10 user.

---

## Yang Akan Kamu Dapatkan

Tiap user mendapat:
- **VS Code di browser** (code-server) — editor yang sama persis dengan VS Code desktop
- **Terminal bash** penuh di dalam browser
- **Folder project pribadi** yang persistent
- **Akses via HTTPS** di subdomain mereka: `https://namauser.domainmu.com`

---

## Prasyarat

1. VPS dengan Ubuntu 22.04 LTS
2. Domain yang DNS-nya bisa kamu kelola (misal lewat Cloudflare)
3. Akses SSH ke VPS sebagai root atau user dengan sudo

---

## Cara Install (5 Langkah)

### Langkah 1 — Clone repo ke VPS
```bash
git clone https://github.com/USERNAMEMU/self-hosted-dev-platform
cd self-hosted-dev-platform
```

### Langkah 2 — Jalankan setup otomatis
Script ini akan install Docker, Nginx, dan tools lainnya:
```bash
chmod +x scripts/*.sh
sudo bash scripts/setup.sh
```

### Langkah 3 — Isi konfigurasi
```bash
cp .env.example .env
nano .env
```

Isi nilainya:
```env
DOMAIN=dev.domainmu.com          # Domain utama kamu
LETSENCRYPT_EMAIL=email@mu.com   # Untuk HTTPS gratis
PASSWORD=passwordKuat123          # Password default (per-user bisa beda)
TZ=Asia/Jakarta
```

### Langkah 4 — Jalankan service dasar
```bash
docker compose up -d
```

### Langkah 5 — Tambah user
```bash
# Format: sudo bash scripts/add-user.sh namauser
sudo bash scripts/add-user.sh budi
sudo bash scripts/add-user.sh siti
sudo bash scripts/add-user.sh rafi
```

Setiap perintah akan:
1. Membuat container VS Code khusus user tersebut
2. Meng-generate password acak
3. Menampilkan URL dan password akses mereka

---

## Perintah Berguna

```bash
# Lihat semua user aktif
bash scripts/list-users.sh

# Tambah user baru
sudo bash scripts/add-user.sh namauser

# Hapus user
sudo bash scripts/remove-user.sh namauser

# Cek status semua container
docker ps

# Lihat log container user tertentu
docker logs codeserver-budi

# Restart container user tertentu
docker restart codeserver-budi
```

---

## Setup HTTPS per User

Setelah menambah user dan mengarahkan DNS subdomain ke VPS:

```bash
# Pastikan DNS sudah propagated dulu (bisa cek di dnschecker.org)
sudo certbot --nginx -d budi.dev.domainmu.com
sudo certbot --nginx -d siti.dev.domainmu.com
```

Certbot akan otomatis konfigurasi HTTPS di Nginx.

---

## Pengaturan DNS (Cloudflare)

Untuk tiap user, tambahkan A record:

| Type | Name | Content | Proxy |
|---|---|---|---|
| A | dev | IP_VPS_KAMU | Proxied |
| A | budi.dev | IP_VPS_KAMU | DNS Only |
| A | siti.dev | IP_VPS_KAMU | DNS Only |

> Gunakan **DNS Only** (tidak diproxy) untuk subdomain user agar SSL Certbot bisa bekerja.

---

## Fitur Platform

- ✅ VS Code lengkap di browser (extensions, IntelliSense, dll)
- ✅ Terminal bash penuh
- ✅ Bisa install bahasa apapun (Python, Node.js, Go, Java, dll)
- ✅ HTTPS gratis via Let's Encrypt
- ✅ Data user persistent (tidak hilang walau server restart)
- ✅ Auto-update container (via Watchtower)
- ✅ Web UI manajemen Docker (via Portainer)
- ✅ Firewall otomatis dikonfigurasi
- ✅ Mudah tambah/hapus user

---

## Estimasi Resource per User

| Resource | Per User |
|---|---|
| RAM | ~512 MB – 2 GB (tergantung aktivitas) |
| CPU | 0.5 – 1 core saat aktif coding |
| Storage | Sesuai project mereka |

Dengan 56 GB RAM, kamu bisa nyaman untuk 10 user aktif sekaligus.

---

## Troubleshooting

**Container tidak mau start:**
```bash
docker logs codeserver-namauser
```

**HTTPS tidak jalan:**
```bash
sudo certbot renew --dry-run
sudo nginx -t
sudo systemctl reload nginx
```

**Port konflik:**
```bash
sudo netstat -tulpn | grep 808
```

---

## Keamanan

- Setiap user punya password dan environment terisolasi
- Firewall hanya buka port 22 (SSH), 80 (HTTP), 443 (HTTPS)
- Fail2Ban aktif untuk mencegah brute-force SSH
- HTTPS enforced (HTTP otomatis redirect ke HTTPS)
- Password tiap user di-generate secara random

---

## Lisensi

Open source, bebas dipakai untuk belajar. Tidak untuk dijual kembali.

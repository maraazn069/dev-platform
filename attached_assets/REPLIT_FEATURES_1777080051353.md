# Apa Saja yang Replit Bisa Lakukan (Lengkap)

> Replit = platform cloud development end-to-end. Dari **prompt teks doang**, kamu bisa bikin app full-stack, deploy ke production, dan jalanin terus tanpa setup server sendiri.

---

## 🤖 1. Replit Agent — Bikin App dari Prompt

Cukup ketik dalam Bahasa Indonesia atau Inggris, contoh:

- *"Bikin website portofolio dengan dark mode dan halaman blog"*
- *"Bikin Discord bot yang bisa kasih meme random"*
- *"Bikin REST API toko online dengan auth dan database"*
- *"Tambahin fitur login Google ke app saya"*
- *"Fix bug di halaman checkout, tombol submit gak jalan"*
- *"Refactor kode ini biar lebih cepet"*

Agent akan:
1. **Scaffold project** — pilih bahasa & framework otomatis
2. **Tulis kode lengkap** — frontend + backend + database
3. **Install dependency** — package.json, requirements.txt dll auto
4. **Setup config** — env vars, secrets, port
5. **Test sendiri** — jalanin app, cek error, fix sendiri
6. **Deploy ke production** kalau diminta — sekali klik

---

## 🌐 2. Bahasa & Framework yang Disupport

### Bahasa Pemrograman (50+)
**Mainstream**: Python, JavaScript/TypeScript, Java, C/C++, C#, Go, Rust, Ruby, PHP, Swift, Kotlin, Dart, Scala, R, MATLAB, Perl

**Web/Markup**: HTML, CSS, SCSS, Markdown, LaTeX

**Database**: SQL (PostgreSQL, MySQL, SQLite), MongoDB query

**Lainnya**: Bash, PowerShell, Lua, Haskell, Elixir, Clojure, F#, OCaml, Crystal, Julia, Nim, Zig

### Frontend Framework
- **React** + Next.js + Remix
- **Vue** + Nuxt
- **Svelte** + SvelteKit
- **Angular**
- **Solid.js**
- **Astro**
- **Vanilla HTML/CSS/JS**

### Backend Framework
- **Node.js**: Express, Fastify, Koa, NestJS
- **Python**: Flask, Django, FastAPI, Starlette
- **Ruby**: Rails, Sinatra
- **Go**: Gin, Echo, Fiber
- **Java**: Spring Boot
- **PHP**: Laravel, Symfony
- **Rust**: Actix, Rocket, Axum

### Mobile
- **React Native** dengan **Expo** — bisa preview langsung di HP via QR code
- **Flutter** (terbatas)

### Game / Grafis
- **Unity** (web build)
- **Pygame**, **p5.js**, **Three.js**, **Babylon.js**
- **Phaser**

---

## 📥 3. Cara Import Code

### Dari GitHub
- Klik "Import from GitHub" → tempel URL repo → otomatis clone & setup
- Support repo public maupun private (lewat OAuth)

### Dari ZIP
- Drag & drop file `.zip` ke workspace → otomatis extract

### Dari Replit Lain (Fork)
- Buka Repl orang → klik "Fork" → copy ke akun kamu

### Dari URL/Gist
- Tempel URL gist GitHub atau pastebin → import

### Dari Template
- Library template ribuan: starter Next.js, Django, Phaser game, Discord bot, dll

### Dari Screenshot/Design
- Upload gambar mockup atau Figma → Agent recreate jadi kode

### Dari Spec Tertulis
- Tempel PRD/wireframe text → Agent generate app sesuai spec

---

## 🗄️ 4. Database & Storage Built-in

### Replit Database (Key-Value)
- NoSQL sederhana, langsung pake — `from replit import db` atau `import { db } from "@replit/database"`
- Cocok untuk session, cache, simple state

### PostgreSQL Built-in
- Database PostgreSQL real, terkelola Replit
- Connection string otomatis di env vars
- Bisa pake ORM: Prisma, Drizzle, SQLAlchemy, Sequelize

### Replit Object Storage
- Mirip S3, simpan file gede (gambar, video, PDF)
- Built-in upload UI

### MongoDB / MySQL / Redis (External)
- Bisa connect ke Atlas, PlanetScale, Upstash dll

---

## 🔌 5. Integrasi Pihak Ketiga (Plug & Play)

Setup tinggal klik tombol, OAuth handled otomatis:

| Kategori | Service |
|---|---|
| **AI** | OpenAI (GPT-4o/o1), Anthropic (Claude), Google Gemini, Stable Diffusion, ElevenLabs, Whisper |
| **Auth** | Replit Auth, Google OAuth, GitHub OAuth, Auth0, Clerk |
| **Payment** | Stripe, RevenueCat (mobile), PayPal |
| **Code** | GitHub, GitLab |
| **Productivity** | Notion, Linear, Jira, Slack, Discord, Telegram |
| **Email** | SendGrid, Resend, Mailgun |
| **SMS** | Twilio |
| **Analytics** | PostHog, Mixpanel, Google Analytics |
| **Storage** | AWS S3, Cloudinary |
| **CMS** | Sanity, Contentful |

---

## 🚀 6. Deploy Otomatis (Production)

### Mode Deploy yang Tersedia

| Mode | Use Case | Harga |
|---|---|---|
| **Autoscale** | Web app traffic naik-turun | Bayar per request |
| **Reserved VM** | App always-on butuh resource konstan | Flat monthly |
| **Static** | Website HTML/CSS/JS statis | Murah, edge CDN |
| **Scheduled** | Cron job berkala | Per execution |

### Yang Otomatis Dihandle
- ✅ Build pipeline (npm build, pip install, dll)
- ✅ HTTPS gratis (Let's Encrypt)
- ✅ Custom domain (CNAME → `.replit.app`)
- ✅ Health check & auto-restart
- ✅ Zero-downtime deploys
- ✅ Rollback ke versi sebelumnya
- ✅ Logs streaming real-time
- ✅ Environment promotion (dev → prod)
- ✅ Geographic regions (US, EU, Asia)

### Custom Domain
- Tinggal masukkan domain `mysite.com` → Replit kasih CNAME record → set di Cloudflare/registrar → done

---

## ⚙️ 7. File Konfigurasi yang Replit Punya

### `.replit`
File utama config Repl. Contoh:
```toml
run = "python main.py"
entrypoint = "main.py"
modules = ["python-3.11", "nodejs-20"]

[deployment]
run = "gunicorn main:app"
deploymentTarget = "autoscale"

[[ports]]
localPort = 5000
externalPort = 80
```

### `replit.nix`
Define system packages via Nix (alternatif apt-get). Contoh:
```nix
{ pkgs }: {
  deps = [
    pkgs.nodejs_20
    pkgs.python311
    pkgs.ffmpeg
    pkgs.imagemagick
    pkgs.postgresql_15
  ];
}
```

### `replit.md`
Dokumentasi project + memory buat AI Agent. Berisi context, preferensi user, arsitektur. Agent baca tiap session.

### Workflow Files
PM2-like config buat run multiple processes paralel (web server + worker + dll).

---

## 📦 8. Package Manager (Auto)

Replit auto-detect & install dependency dari file standard:

| Bahasa | File |
|---|---|
| Python | `requirements.txt`, `pyproject.toml`, `pipenv.lock`, `poetry.lock` |
| Node.js | `package.json`, `pnpm-lock.yaml`, `yarn.lock` |
| Ruby | `Gemfile`, `Gemfile.lock` |
| Go | `go.mod`, `go.sum` |
| Rust | `Cargo.toml`, `Cargo.lock` |
| Java | `pom.xml` (Maven), `build.gradle` (Gradle) |
| PHP | `composer.json`, `composer.lock` |
| C/C++ | `CMakeLists.txt`, `Makefile` |

### Universal Package Manager (UPM)
Replit punya UPM khusus yang detect import statement di kode dan auto-install:
- Python: scan `import` → auto `pip install`
- Node: scan `require/import` → auto `npm install`

Kamu tinggal pake `import requests` di Python, Replit langsung install requests.

### System Package
Pake panel "Packager" UI atau edit `replit.nix`. Bisa install ffmpeg, imagemagick, tesseract, dll.

---

## 🔐 9. Secrets & Environment Variables

- Tab "Secrets" di sidebar
- Set key-value, otomatis ter-inject sebagai env var saat run
- Encrypted at rest
- Tidak ke-commit ke Git
- Akses dari kode: `os.environ.get('OPENAI_API_KEY')` (Python) atau `process.env.OPENAI_API_KEY` (Node)

---

## 🛠️ 10. Tools dalam Workspace

### Editor
- **Monaco Editor** (sama kayak VS Code)
- Syntax highlight 100+ bahasa
- IntelliSense / autocomplete
- Multi-cursor, find & replace
- Vim/Emacs keybindings (settings)

### File Manager
- Tree view, drag & drop, upload, download zip
- Klik kanan: rename, delete, duplicate, move

### Console
- Output app langsung
- Bisa input stdin (untuk app interaktif)

### Shell
- Full bash terminal di container
- Akses sudo (di Repl-mu sendiri), install apa aja
- Multi-tab terminal

### Webview (Live Preview)
- Iframe yang nampilin app jalan
- Auto-refresh saat code berubah (HMR untuk React/Vue dll)
- Mobile preview mode

### Debugger
- Breakpoint visual untuk Python & Node.js
- Inspect variabel, step through code

### Git
- Klik UI commit, push, pull, branch, merge
- Sync ke GitHub repo

### Database UI
- Query editor SQL visual
- Browse table, edit row langsung
- Export CSV/JSON

### Image/Video Generator
- Built-in AI image (DALL-E, Stable Diffusion)
- AI video generator (Sora-like)
- AI voice (text-to-speech)

---

## 👥 11. Kolaborasi Real-time

- **Multiplayer**: beberapa orang edit Repl bareng (kayak Google Docs)
- **Comments** di kode, threaded discussion
- **Share link** view-only atau editor access
- **Teams** untuk organisasi (paid)

---

## 📱 12. Mobile App (Replit Mobile)

- Edit & jalanin Repl dari HP (iOS & Android)
- AI Agent juga jalan di mobile
- Notification kalau Agent selesai task

---

## 🎓 13. Hal Lain yang Sering Dipake

### Replit Auth
- Login system pre-built — user pake akun Replit mereka
- Tinggal `import` lib, dapet user object langsung

### Replit AI (Built-in)
- Chat AI buat tanya-tanya tentang kode
- Inline suggestions saat ngetik (Copilot-like)
- Generate code dari komen
- Explain code
- Translate antar bahasa

### Always-On (deprecated, sekarang via Deploy)
- Repl jalan terus walau tab ditutup

### Snapshots & Checkpoints
- Auto-checkpoint setiap selesai task Agent
- Bisa rollback ke versi mana aja

### Templates Marketplace
- Ratusan template ready-to-fork
- Discord bot, Telegram bot, Twitter bot, scrapers, mini games, REST API starter dll

### Bounties
- Marketplace gigs — orang bayar lo bikin Repl untuk mereka

---

## 💡 Workflow Khas Pemakai Replit

### Skenario 1: Bikin Web App dari Nol
1. Buka Replit, klik "Create App"
2. Pilih "Use Agent" → ketik prompt: *"Bikin SaaS dashboard pake Next.js + PostgreSQL + Stripe"*
3. Agent scaffold → install deps → setup DB → bikin halaman
4. Lo review, kasih feedback: *"Halaman pricing-nya tambahin tier Enterprise"*
5. Klik Deploy → app live di `https://my-saas-abc123.replit.app`
6. (Opsional) Pasang custom domain `mysaas.com`

### Skenario 2: Fix Bug di App Existing
1. Import repo dari GitHub
2. Buka Agent: *"Tombol login di mobile gak responsive, kebawah-bawah"*
3. Agent baca kode, identifikasi masalah CSS, fix, test, commit ke Git
4. Push back ke GitHub

### Skenario 3: Build & Deploy Discord Bot
1. Pilih template "Discord Bot Python"
2. Set secret `DISCORD_TOKEN`
3. Edit `main.py`, tambah command
4. Klik "Deploy" → Reserved VM mode
5. Bot online 24/7

---

## 🆚 Perbandingan vs Tools Lain

| Fitur | Replit | GitHub Codespaces | Vercel | Heroku |
|---|---|---|---|---|
| AI Agent autonomous | ✅ | ❌ (Copilot only) | ❌ | ❌ |
| Browser-only IDE | ✅ | ✅ | ❌ | ❌ |
| Auto deploy | ✅ | ❌ | ✅ | ✅ |
| Built-in DB | ✅ PG + KV | ❌ | ❌ | ✅ PG |
| Multiplayer | ✅ | ❌ | ❌ | ❌ |
| Free tier | ✅ generous | ✅ limited hours | ✅ | ❌ (sejak 2022) |
| Mobile app | ✅ | ❌ | ❌ | ❌ |
| Custom domain | ✅ | ❌ | ✅ | ✅ |

---

## 🎯 Kesimpulan

Replit = **all-in-one platform**:
- 🤖 AI Agent yang bisa bikin app dari prompt
- 💻 IDE di browser
- 🗄️ Database + storage built-in
- 🚀 Deploy production dalam 1 klik
- 🔌 Integrasi puluhan service
- 👥 Kolaborasi real-time

Yang biasanya butuh **belajar 5+ tools terpisah** (VS Code + GitHub + Heroku + Postman + Postgres + dll), Replit kasih dalam **1 platform**, dengan **AI Agent yang ngerjain banyak hal otomatis**.

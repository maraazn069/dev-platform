# ================================================================
# setup-github.ps1
# Script PowerShell untuk upload project ke GitHub
# Jalankan di PowerShell (bukan CMD):
#   .\setup-github.ps1
# ================================================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Self-Hosted Dev Platform — Upload ke GitHub  " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# --- Cek apakah Git sudah terinstall ---
try {
    git --version | Out-Null
} catch {
    Write-Host "Git belum terinstall! Download di: https://git-scm.com/download/win" -ForegroundColor Red
    exit 1
}

# --- Tanya URL repo GitHub ---
Write-Host "Masukkan URL repo GitHub kamu." -ForegroundColor Yellow
Write-Host "Contoh: https://github.com/namauser/self-hosted-dev-platform.git" -ForegroundColor Gray
Write-Host ""
$repoUrl = Read-Host "URL GitHub repo"

if (-not $repoUrl) {
    Write-Host "URL tidak boleh kosong." -ForegroundColor Red
    exit 1
}

# --- Tanya nama branch ---
$branch = Read-Host "Nama branch (tekan Enter untuk pakai 'main')"
if (-not $branch) { $branch = "main" }

# --- Tanya commit message ---
$commitMsg = Read-Host "Pesan commit (tekan Enter untuk pakai default)"
if (-not $commitMsg) { $commitMsg = "Initial commit: Self-Hosted Dev Platform" }

Write-Host ""
Write-Host "[1/5] Inisialisasi Git..." -ForegroundColor Yellow
if (-not (Test-Path ".git")) {
    git init
    Write-Host "Git repository dibuat." -ForegroundColor Green
} else {
    Write-Host "Git repository sudah ada." -ForegroundColor Green
}

Write-Host "[2/5] Mengatur remote origin..." -ForegroundColor Yellow
try {
    git remote add origin $repoUrl 2>&1 | Out-Null
    Write-Host "Remote origin ditambahkan." -ForegroundColor Green
} catch {
    git remote set-url origin $repoUrl
    Write-Host "Remote origin diperbarui." -ForegroundColor Green
}

Write-Host "[3/5] Memastikan .gitignore sudah benar..." -ForegroundColor Yellow
$gitignoreContent = Get-Content ".gitignore" -Raw
if (-not $gitignoreContent.Contains(".env")) {
    Add-Content ".gitignore" "`n.env"
}
if (-not $gitignoreContent.Contains("users.json")) {
    Add-Content ".gitignore" "`nserver/data/users.json"
}
Write-Host ".gitignore OK." -ForegroundColor Green

Write-Host "[4/5] Menambah semua file ke staging..." -ForegroundColor Yellow
git add .
$status = git status --short
Write-Host "File yang akan di-commit:" -ForegroundColor Gray
Write-Host $status -ForegroundColor Gray

Write-Host "[5/5] Commit dan push ke GitHub..." -ForegroundColor Yellow
git commit -m $commitMsg

# Set branch ke main/master
git branch -M $branch

# Push
Write-Host ""
Write-Host "Meng-upload ke GitHub..." -ForegroundColor Cyan
git push -u origin $branch

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Berhasil di-upload ke GitHub!                " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Repo kamu: $repoUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Langkah selanjutnya — Install di VPS:" -ForegroundColor Yellow
Write-Host "  1. SSH ke VPS:  ssh root@IP_VPS_KAMU" -ForegroundColor White
Write-Host "  2. Jalankan:    bash <(curl -fsSL https://raw.githubusercontent.com/$(($repoUrl -replace 'https://github.com/', '' -replace '\.git', ''))/$branch/scripts/install-vps.sh)" -ForegroundColor White
Write-Host ""
Write-Host "Atau clone manual lalu jalankan install-vps.sh" -ForegroundColor Gray

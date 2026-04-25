-- ================================================================
-- init-postgres.sql
-- Inisialisasi database PostgreSQL untuk Dev Platform
-- Dijalankan otomatis saat container PostgreSQL pertama start
-- ================================================================

-- Extension berguna untuk belajar
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "citext";

COMMENT ON DATABASE devplatform IS 'Database bersama Dev Platform — untuk belajar SQL & PostgreSQL';

-- ================================================================
-- CONTOH TABEL BELAJAR (di schema public, bisa dipakai semua user)
-- ================================================================

-- Tabel contoh: Mahasiswa
CREATE TABLE IF NOT EXISTS public.contoh_mahasiswa (
    id          SERIAL PRIMARY KEY,
    nim         VARCHAR(20) UNIQUE NOT NULL,
    nama        VARCHAR(100) NOT NULL,
    jurusan     VARCHAR(100),
    angkatan    INTEGER,
    ipk         DECIMAL(3,2) CHECK (ipk >= 0 AND ipk <= 4),
    email       VARCHAR(150),
    dibuat_pada TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.contoh_mahasiswa (nim, nama, jurusan, angkatan, ipk, email) VALUES
    ('2021001', 'Budi Santoso',    'Teknik Informatika', 2021, 3.75, 'budi@kampus.ac.id'),
    ('2021002', 'Siti Rahayu',     'Sistem Informasi',   2021, 3.90, 'siti@kampus.ac.id'),
    ('2022001', 'Rafi Pratama',    'Teknik Informatika', 2022, 3.50, 'rafi@kampus.ac.id'),
    ('2022002', 'Dewi Lestari',    'Manajemen',          2022, 3.85, 'dewi@kampus.ac.id'),
    ('2023001', 'Ahmad Fauzi',     'Akuntansi',          2023, 3.20, 'ahmad@kampus.ac.id')
ON CONFLICT (nim) DO NOTHING;

-- Tabel contoh: Produk (untuk belajar e-commerce)
CREATE TABLE IF NOT EXISTS public.contoh_produk (
    id          SERIAL PRIMARY KEY,
    kode        VARCHAR(20) UNIQUE NOT NULL,
    nama        VARCHAR(200) NOT NULL,
    kategori    VARCHAR(100),
    harga       DECIMAL(15,2) NOT NULL CHECK (harga >= 0),
    stok        INTEGER DEFAULT 0 CHECK (stok >= 0),
    deskripsi   TEXT,
    dibuat_pada TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.contoh_produk (kode, nama, kategori, harga, stok, deskripsi) VALUES
    ('PRD001', 'Laptop Gaming Asus',     'Elektronik', 15000000, 10, 'Laptop gaming dengan RTX 3060'),
    ('PRD002', 'Mouse Wireless Logitech','Elektronik',   350000, 50, 'Mouse wireless ergonomis'),
    ('PRD003', 'Buku Python Dasar',      'Buku',         120000, 30, 'Belajar Python dari nol'),
    ('PRD004', 'Headset Sony',           'Elektronik',   800000, 20, 'Headset noise-cancelling'),
    ('PRD005', 'Meja Belajar Kayu',      'Furnitur',     750000, 15, 'Meja belajar minimalis')
ON CONFLICT (kode) DO NOTHING;

-- Tabel contoh: Transaksi
CREATE TABLE IF NOT EXISTS public.contoh_transaksi (
    id              SERIAL PRIMARY KEY,
    kode_transaksi  VARCHAR(50) UNIQUE DEFAULT 'TRX-' || LPAD(NEXTVAL('contoh_transaksi_id_seq')::TEXT, 6, '0'),
    produk_id       INTEGER REFERENCES public.contoh_produk(id),
    jumlah          INTEGER NOT NULL CHECK (jumlah > 0),
    total_harga     DECIMAL(15,2),
    status          VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending','sukses','gagal')),
    tanggal         TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- Catatan: Schema per-user dibuat oleh scripts/add-user.sh
-- Format: CREATE SCHEMA namauser AUTHORIZATION namauser;
-- ================================================================

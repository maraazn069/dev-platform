-- ============================================================
-- Inisialisasi PostgreSQL untuk Dev Platform
-- Dijalankan otomatis saat container pertama kali start
-- ============================================================

-- Buat database utama (sudah dibuat via POSTGRES_DB env)
-- Script ini untuk setup schema dan user awal

-- Extension berguna untuk belajar
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Komentar panduan
COMMENT ON DATABASE devplatform IS 'Database bersama Dev Platform — untuk belajar SQL & PostgreSQL';

-- Schema akan dibuat per-user oleh script add-user.sh
-- Contoh: CREATE SCHEMA budi; GRANT ALL ON SCHEMA budi TO budi;

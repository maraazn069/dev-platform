-- ================================================================
-- init-mysql.sql
-- Inisialisasi database MySQL untuk Dev Platform
-- Dijalankan otomatis saat container MySQL pertama start
-- ================================================================

-- Gunakan database shared
USE devplatform_shared;

-- ================================================================
-- CONTOH TABEL BELAJAR (database bersama)
-- ================================================================

-- Tabel contoh: Siswa
CREATE TABLE IF NOT EXISTS contoh_siswa (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    nis         VARCHAR(20) UNIQUE NOT NULL,
    nama        VARCHAR(100) NOT NULL,
    kelas       VARCHAR(10),
    jurusan     VARCHAR(100),
    nilai_rata  DECIMAL(5,2),
    email       VARCHAR(150),
    dibuat_pada DATETIME DEFAULT NOW()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO contoh_siswa (nis, nama, kelas, jurusan, nilai_rata, email) VALUES
    ('SIS001', 'Andi Wijaya',    'XII', 'IPA',  88.5, 'andi@sekolah.id'),
    ('SIS002', 'Rina Sari',      'XI',  'IPS',  91.0, 'rina@sekolah.id'),
    ('SIS003', 'Doni Saputra',   'X',   'IPA',  79.5, 'doni@sekolah.id'),
    ('SIS004', 'Fitri Handayani','XII', 'Bahasa',85.0, 'fitri@sekolah.id'),
    ('SIS005', 'Bagas Prasetyo', 'XI',  'IPA',  77.0, 'bagas@sekolah.id');

-- Tabel contoh: Toko Online
CREATE TABLE IF NOT EXISTS contoh_barang (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    kode        VARCHAR(20) UNIQUE NOT NULL,
    nama        VARCHAR(200) NOT NULL,
    kategori    VARCHAR(100),
    harga       DECIMAL(15,2) NOT NULL,
    stok        INT DEFAULT 0,
    berat_gram  INT,
    dibuat_pada DATETIME DEFAULT NOW()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO contoh_barang (kode, nama, kategori, harga, stok, berat_gram) VALUES
    ('BRG001', 'Sepatu Sneakers Nike', 'Fashion',    850000, 25,  500),
    ('BRG002', 'Kaos Polos Premium',   'Fashion',     75000, 100, 150),
    ('BRG003', 'Tas Ransel Canvas',    'Tas',         220000, 40,  400),
    ('BRG004', 'Powerbank 20000mAh',   'Elektronik', 350000, 30,  250),
    ('BRG005', 'Buku SQL Lengkap',     'Buku',        95000, 20,  300);

-- Tabel contoh: Pesanan
CREATE TABLE IF NOT EXISTS contoh_pesanan (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    nomor_pesanan   VARCHAR(50) UNIQUE NOT NULL,
    nama_pembeli    VARCHAR(100) NOT NULL,
    barang_id       INT,
    jumlah          INT NOT NULL,
    total           DECIMAL(15,2),
    status          ENUM('pending','diproses','dikirim','selesai','dibatalkan') DEFAULT 'pending',
    tanggal         DATETIME DEFAULT NOW(),
    FOREIGN KEY (barang_id) REFERENCES contoh_barang(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO contoh_pesanan (nomor_pesanan, nama_pembeli, barang_id, jumlah, total, status) VALUES
    ('ORD-000001', 'Budi Santoso', 1, 1, 850000,  'selesai'),
    ('ORD-000002', 'Siti Rahayu',  2, 3, 225000,  'dikirim'),
    ('ORD-000003', 'Rafi Pratama', 4, 1, 350000,  'diproses'),
    ('ORD-000004', 'Dewi Lestari', 3, 2, 440000,  'pending');

-- ================================================================
-- Database per-user dibuat otomatis oleh scripts/add-user.sh
-- Format: db_namauser
-- ================================================================

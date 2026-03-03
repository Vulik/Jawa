#!/bin/bash
# ============================================================
# Script otomatisasi pemeliharaan aplikasi untuk Android (Root)
# Versi: Mendukung file ZIP yang berisi APK
# Dependensi: curl, unzip (install di Termux: pkg install curl unzip)
# ============================================================

# Pastikan script dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Script harus dijalankan sebagai root."
    echo "Gunakan: su -c \"bash $0\""
    exit 1
fi

# ========== KONFIGURASI (UBAH SESUAI KEBUTUHAN) ==========
# Daftar package name (harus sesuai dengan yang terinstall di sistem)
packages=(
    "com.example.app1"
    "com.example.app2"
    "com.example.app3"
)

# Daftar URL download (bisa langsung APK atau ZIP)
# Pastikan urutannya sama dengan array packages
urls=(
 "https://github.com/Vulik/Jawa/releases/download/Hai/HI.zip"   # ZIP berisi APK
)

# Direktori sementara (harus writable oleh root)
TEMP_DIR="/data/local/tmp"
# ============================================================

# Fungsi untuk membuka aplikasi menggunakan monkey (fallback ke am start)
open_app() {
    local pkg="$1"
    echo "Membuka aplikasi $pkg ..."
    # Coba dengan monkey (paling sederhana)
    monkey -p "$pkg" 1 > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Peringatan: Gagal membuka $pkg dengan monkey. Coba metode alternatif..."
        # Alternatif: buka dengan intent launcher (memerlukan activity utama, mungkin berhasil)
        am start -p "$pkg" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER > /dev/null 2>&1
    fi
}

# Pastikan direktori temp ada
mkdir -p "$TEMP_DIR"

# Loop berdasarkan indeks array packages
for i in "${!packages[@]}"; do
    pkg="${packages[$i]}"
    url="${urls[$i]}"
    
    # Nama file berdasarkan URL (untuk disimpan sementara)
    filename=$(basename "$url")
    downloaded_file="$TEMP_DIR/$filename"

    echo "========================================="
    echo "Memproses: $pkg"
    echo "URL: $url"
    echo "========================================="

    # 1. Uninstall paket (abaikan error jika tidak terinstall)
    echo "Menghapus $pkg ..."
    pm uninstall "$pkg" > /dev/null 2>&1
    sleep 1

    # 2. Download file
    echo "Mendownload file..."
    curl -L -o "$downloaded_file" "$url"
    if [ $? -ne 0 ] || [ ! -f "$downloaded_file" ]; then
        echo "Error: Gagal mendownload file. Lewati package ini."
        continue
    fi
    echo "Download selesai: $downloaded_file"

    # 3. Proses file: jika ZIP, ekstrak dan cari APK
    apk_file=""
    if [[ "$filename" == *.zip ]]; then
        echo "File ZIP terdeteksi. Mengekstrak..."
        extract_dir="$TEMP_DIR/extracted_$pkg"
        mkdir -p "$extract_dir"
        unzip -o "$downloaded_file" -d "$extract_dir" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Gagal mengekstrak ZIP."
            rm -f "$downloaded_file"
            continue
        fi

        # Cari file APK pertama di dalam folder hasil ekstraksi
        apk_file=$(find "$extract_dir" -name "*.apk" -type f | head -n 1)
        if [ -z "$apk_file" ]; then
            echo "Error: Tidak ditemukan file APK di dalam ZIP."
            rm -rf "$extract_dir" "$downloaded_file"
            continue
        else
            echo "Ditemukan APK: $apk_file"
        fi
    else
        # Jika bukan ZIP, asumsikan langsung APK
        apk_file="$downloaded_file"
    fi

    # 4. Install APK
    echo "Menginstall $pkg dari $apk_file ..."
    pm install -r "$apk_file" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Gagal menginstall $pkg"
        # Bersihkan file sementara
        rm -f "$downloaded_file"
        [ -d "$extract_dir" ] && rm -rf "$extract_dir"
        continue
    fi

    # 5. Buka aplikasi untuk inisialisasi data
    open_app "$pkg"

    # 6. Tunggu 10 detik
    echo "Menunggu 10 detik..."
    sleep 10

    # 7. Bersihkan semua file sementara
    rm -f "$downloaded_file"
    [ -d "$extract_dir" ] && rm -rf "$extract_dir"

    echo "Selesai untuk $pkg"
    echo ""
done

echo "Semua proses selesai."

#!/bin/bash
# =============================================================================
# 🎯 GITHUB RELEASE INSTALLER (Vulik/Jawa - Tag: Hai)
# 📦 Versi: 2.4 - Progress bar rapi & stabil
# 🔧 Fitur: Pilih file 1/2/3 atau A (semua), instal otomatis, hapus temp, trap sempurna
# =============================================================================

VERSION="2.4"

# =============================================================================
# 1. CEK LINGKUNGAN
# =============================================================================
# Cek akses root (dibutuhkan untuk instalasi)
if [ "$(id -u)" -ne 0 ] && ! command -v su &>/dev/null; then
    echo -e "\e[1;31m[ERROR] Script ini butuh akses root untuk instalasi!\e[0m"
    exit 1
fi

# Cek dependensi: curl, jq
MISSING=""
if ! command -v curl &>/dev/null; then MISSING+=" curl"; fi
if ! command -v jq &>/dev/null; then MISSING+=" jq"; fi
if [ -n "$MISSING" ]; then
    echo -e "\e[1;33m⚠️  Perintah berikut tidak ditemukan:$MISSING\e[0m"
    echo -e "\e[1;33m   Install dengan: pkg install$MISSING\e[0m"
    exit 1
fi

# =============================================================================
# 2. SIAPKAN TEMPAT SEMENTARA (di home, tidak perlu root)
# =============================================================================
TEMP_DIR="$HOME/roblox_installer"
mkdir -p "$TEMP_DIR"

# =============================================================================
# 3. WARNA (untuk tampilan)
# =============================================================================
G='\e[1;32m'; B='\e[1;34m'; Y='\e[1;33m'; C='\e[1;36m'; R='\e[1;31m'; M='\e[1;35m'; W='\e[1;37m'; BD='\e[1m'; N='\e[0m'

# =============================================================================
# 4. TRAP UNTUK PENANGANAN INTERUPSI (Ctrl+C, EXIT)
# =============================================================================
# Array untuk menyimpan PID proses download yang sedang berjalan
declare -a DOWNLOAD_PIDS=()

cleanup() {
    echo -e "\n${Y}⚠️  Membersihkan dan menghentikan semua proses...${N}"
    # Hentikan semua proses download yang masih berjalan
    for pid in "${DOWNLOAD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        fi
    done
    # Hapus semua file di folder temp (tanpa menghapus folder)
    rm -rf "$TEMP_DIR"/*
    echo -e "${G}✅ Selesai.${N}"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# =============================================================================
# 5. FUNGSI AMBIL DATA DARI GITHUB (release "Hai")
# =============================================================================
fetch_assets() {
    local repo="Vulik/Jawa"
    local tag="Hai"
    local api_url="https://api.github.com/repos/$repo/releases/tags/$tag"

    echo -e "${Y}🔍 Mengambil data dari release 'Hai'...${N}"
    release_data=$(curl -s "$api_url")

    # Cek apakah ada pesan error (misalnya release tidak ditemukan)
    if echo "$release_data" | jq -e '.message' >/dev/null 2>&1; then
        echo -e "${R}❌ Release 'Hai' tidak ditemukan atau repository tidak bisa diakses.${N}"
        echo -e "${Y}Pesan: $(echo "$release_data" | jq -r '.message')${N}"
        return 1
    fi

    # Ambil nama dan url aset
    mapfile -t asset_names < <(echo "$release_data" | jq -r '.assets[]?.name')
    mapfile -t asset_urls < <(echo "$release_data" | jq -r '.assets[]?.browser_download_url')

    if [ ${#asset_names[@]} -eq 0 ]; then
        echo -e "${R}❌ Tidak ada file aset (assets) pada release ini.${N}"
        return 1
    fi

    echo -e "${G}✅ Ditemukan ${#asset_names[@]} file pada release 'Hai'.${N}"
    return 0
}

# =============================================================================
# 6. FUNGSI DOWNLOAD & INSTALL SATU FILE
# =============================================================================
download_and_install() {
    local url="$1"
    local filename="$2"
    local output="$TEMP_DIR/$filename"

    echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${C}[*] Mengunduh: ${W}$filename${N}"
    rm -f "$output"

    # Download dengan curl dalam mode silent (tidak ada output), jalankan di background
    curl -L -s -o "$output" "$url" &
    local pid=$!
    DOWNLOAD_PIDS+=("$pid")

    # Progress bar buatan sendiri (naik 5% tiap 0.3 detik)
    local progress=0
    while kill -0 $pid 2>/dev/null; do
        progress=$((progress + 5))
        [ $progress -gt 95 ] && progress=98
        local filled=$((progress / 5))
        local bar=$(printf "%${filled}s" | tr ' ' '█')
        local empty=$((20 - filled))
        echo -ne "\r${B}    [${C}${bar}${N}${B}$(printf "%${empty}s" | tr ' ' '-')] ${W}${progress}%${N}"
        sleep 0.3
    done
    wait $pid
    local curl_exit=$?
    echo -ne "\r${B}    [${C}████████████████████${N}${B}] ${W}100%${N}\n"

    # Hapus PID dari daftar setelah selesai
    DOWNLOAD_PIDS=("${DOWNLOAD_PIDS[@]/$pid}")

    if [ $curl_exit -ne 0 ] || [ ! -s "$output" ]; then
        echo -e "${R}❌ Gagal mengunduh $filename${N}"
        return 1
    fi

    echo -e "${Y}📦 Menginstal $filename...${N}"
    if su -c "pm install -r -d -g \"$output\"" </dev/null >/dev/null 2>&1; then
        echo -e "${G}✅ Instalasi sukses!${N}"
        rm -f "$output"
        echo -e "${Y}🗑️  File sementara dihapus.${N}"
        return 0
    else
        echo -e "${R}❌ Instalasi gagal! File tetap disimpan di $output${N}"
        return 1
    fi
}

# =============================================================================
# 7. FUNGSI MENU PILIHAN
# =============================================================================
show_menu() {
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${W}${BD}   FILE TERSEDIA DI RELEASE 'Hai'${N}"
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"

    for i in "${!asset_names[@]}"; do
        echo -e "${B}  [$((i+1))] ${W}${asset_names[$i]}${N}"
    done

    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${Y}  [A] Download & Install SEMUA file sekaligus${N}"
    echo -e "${W}  [0] Keluar${N}"
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    read -p "Pilih opsi (contoh: 1,2,3 atau A): " choice
}

# =============================================================================
# 8. FUNGSI UTAMA
# =============================================================================
main() {
    clear
    echo -e "${C}════════════════════════════════════════════════════${N}"
    echo -e "${W}   GITHUB RELEASE INSTALLER v${VERSION}${N}"
    echo -e "${C}════════════════════════════════════════════════════${N}"

    # Ambil data aset, jika gagal maka exit
    fetch_assets || exit 1

    # Loop utama menu
    while true; do
        show_menu

        # Bersihkan input: hapus carriage return, spasi berlebih
        choice=$(echo "$choice" | tr -d '\r' | xargs)

        if [[ -z "$choice" ]]; then
            echo -e "${Y}Input kosong, silakan masukkan pilihan.${N}"
            sleep 1
            continue
        fi

        case "$choice" in
            0)
                echo -e "${G}Bye!${N}"
                cleanup
                exit 0
                ;;
            [Aa])
                echo -e "${Y}📥 Memproses SEMUA file...${N}"
                for i in "${!asset_urls[@]}"; do
                    download_and_install "${asset_urls[$i]}" "${asset_names[$i]}"
                done
                # Setelah selesai semua, kembali ke menu (loop lagi)
                echo -e "${G}✅ Semua file telah diproses.${N}"
                sleep 1
                continue
                ;;
            *)
                # Parsing input: angka dipisah koma atau spasi
                selected=()
                IFS=',' read -ra parts <<< "$choice"
                for part in "${parts[@]}"; do
                    # Hapus spasi di sekitar angka
                    num=$(echo "$part" | xargs)
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#asset_names[@]}" ]; then
                        selected+=($((num-1)))
                    else
                        echo -e "${R}Nomor '$part' tidak valid (harus 1-${#asset_names[@]}).${N}"
                    fi
                done

                if [ ${#selected[@]} -eq 0 ]; then
                    echo -e "${R}Tidak ada nomor valid yang dipilih.${N}"
                    sleep 1
                    continue
                fi

                echo -e "${Y}📥 Memproses ${#selected[@]} file...${N}"
                for idx in "${selected[@]}"; do
                    download_and_install "${asset_urls[$idx]}" "${asset_names[$idx]}"
                done
                # Kembali ke menu
                sleep 1
                continue
                ;;
        esac
    done
}

# =============================================================================
# 9. JALANKAN FUNGSI UTAMA
# =============================================================================
main "$@"
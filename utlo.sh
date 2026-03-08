#!/bin/bash
# ═══════════════════════════════════════════════════════════
# 🎯 GITHUB RELEASE INSTALLER (Vulik/Jawa - Tag: Hai)
# 📦 Versi: 2.2 - Fix kill child processes on interrupt
# 🔧 Fitur: Pilih file 1/2/3 atau ALL, instal otomatis, hapus temp
# ═══════════════════════════════════════════════════════════

VERSION="2.2"

# Direktori temp
TEMP_DIR="$HOME/roblox_installer"
mkdir -p "$TEMP_DIR"

# Warna
G='\e[1;32m'; B='\e[1;34m'; Y='\e[1;33m'; C='\e[1;36m'; R='\e[1;31m'; M='\e[1;35m'; W='\e[1;37m'; BD='\e[1m'; N='\e[0m'

# Array untuk menyimpan PID proses download
declare -a DOWNLOAD_PIDS=()

# Fungsi cleanup yang ditingkatkan
cleanup() {
    echo -e "\n${Y}⚠️  Membersihkan dan menghentikan semua proses...${N}"
    
    # Hentikan semua proses download yang masih berjalan
    for pid in "${DOWNLOAD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        fi
    done
    
    # Hapus file sementara
    rm -rf "$TEMP_DIR"/*
    echo -e "${G}✅ Selesai.${N}"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Cek root
if [ "$(id -u)" -ne 0 ] && ! command -v su &>/dev/null; then
    echo -e "${R}[ERROR] Script ini butuh akses root untuk instalasi!${N}"
    exit 1
fi

# Cek dependensi
check_deps() {
    if ! command -v jq &>/dev/null; then
        echo -e "${Y}⚠️  jq tidak ditemukan. Menginstall...${N}"
        pkg install jq -y 2>/dev/null || apt install jq -y 2>/dev/null
    fi
    if ! command -v curl &>/dev/null; then
        echo -e "${Y}⚠️  curl tidak ditemukan. Menginstall...${N}"
        pkg install curl -y 2>/dev/null || apt install curl -y 2>/dev/null
    fi
}

# Ambil data aset
fetch_assets() {
    local repo="Vulik/Jawa"
    local tag="Hai"
    local api_url="https://api.github.com/repos/$repo/releases/tags/$tag"

    echo -e "${Y}🔍 Mengambil data dari release 'Hai'...${N}"
    release_data=$(curl -s "$api_url")

    if echo "$release_data" | jq -e '.message' >/dev/null 2>&1; then
        echo -e "${R}❌ Release 'Hai' tidak ditemukan.${N}"
        echo -e "${Y}Pesan: $(echo "$release_data" | jq -r '.message')${N}"
        return 1
    fi

    mapfile -t asset_names < <(echo "$release_data" | jq -r '.assets[]?.name')
    mapfile -t asset_urls < <(echo "$release_data" | jq -r '.assets[]?.browser_download_url')

    if [ ${#asset_names[@]} -eq 0 ]; then
        echo -e "${R}❌ Tidak ada file aset.${N}"
        return 1
    fi

    echo -e "${G}✅ Ditemukan ${#asset_names[@]} file.${N}"
}

# Fungsi download dan install
download_and_install() {
    local url="$1"
    local filename="$2"
    local output="$TEMP_DIR/$filename"

    echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${C}[*] Mengunduh: ${W}$filename${N}"
    rm -f "$output"

    # Download dengan progress bar (background)
    curl -L -# -o "$output" "$url" 2>&1 &
    local pid=$!
    DOWNLOAD_PIDS+=("$pid")  # Simpan PID untuk dibunuh nanti jika perlu

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
    wait $pid  # Tunggu selesai dan dapatkan exit code
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
    else
        echo -e "${R}❌ Instalasi gagal! File tetap disimpan di $output${N}"
    fi
}

# Menu pilihan
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

# Fungsi utama
main() {
    clear
    echo -e "${C}════════════════════════════════════════════════════${N}"
    echo -e "${W}   GITHUB RELEASE INSTALLER v${VERSION}${N}"
    echo -e "${C}════════════════════════════════════════════════════${N}"
    check_deps
    fetch_assets || return 1

    while true; do
        show_menu

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
                break
                ;;
            *)
                selected=()
                for num in $(echo "$choice" | tr ',' ' '); do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#asset_names[@]}" ]; then
                        selected+=($((num-1)))
                    fi
                done

                if [ ${#selected[@]} -eq 0 ]; then
                    echo -e "${R}Pilihan tidak valid!${N}"
                    sleep 1
                    continue
                fi

                echo -e "${Y}📥 Memproses ${#selected[@]} file...${N}"
                for idx in "${selected[@]}"; do
                    download_and_install "${asset_urls[$idx]}" "${asset_names[$idx]}"
                done
                break
                ;;
        esac
    done

    echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${G}✅ Semua proses selesai!${N}"
    echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    cleanup
}

main "$@"
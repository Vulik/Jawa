#!/bin/bash
# ═══════════════════════════════════════════════════════════
# 🎯 GITHUB RELEASE DOWNLOADER (Vulik/Jawa - Tag: Hai)
# 📦 Versi: 1.0 - Khusus Satu Release
# 🔧 Fitur: Pilih file 1/2/3 atau ALL
# ═══════════════════════════════════════════════════════════

D="$HOME/downloads_jawa"; mkdir -p "$D"
G='\e[1;32m'; B='\e[1;34m'; Y='\e[1;33m'; C='\e[1;36m'; R='\e[1;31m'; M='\e[1;35m'; W='\e[1;37m'; BD='\e[1m'; N='\e[0m'

# ═══════════════════════════════════════════════════════════
# 🛠️  CEK DEPENDENSI
# ═══════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════
# 📦 AMBIL DATA ASSET DARI RELEASE "Hai"
# ═══════════════════════════════════════════════════════════
fetch_assets() {
    local repo="Vulik/Jawa"
    local tag="Hai"
    local api_url="https://api.github.com/repos/$repo/releases/tags/$tag"
    
    echo -e "${Y}🔍 Mengambil data dari release 'Hai'...${N}"
    release_data=$(curl -s "$api_url")
    
    # Cek apakah release ditemukan
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
}

# ═══════════════════════════════════════════════════════════
# ⏬ FUNGSI DOWNLOAD (dengan progress bar)
# ═══════════════════════════════════════════════════════════
download_file() {
    local url="$1"
    local filename="$2"
    local output="$D/$filename"
    
    echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${C}[*] Mengunduh: ${W}$filename${N}"
    rm -f "$output"
    
    # Unduh dengan curl, tampilkan progress bar sederhana
    curl -L -# -o "$output" "$url" 2>&1 &
    local pid=$!
    
    # Progress bar ala script sebelumnya
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
    echo -ne "\r${B}    [${C}████████████████████${N}${B}] ${W}100%${N}\n"
    
    if [ -f "$output" ] && [ -s "$output" ]; then
        echo -e "${G}✅ Selesai: ${B}$output${N}"
    else
        echo -e "${R}❌ Gagal mengunduh $filename${N}"
    fi
}

# ═══════════════════════════════════════════════════════════
# 🎯 MENU PILIHAN
# ═══════════════════════════════════════════════════════════
show_menu() {
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${W}${BD}   FILE TERSEDIA DI RELEASE 'Hai'${N}"
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    
    for i in "${!asset_names[@]}"; do
        echo -e "${B}  [$((i+1))] ${W}${asset_names[$i]}${N}"
    done
    
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${Y}  [A] Download SEMUA file sekaligus${N}"
    echo -e "${W}  [0] Keluar${N}"
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    read -p "Pilih opsi (contoh: 1,2,3 atau A): " choice
}

# ═══════════════════════════════════════════════════════════
# 🚀 FUNGSI UTAMA
# ═══════════════════════════════════════════════════════════
main() {
    check_deps
    fetch_assets || return 1
    
    while true; do
        show_menu
        
        case "$choice" in
            0)
                echo -e "${G}Bye!${N}"
                exit 0
                ;;
            [Aa])
                echo -e "${Y}📥 Mendownload SEMUA file...${N}"
                for i in "${!asset_urls[@]}"; do
                    download_file "${asset_urls[$i]}" "${asset_names[$i]}"
                done
                break
                ;;
            *)
                # Cek apakah input berupa angka atau rentang (1,2,3)
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
                
                echo -e "${Y}📥 Mendownload ${#selected[@]} file...${N}"
                for idx in "${selected[@]}"; do
                    download_file "${asset_urls[$idx]}" "${asset_names[$idx]}"
                done
                break
                ;;
        esac
    done
    
    echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${G}✅ Semua unduhan selesai! File tersimpan di:${N}"
    echo -e "${B}   $D${N}"
    echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
}

# ═══════════════════════════════════════════════════════════
# 🏁 EKSEKUSI
# ═══════════════════════════════════════════════════════════
main "$@"
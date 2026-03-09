#!/bin/bash
# =============================================================================
# 💉 Roblox Cookie Injector - Pilih Aplikasi dan Cookie
# Versi: 1.0 - Inject cookie ke aplikasi Roblox (root required)
# =============================================================================

VERSION="1.0"

# Warna
G='\e[1;32m'; B='\e[1;34m'; Y='\e[1;33m'; C='\e[1;36m'; R='\e[1;31m'; N='\e[0m'

# Cek root
if [ "$(id -u)" -ne 0 ] && ! command -v su &>/dev/null; then
    echo -e "${R}[ERROR] Script ini butuh akses root!${N}"
    exit 1
fi

# Header
clear
echo -e "${C}════════════════════════════════════════════════════${N}"
echo -e "${W}   Roblox Cookie Injector v${VERSION}${N}"
echo -e "${C}════════════════════════════════════════════════════${N}"
echo ""

# =============================================================================
# 1. Dapatkan daftar paket Roblox
# =============================================================================
mapfile -t packages < <(pm list packages | grep -iE "roblox|nomercy|delta|codex|ronix|arceus" | cut -d: -f2)

if [ ${#packages[@]} -eq 0 ]; then
    echo -e "${Y}Tidak ada aplikasi Roblox terinstall.${N}"
    exit 0
fi

echo -e "${B}Pilih aplikasi target:${N}"
for i in "${!packages[@]}"; do
    echo -e "${B}  [$((i+1))] ${W}${packages[$i]}${N}"
done
echo -e "${B}  [0] ${Y}Batal${N}"
read -p "Pilih nomor: " pkg_choice

if [[ "$pkg_choice" == "0" ]]; then
    exit 0
fi

if ! [[ "$pkg_choice" =~ ^[0-9]+$ ]] || [ "$pkg_choice" -lt 1 ] || [ "$pkg_choice" -gt "${#packages[@]}" ]; then
    echo -e "${R}Pilihan tidak valid.${N}"
    exit 1
fi

selected_pkg="${packages[$((pkg_choice-1))]}"
echo -e "${G}Aplikasi dipilih: $selected_pkg${N}"
echo ""

# =============================================================================
# 2. Pilih sumber cookie
# =============================================================================
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${W}Pilih sumber cookie:${N}"
echo -e "${B}  [1] ${Y}Dari file /sdcard/listcookie/cookie${N}"
echo -e "${B}  [2] ${Y}Masukkan cookie manual${N}"
echo -e "${B}  [0] ${Y}Batal${N}"
read -p "Pilih: " src_choice

case $src_choice in
    0) exit 0 ;;
    1)
        COOKIE_FILE="/sdcard/listcookie/cookie"
        if [ ! -f "$COOKIE_FILE" ]; then
            echo -e "${R}File $COOKIE_FILE tidak ditemukan.${N}"
            exit 1
        fi
        # Baca file, tampilkan daftar cookie (username)
        mapfile -t cookie_lines < "$COOKIE_FILE"
        # Filter baris yang mengandung ":" (username:cookie)
        valid_cookies=()
        for line in "${cookie_lines[@]}"; do
            if [[ "$line" == *:* ]]; then
                valid_cookies+=("$line")
            fi
        done

        if [ ${#valid_cookies[@]} -eq 0 ]; then
            echo -e "${R}Tidak ada cookie valid di file.${N}"
            exit 1
        fi

        echo -e "${B}Pilih cookie yang akan diinject:${N}"
        for i in "${!valid_cookies[@]}"; do
            username=$(echo "${valid_cookies[$i]}" | cut -d: -f1)
            echo -e "${B}  [$((i+1))] ${W}$username${N}"
        done
        echo -e "${B}  [0] ${Y}Batal${N}"
        read -p "Pilih nomor: " cookie_choice

        if [[ "$cookie_choice" == "0" ]]; then
            exit 0
        fi

        if ! [[ "$cookie_choice" =~ ^[0-9]+$ ]] || [ "$cookie_choice" -lt 1 ] || [ "$cookie_choice" -gt "${#valid_cookies[@]}" ]; then
            echo -e "${R}Pilihan tidak valid.${N}"
            exit 1
        fi

        selected_line="${valid_cookies[$((cookie_choice-1))]}"
        username=$(echo "$selected_line" | cut -d: -f1)
        cookie=$(echo "$selected_line" | cut -d: -f2-)
        echo -e "${G}Dipilih: $username${N}"
        ;;
    2)
        read -p "Masukkan cookie .ROBLOSECURITY: " cookie
        if [ -z "$cookie" ]; then
            echo -e "${R}Cookie tidak boleh kosong.${N}"
            exit 1
        fi
        username="Manual"
        ;;
    *)
        echo -e "${R}Pilihan tidak valid.${N}"
        exit 1
        ;;
esac

# =============================================================================
# 3. Konfirmasi
# =============================================================================
echo ""
echo -e "${Y}Akan menginject cookie ke:${N}"
echo -e "  Aplikasi: $selected_pkg"
echo -e "  Username: $username"
echo -e "  Cookie: ${cookie:0:20}...${cookie: -10}"
read -p "Lanjutkan? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${Y}Dibatalkan.${N}"
    exit 0
fi

# =============================================================================
# 4. Proses inject
# =============================================================================
echo -e "${Y}📦 Memproses inject...${N}"

# Hentikan aplikasi
su -c "am force-stop $selected_pkg" </dev/null >/dev/null 2>&1

# Hapus data aplikasi (clear)
su -c "pm clear $selected_pkg" </dev/null >/dev/null 2>&1
sleep 1

# Escape cookie untuk XML
cookie_escaped=$(printf '%s' "$cookie" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g')

# Tentukan file preferences
PREF_DIR="/data/data/$selected_pkg/shared_prefs"
su -c "mkdir -p $PREF_DIR"

# Coba beberapa nama file umum
PREF_FILES=(
    "com.roblox.client_preferences.xml"
    "RobloxPreferences.xml"
    "${selected_pkg}_preferences.xml"
    "com.roblox.client.xml"
)

PREF_FILE=""
for f in "${PREF_FILES[@]}"; do
    if su -c "test -f $PREF_DIR/$f" 2>/dev/null; then
        PREF_FILE="$PREF_DIR/$f"
        break
    fi
done

if [ -z "$PREF_FILE" ]; then
    # Gunakan nama default
    PREF_FILE="$PREF_DIR/com.roblox.client_preferences.xml"
fi

# Tulis file XML
su -c "cat > '$PREF_FILE' << 'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name=\"ROBLOSECURITY\">${cookie_escaped}</string>
</map>
EOF" </dev/null >/dev/null 2>&1

# Set permission
uid=$(su -c "stat -c '%u' /data/data/$selected_pkg" 2>/dev/null)
[ -z "$uid" ] && uid=10000
su -c "chown $uid:$uid '$PREF_FILE'" 2>/dev/null
su -c "chmod 660 '$PREF_FILE'" 2>/dev/null
su -c "chmod 755 '$PREF_DIR'" 2>/dev/null
su -c "restorecon '$PREF_FILE'" 2>/dev/null

# Verifikasi
if su -c "grep -q 'ROBLOSECURITY' '$PREF_FILE'" 2>/dev/null; then
    echo -e "${G}✅ Cookie berhasil diinject!${N}"
else
    echo -e "${R}❌ Gagal menulis file preferences.${N}"
    exit 1
fi

# Jalankan aplikasi
echo -e "${Y}🚀 Membuka aplikasi...${N}"
su -c "monkey -p $selected_pkg -c android.intent.category.LAUNCHER 1" </dev/null >/dev/null 2>&1 &

echo -e "${G}Selesai. Aplikasi akan terbuka dalam beberapa detik.${N}"

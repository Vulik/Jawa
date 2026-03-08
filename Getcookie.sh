#!/bin/bash
# =============================================================================
# 🍪 Roblox Cookie Extractor (Semua Aplikasi) - Output ke File
# Versi: 2.1 - Hanya username:cookie per baris
# =============================================================================

# Cek root
if [ "$(id -u)" -ne 0 ] && ! command -v su &>/dev/null; then
    echo "ERROR: Butuh akses root"
    exit 1
fi

# Cek curl
if ! command -v curl &>/dev/null; then
    echo "ERROR: curl tidak ditemukan. Install dengan: pkg install curl"
    exit 1
fi

# Cek grep
if ! command -v grep &>/dev/null; then
    echo "ERROR: grep tidak ditemukan"
    exit 1
fi

# Buat direktori output
OUTPUT_DIR="/sdcard/listcookie"
OUTPUT_FILE="$OUTPUT_DIR/cookie"
mkdir -p "$OUTPUT_DIR"

# Kosongkan file (atau buat baru)
> "$OUTPUT_FILE"

# Cari semua paket yang mungkin mengandung Roblox
packages=$(pm list packages | grep -iE "roblox|nomercy|delta|codex|ronix|arceus" | cut -d: -f2)

if [ -z "$packages" ]; then
    echo "Tidak ada aplikasi Roblox terinstall"
    exit 0
fi

# Buat direktori temp
TEMP_DIR="/data/local/tmp/roblox_cookies"
su -c "mkdir -p $TEMP_DIR"

found_any=false

for pkg in $packages; do
    echo "Memeriksa: $pkg" >&2
    cookie=""
    
    # Method 1: Shared Preferences (XML)
    PREFS_DIR="/data/data/$pkg/shared_prefs"
    if su -c "test -d $PREFS_DIR"; then
        for xml in $(su -c "ls $PREFS_DIR/*.xml 2>/dev/null"); do
            content=$(su -c "cat '$xml' 2>/dev/null")
            if echo "$content" | grep -q "ROBLOSECURITY"; then
                cookie=$(echo "$content" | sed -n 's/.*name="[^"]*ROBLOSECURITY[^"]*"[^>]*>\([^<]*\)<.*/\1/p' | head -n1)
                if [ -n "$cookie" ]; then
                    break
                fi
            fi
        done
    fi
    
    # Method 2: Database WebView (fallback)
    if [ -z "$cookie" ]; then
        DB_PATH="/data/data/$pkg/app_webview/Default/Cookies"
        if su -c "test -f $DB_PATH"; then
            TMP_DB="$TEMP_DIR/cookies_$pkg.db"
            su -c "cp '$DB_PATH' '$TMP_DB'" 2>/dev/null
            if command -v sqlite3 &>/dev/null; then
                cookie=$(sqlite3 "$TMP_DB" "SELECT value FROM cookies WHERE host_key LIKE '%.roblox.com' AND name='.ROBLOSECURITY' LIMIT 1;" 2>/dev/null)
            fi
            rm -f "$TMP_DB"
        fi
    fi
    
    # Jika cookie ditemukan, proses dan simpan
    if [ -n "$cookie" ]; then
        # Bersihkan cookie
        cookie=$(echo "$cookie" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n\t')
        if [[ "$cookie" == *"%"* ]]; then
            cookie=$(printf '%b' "${cookie//%/\\x}" 2>/dev/null || echo "$cookie")
        fi
        
        # Ambil username
        username=$(curl -s --connect-timeout 5 -A "Roblox/2.610.528 (Linux; Android)" -H "Cookie: .ROBLOSECURITY=$cookie" "https://users.roblox.com/v1/users/authenticated" | grep -oP '"name":"\K[^"]+' | head -n1)
        [ -z "$username" ] && username="Unknown"
        
        # Tampilkan di console
        echo "  ✓ Ditemukan: $username" >&2
        
        # Simpan ke file (hanya username:cookie)
        echo "${username}:${cookie}" >> "$OUTPUT_FILE"
        
        found_any=true
    else
        echo "  ✗ Tidak ditemukan" >&2
    fi
done

# Bersihkan temp
su -c "rm -rf $TEMP_DIR"

if [ "$found_any" = false ]; then
    echo "Tidak ditemukan cookie di aplikasi manapun" >&2
else
    echo "✅ Semua cookie disimpan di: $OUTPUT_FILE" >&2
    echo "   (format: username:cookie per baris)" >&2
fi
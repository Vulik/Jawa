#!/bin/bash
# =============================================================================
# 🍪 Roblox Cookie Extractor (Format: username@:cookie)
# Versi: 1.1 - Lebih robust, dengan fallback database WebView
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

# Cek grep (opsional, tapi kita butuh)
if ! command -v grep &>/dev/null; then
    echo "ERROR: grep tidak ditemukan"
    exit 1
fi

# Cari paket Roblox (tambah lebih banyak keyword)
packages=$(pm list packages | grep -iE "roblox|nomercy|delta|codex|ronix|arceus" | cut -d: -f2)

if [ -z "$packages" ]; then
    echo "Tidak ada aplikasi Roblox terinstall"
    exit 0
fi

# Buat direktori temp (untuk fallback database)
TEMP_DIR="/data/local/tmp/roblox_cookies"
su -c "mkdir -p $TEMP_DIR"

found=false
for pkg in $packages; do
    # --- Method 1: Shared Preferences (XML) ---
    PREFS_DIR="/data/data/$pkg/shared_prefs"
    if su -c "test -d $PREFS_DIR"; then
        for xml in $(su -c "ls $PREFS_DIR/*.xml 2>/dev/null"); do
            content=$(su -c "cat '$xml' 2>/dev/null")
            # Ekstrak cookie (tanpa -P jika tidak didukung)
            if echo "$content" | grep -q "ROBLOSECURITY"; then
                cookie=$(echo "$content" | sed -n 's/.*name="[^"]*ROBLOSECURITY[^"]*"[^>]*>\([^<]*\)<.*/\1/p' | head -n1)
                if [ -n "$cookie" ]; then
                    # Bersihkan
                    cookie=$(echo "$cookie" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n\t')
                    # Decode URL
                    if [[ "$cookie" == *"%"* ]]; then
                        cookie=$(printf '%b' "${cookie//%/\\x}" 2>/dev/null || echo "$cookie")
                    fi
                    found=true
                    break 2
                fi
            fi
        done
    fi

    # --- Method 2: Database WebView (fallback) ---
    if [ "$found" = false ]; then
        DB_PATH="/data/data/$pkg/app_webview/Default/Cookies"
        if su -c "test -f $DB_PATH"; then
            TMP_DB="$TEMP_DIR/cookies_$pkg.db"
            su -c "cp '$DB_PATH' '$TMP_DB'" 2>/dev/null
            if command -v sqlite3 &>/dev/null; then
                cookie=$(sqlite3 "$TMP_DB" "SELECT value FROM cookies WHERE host_key LIKE '%.roblox.com' AND name='.ROBLOSECURITY' LIMIT 1;" 2>/dev/null)
                if [ -n "$cookie" ]; then
                    found=true
                    break
                fi
            fi
            rm -f "$TMP_DB"
        fi
    fi
done

# Bersihkan temp
su -c "rm -rf $TEMP_DIR"

if [ "$found" = false ]; then
    echo "Tidak ditemukan cookie"
    exit 0
fi

# Ambil username dari API Roblox (dengan User-Agent)
username=$(curl -s --connect-timeout 5 -A "Roblox/2.610.528 (Linux; Android)" -H "Cookie: .ROBLOSECURITY=$cookie" "https://users.roblox.com/v1/users/authenticated" | grep -oP '"name":"\K[^"]+' | head -n1)
[ -z "$username" ] && username="Unknown"

# Output format: username@:cookie
echo "${username}@:${cookie}"

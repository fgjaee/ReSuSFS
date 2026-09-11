#!/system/bin/sh
#title=Developer options / ADB mode
#author=ahmed-alnassif
#desc=Leaves ADB unchanged by default; disabling requires explicit confirmation

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
PERSISTENT_DIR="${SUSAF_PERSISTENT_DIR:-/data/adb/SusAF}"

. "$MODULE_DIR/lib/adb-mode.sh" || {
	echo "[-] ADB mode library not found"
	exit 1
}

if apply_adb_mode "$PERSISTENT_DIR/config.txt"; then
	echo "[+] Developer options / ADB mode applied"
else
	echo "[-] Developer options / ADB mode was not applied; see state/adb_mode.report.txt"
	exit 1
fi

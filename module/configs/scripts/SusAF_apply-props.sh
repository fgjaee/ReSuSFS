#!/system/bin/sh
#title=Sanitize verified-boot errors
#author=ahmed-alnassif
#desc=Removes verifiedbooterror and verifyerrorpart without rewriting build identity

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH

command -v resetprop >/dev/null 2>&1 || {
	echo "[*] resetprop unavailable; verified-boot properties left unchanged"
	exit 0
}

resetprop | awk -F'[][]' '{print $2}' | while IFS= read -r prop; do
	case "$prop" in
		*verifiedbooterror|*verifyerrorpart)
			resetprop -d "$prop" 2>/dev/null
			resetprop -d -p "$prop" 2>/dev/null
			;;
	esac
done
resetprop -d ro.boot.verifiedbooterror 2>/dev/null
resetprop -d -p ro.boot.verifiedbooterror 2>/dev/null
resetprop -d ro.boot.verifyerrorpart 2>/dev/null
resetprop -d -p ro.boot.verifyerrorpart 2>/dev/null

echo "[+] verified-boot error properties sanitized"
echo "[*] build, product, lock-state, and ADB properties were left unchanged"

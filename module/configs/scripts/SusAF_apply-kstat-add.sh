#!/system/bin/sh
#title=Hide kstat
#author=ahmed-alnassif
#desc=Hides file stats for framework-managed paths

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
PERSISTENT_DIR="${SUSAF_PERSISTENT_DIR:-/data/adb/SusAF}"
STATE_DIR="$PERSISTENT_DIR/state"
LIST_FILE="$STATE_DIR/kstat.generated.txt"
TEMP_FILE="$STATE_DIR/.kstat.generated.$$"

run_susaf() {
	if [ -n "${SUSAF_CLI_COMMAND:-}" ]; then
		"$SUSAF_CLI_COMMAND" "$@"
	else
		sh "$MODULE_DIR/SusAF.sh" "$@"
	fi
}

umask 077
mkdir -p "$STATE_DIR" || exit 1
chmod 700 "$STATE_DIR" 2>/dev/null
trap 'rm -f "$TEMP_FILE"' EXIT HUP INT TERM

cat > "$TEMP_FILE" << EOF
/data/local/tmp 100 default default 4096 default default default default default default 8 4096
/data/adb/SusAF default default default default default default default default default default default default
EOF
chmod 600 "$TEMP_FILE" 2>/dev/null
mv "$TEMP_FILE" "$LIST_FILE" || exit 1

if run_susaf --apply-kstat-add-direct "$LIST_FILE"; then
	echo "[+] kstat spoof applied successfully"
	echo "[*] reboot recommended for the spoofed stats to take effect"
else
	echo "[-] kstat spoof apply failed"
	echo "[*] reboot not required"
fi

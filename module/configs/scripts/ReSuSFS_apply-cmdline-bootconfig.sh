#!/system/bin/sh
#title=Spoof cmdline
#author=ahmed-alnassif
#desc=Hides bootloader unlock state from kernel cmdline/bootconfig

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
PERSISTENT_DIR="${SUSAF_PERSISTENT_DIR:-/data/adb/SusAF}"
STATE_DIR="$PERSISTENT_DIR/state"
OUTPUT_FILE="$STATE_DIR/cmdline_or_bootconfig.generated.txt"
TEMP_FILE="$STATE_DIR/.cmdline_or_bootconfig.generated.$$"
SOURCE_RECORD="$STATE_DIR/cmdline_or_bootconfig.source"
SOURCE_TEMP="$STATE_DIR/.cmdline_or_bootconfig.source.$$"

. "$MODULE_DIR/lib/boot-state.sh" || {
	echo "[-] boot-state sanitizer library not found"
	exit 1
}

if [ -s "${SUSAF_BOOTCONFIG_SOURCE:-/proc/bootconfig}" ]; then
	SOURCE_PATH="${SUSAF_BOOTCONFIG_SOURCE:-/proc/bootconfig}"
	SOURCE_FORMAT="bootconfig"
else
	SOURCE_PATH="${SUSAF_CMDLINE_SOURCE:-/proc/cmdline}"
	SOURCE_FORMAT="cmdline"
fi

umask 077
mkdir -p "$STATE_DIR" || exit 1
chmod 700 "$STATE_DIR" 2>/dev/null
trap 'rm -f "$TEMP_FILE" "$SOURCE_TEMP"' EXIT HUP INT TERM

if [ "$SOURCE_FORMAT" = "bootconfig" ]; then
	sanitize_bootconfig_file "$SOURCE_PATH" "$TEMP_FILE" || exit 1
else
	sanitize_cmdline_file "$SOURCE_PATH" "$TEMP_FILE" || exit 1
fi

[ -s "$TEMP_FILE" ] || {
	echo "[-] generated cmdline/bootconfig is empty"
	exit 1
}
chmod 600 "$TEMP_FILE" 2>/dev/null
mv "$TEMP_FILE" "$OUTPUT_FILE" || exit 1
printf '%s\n' "$SOURCE_PATH" > "$SOURCE_TEMP" || exit 1
chmod 600 "$SOURCE_TEMP" 2>/dev/null
mv "$SOURCE_TEMP" "$SOURCE_RECORD" || exit 1

if SusAF --apply-cmdline-bootconfig-direct "$OUTPUT_FILE"; then
	echo "[+] cmdline/bootconfig spoof applied successfully
[*] generated fresh from $SOURCE_PATH; user config was not modified"
else
	echo "[-] cmdline/bootconfig spoof apply failed
[*] reboot not required"
fi

#!/system/bin/sh
#title=Spoof uname
#author=ahmed-alnassif
#desc=Spoofs kernel version and build info from uname

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH

MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
PERSISTENT_DIR="${SUSAF_PERSISTENT_DIR:-/data/adb/SusAF}"
CONF_FILE="${SUSAF_UNAME_OUTPUT:-$PERSISTENT_DIR/tmp_uname.txt}"
PROC_VERSION_FILE="${SUSAF_PROC_VERSION:-/proc/version}"
BOOT_ID_FILE="${SUSAF_BOOT_ID:-/proc/sys/kernel/random/boot_id}"
SUSAF_COMMAND="${SUSAF_CLI_COMMAND:-SusAF}"

[ -r "$MODULE_DIR/lib/ksud.sh" ] && . "$MODULE_DIR/lib/ksud.sh"
KSUD_BIN=$(resolve_ksud_bin 2>/dev/null) || KSUD_BIN=""

base_ver=$(awk '{print $3}' "$PROC_VERSION_FILE" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
build_info="#1 SMP PREEMPT $(getprop ro.build.date | tr -s ' ')"

if [ -n "$KSUD_BIN" ] && current_kmi=$("$KSUD_BIN" boot-info current-kmi 2>/dev/null); then
	kmi_tag=$(printf '%s\n' "$current_kmi" | cut -d'-' -f1)
	final_release="${base_ver}-${kmi_tag}-11-g$(tr -d '-' < "$BOOT_ID_FILE" | cut -c1-12)"
else
	final_release="${base_ver}-g$(tr -d '-' < "$BOOT_ID_FILE" | cut -c1-8)"
fi

cat > "$CONF_FILE" << EOF
release=${final_release}
version=${build_info}
EOF

if "$SUSAF_COMMAND" --apply-uname "$CONF_FILE"; then
	echo "[+] uname spoofed successfully"
	echo "[*] reboot recommended for processes started after boot to consistently observe the spoofed values"
else
	echo "[-] uname spoof apply failed"
	echo "[*] reboot not required"
fi

rm -f "$CONF_FILE"

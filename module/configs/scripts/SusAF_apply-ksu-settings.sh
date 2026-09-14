#!/system/bin/sh
#title=Set SELinux hide
#author=ahmed-alnassif
#desc=Enables KernelSU SELinux hiding when supported

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_ID="${SUSAF_MODULE_ID:-susaf}"
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"

[ -r "$MODULE_DIR/lib/ksud.sh" ] && . "$MODULE_DIR/lib/ksud.sh"
KSUD_BIN=$(resolve_ksud_bin 2>/dev/null) || KSUD_BIN=""
[ -n "$KSUD_BIN" ] || {
	echo "[*] KernelSU daemon unavailable; selinux_hide left unchanged"
	exit 0
}

status=$("$KSUD_BIN" feature check selinux_hide 2>/dev/null) || status=unavailable
case "$status" in
	supported|managed)
		if KSU_MODULE="$MODULE_ID" "$KSUD_BIN" feature set selinux_hide 1; then
			echo "[+] selinux_hide enabled"
		else
			echo "[-] selinux_hide is managed by another module or could not be set"
			exit 1
		fi
		;;
	*)
		echo "[*] selinux_hide not supported; left unchanged"
		exit 0
		;;
esac

echo "[*] no reboot required"

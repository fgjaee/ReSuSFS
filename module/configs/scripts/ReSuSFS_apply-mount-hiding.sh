#!/system/bin/sh
#title=Hide mounts
#author=ahmed-alnassif
#desc=Hides module mounts redirected to system paths

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
PERSISTENT_DIR="${SUSAF_PERSISTENT_DIR:-/data/adb/SusAF}"
MOUNTINFO_FILE="${SUSAF_MOUNTINFO:-/proc/1/mountinfo}"
STATE_DIR="$PERSISTENT_DIR/state"
LIST_FILE="$STATE_DIR/mount_hiding.generated.txt"
CANDIDATE_FILE="$STATE_DIR/.mount_hiding.candidates.$$"
TEMP_FILE="$STATE_DIR/.mount_hiding.generated.$$"

. "$MODULE_DIR/lib/kernel-umount.sh" || {
	echo "[-] mountinfo parser library not found"
	exit 1
}

umask 077
mkdir -p "$STATE_DIR" || exit 1
chmod 700 "$STATE_DIR" 2>/dev/null
trap 'rm -f "$CANDIDATE_FILE" "$TEMP_FILE"' EXIT HUP INT TERM
: > "$TEMP_FILE"

collect_kernel_umount_candidates "$MOUNTINFO_FILE" "$CANDIDATE_FILE" || {
	echo "[-] could not parse $MOUNTINFO_FILE"
	exit 1
}

while IFS="$(printf '\t')" read -r mount_point reason || [ -n "$mount_point" ]; do
	[ -n "$mount_point" ] || continue
	if kernel_umount_target_is_safe "$mount_point" && kernel_umount_target_is_mounted "$MOUNTINFO_FILE" "$mount_point"; then
		printf '%s\n' "$mount_point" >> "$TEMP_FILE"
	else
		echo "[!] rejected mount target: $mount_point ($reason)"
	fi
done < "$CANDIDATE_FILE"

sort -u "$TEMP_FILE" -o "$TEMP_FILE"
chmod 600 "$TEMP_FILE" 2>/dev/null
mv "$TEMP_FILE" "$LIST_FILE" || exit 1

if [ -s "$LIST_FILE" ]; then
	if SusAF --apply-sus-paths-loop-direct "$LIST_FILE"; then
		echo "[+] mount hiding applied successfully"
		echo "[*] generated from validated KSU/module-backed mountinfo entries"
	else
		echo "[-] mount hiding apply failed"
		echo "[*] no reboot required"
	fi
else
	echo "[*] no suspicious mounts found, nothing applied"
	echo "[*] no reboot required"
fi

#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/source"
EXPORT_DIR="$TEST_ROOT/export"
mkdir -p "$PERSISTENT_DIR/scripts" "$PERSISTENT_DIR/state" "$EXPORT_DIR"

if [ -n "${SUSAF_TEST_BUSYBOX:-}" ]; then
	SUSAF_BUSYBOX_BIN="$SUSAF_TEST_BUSYBOX"
elif command -v busybox >/dev/null 2>&1; then
	SUSAF_BUSYBOX_BIN=$(command -v busybox)
else
	mkdir -p "$TEST_ROOT/bin"
	cat > "$TEST_ROOT/bin/busybox" <<'EOF'
#!/bin/sh
[ "$1" = tar ] || exit 127
shift
exec tar "$@"
EOF
	chmod 755 "$TEST_ROOT/bin/busybox"
	SUSAF_BUSYBOX_BIN="$TEST_ROOT/bin/busybox"
fi
SUSAF_EXPORT_DIR="$EXPORT_DIR"
export PERSISTENT_DIR SUSAF_BUSYBOX_BIN SUSAF_EXPORT_DIR

. "$MODULE_DIR/lib/backup-restore.sh"

printf 'new-config\n' > "$PERSISTENT_DIR/config.txt"
printf 'Max_Saturation.sh\n' > "$PERSISTENT_DIR/scripts_bootcompleted.txt"
cat > "$PERSISTENT_DIR/scripts/Max_Saturation.sh" <<'EOF'
#!/system/bin/sh
#title=Max Saturation
printf 'preserved\n'
EOF
chmod 755 "$PERSISTENT_DIR/scripts/Max_Saturation.sh"
printf 'private runtime state\n' > "$PERSISTENT_DIR/state/secret.txt"

export_output=$(export_susaf_config)
archive=$(printf '%s\n' "$export_output" | sed -n 's/^SUSAF_EXPORT_PATH=//p')
[ -f "$archive" ]
"$SUSAF_BUSYBOX_BIN" tar tzf "$archive" | grep -Eq '(^|/)config.txt$'
"$SUSAF_BUSYBOX_BIN" tar tzf "$archive" | grep -Eq '(^|/)scripts/Max_Saturation.sh$'
! "$SUSAF_BUSYBOX_BIN" tar tzf "$archive" | grep -Fq 'secret.txt'

PERSISTENT_DIR="$TEST_ROOT/live"
export PERSISTENT_DIR
mkdir -p "$PERSISTENT_DIR/scripts"
printf 'old-config\n' > "$PERSISTENT_DIR/config.txt"
printf 'old-script\n' > "$PERSISTENT_DIR/scripts/Max_Saturation.sh"
SUSAF_RESTORE_TIMESTAMP=20260912_120000
export SUSAF_RESTORE_TIMESTAMP

restore_susaf_config "$archive"
grep -Fqx 'new-config' "$PERSISTENT_DIR/config.txt"
cmp "$TEST_ROOT/source/scripts/Max_Saturation.sh" "$PERSISTENT_DIR/scripts/Max_Saturation.sh"
grep -Fqx 'old-config' "$PERSISTENT_DIR/restore/20260912_120000/replaced/config.txt"
grep -Fqx 'old-script' "$PERSISTENT_DIR/restore/20260912_120000/replaced/scripts/Max_Saturation.sh"
grep -Fqx 'rollback=not-needed' "$PERSISTENT_DIR/state/restore.report.txt"
grep -Fqx 'result=restored' "$PERSISTENT_DIR/state/restore.report.txt"

write_manifest() {
	mkdir -p "$1"
	cat > "$1/.susaf-backup-manifest" <<'EOF'
schema=1
module_id=susaf
format=tar.gz
EOF
}

# A symlink member is rejected before it can be merged into live config.
SYMLINK_PAYLOAD="$TEST_ROOT/symlink-payload"
write_manifest "$SYMLINK_PAYLOAD"
printf 'attacker\n' > "$SYMLINK_PAYLOAD/config.txt"
ln -s /data/adb "$SYMLINK_PAYLOAD/escape"
tar czf "$TEST_ROOT/symlink.tar.gz" -C "$SYMLINK_PAYLOAD" .
printf 'safe-before-symlink\n' > "$PERSISTENT_DIR/config.txt"
set +e
restore_susaf_config "$TEST_ROOT/symlink.tar.gz"
symlink_status=$?
set -e
[ "$symlink_status" -eq 1 ]
grep -Fqx 'safe-before-symlink' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'result=unsafe-member-type' "$PERSISTENT_DIR/state/restore.report.txt"

# BusyBox's alternate hard-link listing format is rejected as well.
HARDLINK_PAYLOAD="$TEST_ROOT/hardlink-payload"
write_manifest "$HARDLINK_PAYLOAD"
printf 'linked\n' > "$HARDLINK_PAYLOAD/config.txt"
ln "$HARDLINK_PAYLOAD/config.txt" "$HARDLINK_PAYLOAD/uname.txt"
tar czf "$TEST_ROOT/hardlink.tar.gz" -C "$HARDLINK_PAYLOAD" \
	.susaf-backup-manifest config.txt uname.txt
set +e
restore_susaf_config "$TEST_ROOT/hardlink.tar.gz"
hardlink_status=$?
set -e
[ "$hardlink_status" -eq 1 ]
grep -Fqx 'safe-before-symlink' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'result=unsafe-member-type' "$PERSISTENT_DIR/state/restore.report.txt"

# Traversal is rejected from the member list, before archive extraction.
TRAVERSAL_PAYLOAD="$TEST_ROOT/traversal-payload"
write_manifest "$TRAVERSAL_PAYLOAD"
printf 'escape\n' > "$TRAVERSAL_PAYLOAD/config.txt"
tar czf "$TEST_ROOT/traversal.tar.gz" -C "$TRAVERSAL_PAYLOAD" \
	.susaf-backup-manifest --transform='s#^config.txt$#../escaped.txt#' config.txt
set +e
restore_susaf_config "$TEST_ROOT/traversal.tar.gz"
traversal_status=$?
set -e
[ "$traversal_status" -eq 1 ]
[ ! -e "$TEST_ROOT/escaped.txt" ]
grep -Fqx 'safe-before-symlink' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'result=unsafe-member' "$PERSISTENT_DIR/state/restore.report.txt"

# The declared uncompressed size is bounded before extraction.
SIZE_PAYLOAD="$TEST_ROOT/size-payload"
write_manifest "$SIZE_PAYLOAD"
printf '%0200d\n' 0 > "$SIZE_PAYLOAD/config.txt"
tar czf "$TEST_ROOT/oversized.tar.gz" -C "$SIZE_PAYLOAD" .
SUSAF_BACKUP_MAX_TOTAL_BYTES=100
set +e
restore_susaf_config "$TEST_ROOT/oversized.tar.gz"
size_status=$?
set -e
[ "$size_status" -eq 1 ]
grep -Fqx 'result=extracted-size-invalid' "$PERSISTENT_DIR/state/restore.report.txt"
SUSAF_BACKUP_MAX_TOTAL_BYTES=67108864

# If a staged merge fails after one file, every installed file is rolled back.
ROLLBACK_PAYLOAD="$TEST_ROOT/rollback-payload"
write_manifest "$ROLLBACK_PAYLOAD"
printf 'replacement-config\n' > "$ROLLBACK_PAYLOAD/config.txt"
printf '/replacement\n' > "$ROLLBACK_PAYLOAD/kernel_umount.txt"
tar czf "$TEST_ROOT/rollback.tar.gz" -C "$ROLLBACK_PAYLOAD" .
printf 'original-config\n' > "$PERSISTENT_DIR/config.txt"
printf '/original\n' > "$PERSISTENT_DIR/kernel_umount.txt"
SUSAF_FAIL_COPY_ONCE=1
cp() {
	last=''
	for argument in "$@"; do last="$argument"; done
	case "$last" in
		"$PERSISTENT_DIR/kernel_umount.txt.restore."*)
			if [ "$SUSAF_FAIL_COPY_ONCE" = 1 ]; then
				SUSAF_FAIL_COPY_ONCE=0
				return 1
			fi
			;;
	esac
	command cp "$@"
}
set +e
restore_susaf_config "$TEST_ROOT/rollback.tar.gz"
rollback_status=$?
set -e
[ "$rollback_status" -eq 1 ]
grep -Fqx 'original-config' "$PERSISTENT_DIR/config.txt"
grep -Fqx '/original' "$PERSISTENT_DIR/kernel_umount.txt"
grep -Fqx 'rollback=restored' "$PERSISTENT_DIR/state/restore.report.txt"
grep -Fqx 'result=install-failed' "$PERSISTENT_DIR/state/restore.report.txt"

echo 'safe-restore tests passed'

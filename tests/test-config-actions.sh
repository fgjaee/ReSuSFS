#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MODULE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module" && pwd)
PERSISTENT_DIR="$TEST_ROOT/SusAF"
mkdir -p "$PERSISTENT_DIR" "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/ksu_susfs" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUSAF_FAKE_SUSFS_LOG"
EOF
chmod 755 "$TEST_ROOT/bin/ksu_susfs"
: > "$TEST_ROOT/susfs.log"

printf '# optional; no entries\n' > "$PERSISTENT_DIR/open_redirect.txt"
open_output=$(SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-open-redirect)
printf '%s\n' "$open_output" | grep -Fqx '[*] Open Redirect has no configured entries'
printf '%s\n' "$open_output" | grep -Fqx '[*] this optional feature is off; nothing applied'
[ ! -s "$TEST_ROOT/susfs.log" ]

printf '# generated automatically\n' > "$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
boot_output=$(SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-cmdline-bootconfig)
printf '%s\n' "$boot_output" | grep -Fqx '[*] no custom cmdline/bootconfig entries configured'
[ ! -s "$TEST_ROOT/susfs.log" ]

printf '/definitely/missing default default default default default default default default default default default default\n' > "$PERSISTENT_DIR/kstat_paths.txt"
kstat_output=$(SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-kstat-add)
printf '%s\n' "$kstat_output" | grep -Fqx '[!] skip missing path: /definitely/missing'
[ ! -s "$TEST_ROOT/susfs.log" ]

printf '%s default default default default default default default default default default default default\n' "$TEST_ROOT" > "$TEST_ROOT/kstat.generated.txt"
SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-kstat-add-direct "$TEST_ROOT/kstat.generated.txt" >/dev/null
grep -Fqx "add_sus_kstat_statically $TEST_ROOT default default default default default default default default default default default default" "$TEST_ROOT/susfs.log"

: > "$TEST_ROOT/susfs.log"
printf '%s\n' "$TEST_ROOT" > "$PERSISTENT_DIR/kstat_paths.txt"
SUSAF_MODULE_DIR="$MODULE_DIR" \
	SUSAF_PERSISTENT_DIR="$PERSISTENT_DIR" \
	SUSAF_SUSFS_BIN="$TEST_ROOT/bin/ksu_susfs" \
	SUSAF_FAKE_SUSFS_LOG="$TEST_ROOT/susfs.log" \
	NO_BANNER=1 sh "$MODULE_DIR/SusAF.sh" --apply-kstat-add >/dev/null
grep -Fqx "add_sus_kstat $TEST_ROOT" "$TEST_ROOT/susfs.log"

echo "config-action tests passed"

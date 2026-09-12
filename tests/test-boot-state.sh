#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

. "$(dirname "$0")/../module/lib/boot-state.sh"

cat > "$TEST_ROOT/bootconfig.in" <<'EOF'
androidboot.verifiedbootstate = "orange"
androidboot.verifiedbootstate = "red"
androidboot.vbmeta.device_state = "unlocked"
androidboot.warranty_bit = "1"
androidboot.flash.locked = "0"
androidboot.veritymode = "logging"
androidboot.verifiedbooterror = "dm-verity"
vendor.androidboot.verifyerrorpart = "system"
verifiedbooterror = "failure"
foo = "bar"
EOF

cat > "$TEST_ROOT/bootconfig.expected" <<'EOF'
androidboot.verifiedbootstate = "green"
androidboot.vbmeta.device_state = "locked"
androidboot.warranty_bit = "0"
androidboot.flash.locked = "1"
androidboot.veritymode = "enforcing"
foo = "bar"
EOF

bootconfig_before=$(sha256sum "$TEST_ROOT/bootconfig.in")
sanitize_bootconfig_file "$TEST_ROOT/bootconfig.in" "$TEST_ROOT/bootconfig.out"
cmp "$TEST_ROOT/bootconfig.expected" "$TEST_ROOT/bootconfig.out"
[ "$bootconfig_before" = "$(sha256sum "$TEST_ROOT/bootconfig.in")" ]

cat > "$TEST_ROOT/cmdline.in" <<'EOF'
console=ttyS0 androidboot.verifiedbootstate=orange androidboot.verifiedbootstate=red androidboot.vbmeta.device_state=unlocked androidboot.warranty_bit=1 androidboot.flash.locked=0 androidboot.veritymode=logging androidboot.verifiedbooterror=dm-verity vendor.androidboot.verifyerrorpart=system foo=bar
EOF
cat > "$TEST_ROOT/cmdline.expected" <<'EOF'
console=ttyS0 androidboot.verifiedbootstate=green androidboot.vbmeta.device_state=locked androidboot.warranty_bit=0 androidboot.flash.locked=1 androidboot.veritymode=enforcing foo=bar
EOF
sanitize_cmdline_file "$TEST_ROOT/cmdline.in" "$TEST_ROOT/cmdline.out"
cmp "$TEST_ROOT/cmdline.expected" "$TEST_ROOT/cmdline.out"

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/persistent"
cat > "$TEST_ROOT/bin/SusAF" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" > "$SUSAF_CAPTURE_ARGS"
cp "$2" "$SUSAF_CAPTURE_FILE"
EOF
chmod 755 "$TEST_ROOT/bin/SusAF"
printf 'custom.user.value=keep\n' > "$TEST_ROOT/persistent/cmdline_or_bootconfig.txt"
custom_before=$(sha256sum "$TEST_ROOT/persistent/cmdline_or_bootconfig.txt")

SUSAF_CAPTURE_ARGS="$TEST_ROOT/boot-args" \
SUSAF_CAPTURE_FILE="$TEST_ROOT/boot-captured" \
SUSAF_MODULE_DIR="$(dirname "$0")/../module" \
SUSAF_PERSISTENT_DIR="$TEST_ROOT/persistent" \
SUSAF_BOOTCONFIG_SOURCE="$TEST_ROOT/bootconfig.in" \
PATH="$TEST_ROOT/bin:$PATH" \
sh "$(dirname "$0")/../module/configs/scripts/SusAF_apply-cmdline-bootconfig.sh"

grep -Fqx -- '--apply-cmdline-bootconfig-direct' "$TEST_ROOT/boot-args"
cmp "$TEST_ROOT/bootconfig.expected" "$TEST_ROOT/boot-captured"
cmp "$TEST_ROOT/bootconfig.expected" "$TEST_ROOT/persistent/state/cmdline_or_bootconfig.generated.txt"
[ "$custom_before" = "$(sha256sum "$TEST_ROOT/persistent/cmdline_or_bootconfig.txt")" ]

cat > "$TEST_ROOT/bin/getprop" <<'EOF'
#!/bin/sh
[ "$1" = "ro.build.date" ] && printf '%s\n' 'Fri Jan  2 03:04:05 UTC 2026'
EOF
cat > "$TEST_ROOT/bin/ksud" <<'EOF'
#!/bin/sh
[ "$1 $2" = "boot-info current-kmi" ] && printf '%s\n' 'android14-6.1-test'
EOF
cat > "$TEST_ROOT/bin/SusAF" <<'EOF'
#!/bin/sh
cp "$2" "$SUSAF_UNAME_CAPTURE"
EOF
chmod 755 "$TEST_ROOT/bin/getprop" "$TEST_ROOT/bin/ksud" "$TEST_ROOT/bin/SusAF"
printf '%s\n' 'Linux version 6.1.99-android14-test builder@host' > "$TEST_ROOT/proc-version"
printf '%s\n' '12345678-90ab-cdef-1234-567890abcdef' > "$TEST_ROOT/boot-id"

SUSAF_PERSISTENT_DIR="$TEST_ROOT/persistent" \
SUSAF_PROC_VERSION="$TEST_ROOT/proc-version" \
SUSAF_BOOT_ID="$TEST_ROOT/boot-id" \
SUSAF_CLI_COMMAND="$TEST_ROOT/bin/SusAF" \
SUSAF_UNAME_CAPTURE="$TEST_ROOT/uname-captured" \
PATH="$TEST_ROOT/bin:$PATH" \
sh "$(dirname "$0")/../module/configs/scripts/SusAF_apply-uname.sh"

grep -Fqx 'release=6.1.99-android14-11-g1234567890ab' "$TEST_ROOT/uname-captured"
grep -Fqx 'version=#1 SMP PREEMPT Fri Jan 2 03:04:05 UTC 2026' "$TEST_ROOT/uname-captured"

cat > "$TEST_ROOT/resetprop-state" <<'EOF'
[ro.boot.verifiedbooterror]: [dm-verity]
[ro.boot.verifyerrorpart]: [system]
[vendor.boot.verifiedbooterror]: [vendor]
[persist.vendor.verifyerrorpart]: [product]
[ro.normal.property]: [keep]
EOF
cat > "$TEST_ROOT/bin/resetprop" <<'EOF'
#!/bin/sh
if [ "$#" -eq 0 ]; then
	cat "$SUSAF_RESETPROP_STATE"
	exit 0
fi
printf '%s\n' "$*" >> "$SUSAF_RESETPROP_LOG"
exit 0
EOF
chmod 755 "$TEST_ROOT/bin/resetprop"
SUSAF_RESETPROP_STATE="$TEST_ROOT/resetprop-state" \
SUSAF_RESETPROP_LOG="$TEST_ROOT/resetprop-log" \
PATH="$TEST_ROOT/bin:$PATH" \
sh "$(dirname "$0")/../module/configs/scripts/SusAF_apply-props.sh"

for prop in ro.boot.verifiedbooterror ro.boot.verifyerrorpart vendor.boot.verifiedbooterror persist.vendor.verifyerrorpart; do
	grep -Fqx -- "-d $prop" "$TEST_ROOT/resetprop-log"
	grep -Fqx -- "-d -p $prop" "$TEST_ROOT/resetprop-log"
done
! grep -Fq -- '-d ro.normal.property' "$TEST_ROOT/resetprop-log"

echo "boot-state tests passed"

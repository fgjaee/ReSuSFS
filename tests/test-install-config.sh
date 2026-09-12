#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export PERSISTENT_DIR="$TEST_ROOT/SusAF"
PACKAGE_DIR="$TEST_ROOT/package"
. "$(dirname "$0")/../module/install-config.sh"

mkdir -p "$PACKAGE_DIR/scripts" "$PERSISTENT_DIR/scripts"
printf 'BuiltInEarly.sh\n' > "$PACKAGE_DIR/scripts_postfs.txt"
printf 'BuiltInLate.sh\n' > "$PACKAGE_DIR/scripts_bootcompleted.txt"
printf 'new-default\n' > "$PACKAGE_DIR/config.txt"
printf '#!/system/bin/sh\nprintf "new built-in\\n"\n' > "$PACKAGE_DIR/scripts/BuiltInLate.sh"

printf 'Max_Saturation.sh\n' > "$PERSISTENT_DIR/scripts_bootcompleted.txt"
printf 'custom-value\n' > "$PERSISTENT_DIR/config.txt"
printf '#!/system/bin/sh\nprintf "old built-in\\n"\n' > "$PERSISTENT_DIR/scripts/BuiltInLate.sh"
printf '#!/system/bin/sh\nprintf "mine\\n"\n' > "$PERSISTENT_DIR/scripts/MyCustom.sh"

merge_schedule_defaults "$PACKAGE_DIR/scripts_postfs.txt" "$PERSISTENT_DIR/scripts_postfs.txt"
merge_schedule_defaults "$PACKAGE_DIR/scripts_bootcompleted.txt" "$PERSISTENT_DIR/scripts_bootcompleted.txt"
install_packaged_builtins "$PACKAGE_DIR/scripts" "$PERSISTENT_DIR/scripts"
install_missing_defaults "$PACKAGE_DIR" "$PERSISTENT_DIR"

grep -Fqx 'Max_Saturation.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt"
grep -Fqx 'BuiltInLate.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt"
[ "$(grep -Fxc 'BuiltInLate.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt")" -eq 1 ]
grep -Fqx 'BuiltInEarly.sh' "$PERSISTENT_DIR/scripts_postfs.txt"
grep -Fqx 'custom-value' "$PERSISTENT_DIR/config.txt"
grep -Fq 'new built-in' "$PERSISTENT_DIR/scripts/BuiltInLate.sh"
grep -Fq 'mine' "$PERSISTENT_DIR/scripts/MyCustom.sh"
find "$PERSISTENT_DIR/migration" -path '*/replaced-builtins/BuiltInLate.sh' \
	-exec grep -Fq 'old built-in' {} \;

! grep -Eq 'VOLUME (UP|DOWN)|getevent|detect_key_press' "$(dirname "$0")/../module/customize.sh"

echo "install config tests passed"

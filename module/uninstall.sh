#!/bin/sh

MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
[ -f "$MODULE_DIR/common.sh" ] && . "$MODULE_DIR/common.sh"
: "${DEST_BIN_DIR:=/data/adb/ksu/bin}"

for command_path in "$DEST_BIN_DIR/SusAF" "$DEST_BIN_DIR/ReSuSFS"; do
	[ -L "$command_path" ] || continue
	[ "$(readlink "$command_path" 2>/dev/null)" = "$MODULE_DIR/SusAF.sh" ] && rm -f "$command_path"
done

# EOF

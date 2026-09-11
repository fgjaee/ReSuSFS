#!/bin/sh
PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

# apply late-stage susfs config now that mounts have settled
sh "$MODULE_DIR/SusAF.sh" --stage-late

sh "$MODULE_DIR/SusAF.sh" --run-bootcompleted-scripts

# Migrated scripts may contain ReSuSFS's old numeric disable command.
sh "$MODULE_DIR/SusAF.sh" --apply-kernel-umount-feature || true

# EOF

#!/bin/sh
PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

# apply early-stage susfs config now that mounts have settled
sh "$MODULE_DIR/SusAF.sh" --stage-early

sh "$MODULE_DIR/SusAF.sh" --run-postfs-scripts

# EOF

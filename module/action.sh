#!/bin/sh

PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

. "$MODULE_DIR/utils.sh"

banner

update_susfs || exit 1

export NO_BANNER=1
sh "$MODULE_DIR/SusAF.sh" --status

# EOF

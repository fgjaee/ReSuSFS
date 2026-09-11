#!/bin/sh
PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

sh "$MODULE_DIR/post-fs-data.sh" > /dev/null 2>&1

sh "$MODULE_DIR/service.sh" > /dev/null 2>&1

echo "SusAF: hot-install.sh done" >> /dev/kmsg

# EOF

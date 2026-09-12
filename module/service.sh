#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
	sleep 1
done

# One event-based snapshot after Android finishes booting. The WebUI can
# explicitly refresh it later; no installed module file is rewritten.
sh "$MODULE_DIR/SusAF.sh" --status-report > /dev/null 2>&1

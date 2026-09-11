#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
	sleep 1
done

(
	while true; do
		sh "$MODULE_DIR/SusAF.sh" --status-report > /dev/null 2>&1
		sleep 5
	done
) &

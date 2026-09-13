#!/bin/sh

MODULE_ID="susaf"
MODULE_NAME="Sus'AF"
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/$MODULE_ID}"
PERSISTENT_DIR="${SUSAF_PERSISTENT_DIR:-/data/adb/SusAF}"
if [ -n "${SUSAF_BIN_DIR:-}" ]; then
	DEST_BIN_DIR="$SUSAF_BIN_DIR"
elif [ -d /data/adb/ksu/bin ]; then
	DEST_BIN_DIR=/data/adb/ksu/bin
elif [ -d /data/adb/ap/bin ]; then
	DEST_BIN_DIR=/data/adb/ap/bin
else
	DEST_BIN_DIR=/data/adb/ksu/bin
fi
SUSFS_BUNDLED_BIN="$MODULE_DIR/bin/ksu_susfs"

LEGACY_RESUSFS_DIR="${SUSAF_LEGACY_RESUSFS_DIR:-/data/adb/ReSuSFS}"
LEGACY_SUSFS4KSU_DIR="${SUSAF_LEGACY_SUSFS4KSU_DIR:-/data/adb/susfs4ksu}"
LEGACY_MODULE_DIR="${SUSAF_LEGACY_MODULE_DIR:-/data/adb/modules/ReSuSFS}"

SUSAF_CLI="$DEST_BIN_DIR/SusAF"
RESUSFS_COMPAT_CLI="$DEST_BIN_DIR/ReSuSFS"

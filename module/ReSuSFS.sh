#!/bin/sh

# Compatibility entry point for migrated UserHub scripts.
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
exec sh "$MODULE_DIR/SusAF.sh" "$@"

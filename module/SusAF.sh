#!/bin/sh

MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
exec sh "$MODULE_DIR/ReSuSFS.sh" "$@"


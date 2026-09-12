#!/bin/sh
PATH=/data/adb/ksu/bin:$PATH
MODULE_DIR="${SUSAF_MODULE_DIR:-/data/adb/modules/susaf}"
. "$MODULE_DIR/common.sh"
. "$MODULE_DIR/lib/stage-state.sh"

stage_result=0
stage_state_begin post-fs-data || stage_result=1

# apply early-stage susfs config now that mounts have settled
sh "$MODULE_DIR/SusAF.sh" --stage-early || stage_result=1

sh "$MODULE_DIR/SusAF.sh" --run-postfs-scripts || stage_result=1

# Re-assert Sus'AF's explicit policy after migrated/custom scripts have run.
sh "$MODULE_DIR/SusAF.sh" --apply-kernel-umount-feature || stage_result=1

stage_state_finish post-fs-data "$stage_result" || true

# EOF

#!/bin/sh
set -eu

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export SUSAF_PERSISTENT_DIR="$TEST_ROOT/SusAF"
export SUSAF_LEGACY_RESUSFS_DIR="$TEST_ROOT/ReSuSFS"
export SUSAF_LEGACY_SUSFS4KSU_DIR="$TEST_ROOT/susfs4ksu"
export SUSAF_MODULE_DIR="$TEST_ROOT/modules/susaf"
export SUSAF_LEGACY_MODULE_DIR="$TEST_ROOT/modules/ReSuSFS"
export SUSAF_BIN_DIR="$TEST_ROOT/bin"
export SUSAF_MIGRATION_TIMESTAMP="migration-test"
TEMPLATE_DIR=$(CDPATH= cd -- "$(dirname "$0")/../module/configs/scripts" && pwd)

. "$(dirname "$0")/../module/common.sh"
. "$(dirname "$0")/../module/migrate.sh"

mkdir -p "$PERSISTENT_DIR" "$LEGACY_RESUSFS_DIR/scripts" "$LEGACY_SUSFS4KSU_DIR" "$LEGACY_MODULE_DIR"
printf 'HIDE_SUS_MNTS_NON_SU=0\n' > "$PERSISTENT_DIR/config.txt"
printf 'Existing.sh\n' > "$PERSISTENT_DIR/scripts_postfs.txt"

printf 'HIDE_SUS_MNTS_NON_SU=1\n' > "$LEGACY_RESUSFS_DIR/config.txt"
printf '#!/system/bin/sh\nprintf "max saturation\\n"\n' > "$LEGACY_RESUSFS_DIR/scripts/Max_Saturation.sh"
chmod 750 "$LEGACY_RESUSFS_DIR/scripts/Max_Saturation.sh"
printf '#!/system/bin/sh\nsettings put global adb_enabled 0\n' > "$LEGACY_RESUSFS_DIR/scripts/ReSuSFS_apply-settings.sh"
printf '#!/system/bin/sh\nfor pty in /dev/pts/*; do echo "$pty"; done\n' > "$LEGACY_RESUSFS_DIR/scripts/ReSuSFS_apply-sus-paths-loop.sh"
printf '#!/system/bin/sh\nfind /data/adb/modules -name "*.so"\n' > "$LEGACY_RESUSFS_DIR/scripts/ReSuSFS_apply-sus-maps.sh"
printf 'Max_Saturation.sh\n' > "$LEGACY_RESUSFS_DIR/scripts_postfs.txt"
printf 'Max_Saturation.sh\n' > "$LEGACY_RESUSFS_DIR/scripts_bootcompleted.txt"
printf '0 6 * * * Max_Saturation.sh\n' > "$LEGACY_RESUSFS_DIR/scripts_cron.txt"
printf '/system/example\n' > "$LEGACY_RESUSFS_DIR/sus_paths.txt"

printf '# old format supports a retry field\n/system/addon.d 15\n/vendor/bin/install-recovery.sh\n' > "$LEGACY_SUSFS4KSU_DIR/sus_path.txt"
printf '/system_ext\n/debug_ramdisk # comment\n' > "$LEGACY_SUSFS4KSU_DIR/try_umount.txt"
printf '/system\n' > "$LEGACY_SUSFS4KSU_DIR/legit_mounts.txt"
printf 'auto_try_umount=1\nunknown_key=unsafe\n' > "$LEGACY_SUSFS4KSU_DIR/config.sh"

legacy_before=$(find "$LEGACY_RESUSFS_DIR" "$LEGACY_SUSFS4KSU_DIR" -type f -exec sha256sum {} \; | sort | sha256sum)

migrate_legacy_configs
refresh_unsafe_legacy_builtins "$TEMPLATE_DIR"

cmp "$LEGACY_RESUSFS_DIR/scripts/Max_Saturation.sh" "$PERSISTENT_DIR/scripts/Max_Saturation.sh"
[ "$(stat -c %a "$PERSISTENT_DIR/scripts/Max_Saturation.sh")" = "750" ]
grep -Fqx 'Existing.sh' "$PERSISTENT_DIR/scripts_postfs.txt"
grep -Fqx 'Max_Saturation.sh' "$PERSISTENT_DIR/scripts_postfs.txt"
grep -Fqx 'Max_Saturation.sh' "$PERSISTENT_DIR/scripts_bootcompleted.txt"
grep -Fqx '0 6 * * * Max_Saturation.sh' "$PERSISTENT_DIR/scripts_cron.txt"
! grep -Fq 'settings put global adb_enabled 0' "$PERSISTENT_DIR/scripts/ReSuSFS_apply-settings.sh"
! grep -Fq 'for pty in /dev/pts/*' "$PERSISTENT_DIR/scripts/ReSuSFS_apply-sus-paths-loop.sh"
! grep -Fq 'find /data/adb/modules -name "*.so"' "$PERSISTENT_DIR/scripts/ReSuSFS_apply-sus-maps.sh"
grep -Fq 'settings put global adb_enabled 0' "$MIGRATION_RUN_DIR/review/replaced-builtins/ReSuSFS_apply-settings.sh"
grep -Fq 'for pty in /dev/pts/*' "$MIGRATION_RUN_DIR/review/replaced-builtins/ReSuSFS_apply-sus-paths-loop.sh"
grep -Fq 'find /data/adb/modules -name "*.so"' "$MIGRATION_RUN_DIR/review/replaced-builtins/ReSuSFS_apply-sus-maps.sh"
grep -Fq 'settings put global adb_enabled 0' "$LEGACY_RESUSFS_DIR/scripts/ReSuSFS_apply-settings.sh"
grep -Fqx 'HIDE_SUS_MNTS_NON_SU=0' "$PERSISTENT_DIR/config.txt"
grep -Fqx 'HIDE_SUS_MNTS_NON_SU=1' "$PERSISTENT_DIR/migration/migration-test/review/ReSuSFS/config.txt"
grep -Fqx '/system/example' "$PERSISTENT_DIR/sus_paths.txt"
grep -Fqx '/system/addon.d' "$PERSISTENT_DIR/sus_paths.txt"
! grep -q ' 15' "$PERSISTENT_DIR/sus_paths.txt"
grep -Fqx '/system_ext' "$PERSISTENT_DIR/kernel_umount.txt"
grep -Fqx '/debug_ramdisk' "$PERSISTENT_DIR/kernel_umount.txt"
grep -Fqx '/system' "$PERSISTENT_DIR/legacy/legit_mounts.txt"
grep -Fqx 'auto_try_umount=1' "$PERSISTENT_DIR/migration/migration-test/review/susfs4ksu/config-known.txt"
! grep -q 'unknown_key' "$PERSISTENT_DIR/migration/migration-test/review/susfs4ksu/config-known.txt"

legacy_after=$(find "$LEGACY_RESUSFS_DIR" "$LEGACY_SUSFS4KSU_DIR" -type f -exec sha256sum {} \; | sort | sha256sum)
[ "$legacy_before" = "$legacy_after" ]

postfs_before=$(sha256sum "$PERSISTENT_DIR/scripts_postfs.txt")
migrate_legacy_configs
[ "$postfs_before" = "$(sha256sum "$PERSISTENT_DIR/scripts_postfs.txt")" ]

disable_legacy_resusfs_module
[ -f "$LEGACY_MODULE_DIR/disable" ]

echo "migration tests passed"

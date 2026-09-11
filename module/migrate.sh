#!/bin/sh

# Safe, idempotent migration into /data/adb/SusAF. Legacy sources are read
# only. Unsupported data is snapshotted for review instead of being executed.

MIGRATION_SCHEMA=1
MIGRATION_MAX_CONFIG_BYTES=4194304
MIGRATION_MAX_SCRIPT_BYTES=2097152
MIGRATION_MAX_BACKGROUND_BYTES=33554432

_migration_print() {
	local message="$1"
	if command -v ui_print >/dev/null 2>&1; then
		ui_print "$message"
	else
		echo "$message"
	fi
}

_migration_note() {
	local message="$1"
	_migration_print "$message"
	[ -n "${MIGRATION_LOG:-}" ] && printf '%s\n' "$message" >> "$MIGRATION_LOG"
}

_migration_fail() {
	_migration_note "[!] $1"
	[ -n "${MIGRATION_ERROR_FILE:-}" ] && : > "$MIGRATION_ERROR_FILE"
	return 1
}

_ensure_migration_layout() {
	local stamp
	umask 077
	mkdir -p "$PERSISTENT_DIR" "$PERSISTENT_DIR/state/migrations" "$PERSISTENT_DIR/migration" || return 1
	chmod 700 "$PERSISTENT_DIR" "$PERSISTENT_DIR/state" "$PERSISTENT_DIR/state/migrations" "$PERSISTENT_DIR/migration" 2>/dev/null

	[ -n "${MIGRATION_RUN_DIR:-}" ] && return 0
	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	MIGRATION_RUN_DIR="$PERSISTENT_DIR/migration/$stamp"
	[ ! -e "$MIGRATION_RUN_DIR" ] || MIGRATION_RUN_DIR="$PERSISTENT_DIR/migration/${stamp}_$$"
	mkdir -p "$MIGRATION_RUN_DIR/snapshot" "$MIGRATION_RUN_DIR/review" "$MIGRATION_RUN_DIR/translated" || return 1
	MIGRATION_LOG="$MIGRATION_RUN_DIR/migration.log"
	: > "$MIGRATION_LOG"
}

_regular_file_size() {
	wc -c < "$1" 2>/dev/null | tr -d '[:space:]'
}

_copy_regular_file() {
	local src="$1"
	local dst="$2"
	local max_bytes="${3:-$MIGRATION_MAX_CONFIG_BYTES}"
	local size

	[ -f "$src" ] && [ ! -L "$src" ] || {
		_migration_fail "Rejected non-regular migration source: $src"
		return 1
	}

	size=$(_regular_file_size "$src")
	case "$size" in
		''|*[!0-9]*) _migration_fail "Could not determine migration source size: $src"; return 1 ;;
	esac
	[ "$size" -le "$max_bytes" ] || {
		_migration_fail "Rejected oversized migration source ($size bytes): $src"
		return 1
	}

	mkdir -p "$(dirname "$dst")" || {
		_migration_fail "Could not create migration destination: $dst"
		return 1
	}
	cp -p "$src" "$dst" || {
		_migration_fail "Could not copy migration source: $src"
		return 1
	}
	chown 0:0 "$dst" 2>/dev/null
	return 0
}

_snapshot_file() {
	local label="$1"
	local rel="$2"
	local max_bytes="${3:-$MIGRATION_MAX_CONFIG_BYTES}"
	_copy_regular_file "$MIGRATION_SOURCE/$rel" "$MIGRATION_RUN_DIR/snapshot/$label/$rel" "$max_bytes"
}

_review_file() {
	local label="$1"
	local rel="$2"
	local max_bytes="${3:-$MIGRATION_MAX_CONFIG_BYTES}"
	_copy_regular_file "$MIGRATION_SOURCE/$rel" "$MIGRATION_RUN_DIR/review/$label/$rel" "$max_bytes"
}

_import_file_if_missing() {
	local label="$1"
	local rel="$2"
	local mode="$3"
	local max_bytes="${4:-$MIGRATION_MAX_CONFIG_BYTES}"
	local src="$MIGRATION_SOURCE/$rel"
	local dst="$PERSISTENT_DIR/$rel"

	_snapshot_file "$label" "$rel" "$max_bytes" || return 1
	if [ ! -e "$dst" ]; then
		_copy_regular_file "$src" "$dst" "$max_bytes" || return 1
		[ -n "$mode" ] && chmod "$mode" "$dst" 2>/dev/null
		_migration_note "[+] Imported $label/$rel"
	elif [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
		_review_file "$label" "$rel" "$max_bytes" || return 1
		_migration_note "[*] Kept existing $rel; legacy copy saved for review"
	fi
}

_merge_unique_file() {
	local label="$1"
	local rel="$2"
	local mode="$3"
	local src="$MIGRATION_SOURCE/$rel"
	local dst="$PERSISTENT_DIR/$rel"
	local tmp line

	_snapshot_file "$label" "$rel" "$MIGRATION_MAX_CONFIG_BYTES" || return 1
	if [ ! -e "$dst" ]; then
		_copy_regular_file "$src" "$dst" "$MIGRATION_MAX_CONFIG_BYTES" || return 1
		chmod "$mode" "$dst" 2>/dev/null
		_migration_note "[+] Imported $label/$rel"
		return 0
	fi
	[ -f "$dst" ] && [ ! -L "$dst" ] || {
		_migration_fail "Refusing to merge into non-regular destination: $dst"
		return 1
	}

	tmp="${dst}.migration.$$"
	cp "$dst" "$tmp" || {
		_migration_fail "Could not stage list merge: $rel"
		return 1
	}
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] || continue
		grep -Fqx "$line" "$tmp" 2>/dev/null || printf '%s\n' "$line" >> "$tmp" || _migration_fail "Could not append migrated entry: $rel"
	done < "$src"
	mv "$tmp" "$dst" || {
		rm -f "$tmp"
		_migration_fail "Could not atomically merge: $rel"
		return 1
	}
	chmod "$mode" "$dst" 2>/dev/null
	_migration_note "[+] Merged missing entries from $label/$rel"
}

_import_resusfs_scripts() {
	local scripts_dir="$MIGRATION_SOURCE/scripts"
	local src rel dst
	[ -d "$scripts_dir" ] && [ ! -L "$scripts_dir" ] || return 0

	find "$scripts_dir" -type f -name '*.sh' 2>/dev/null | while IFS= read -r src; do
		rel="${src#"$MIGRATION_SOURCE"/}"
		case "$rel" in
			scripts/*.sh) ;;
			*) _migration_fail "Rejected unexpected UserHub script path: $src"; continue ;;
		esac
		_snapshot_file "ReSuSFS" "$rel" "$MIGRATION_MAX_SCRIPT_BYTES" || continue
		dst="$PERSISTENT_DIR/$rel"
		if [ ! -e "$dst" ]; then
			_copy_regular_file "$src" "$dst" "$MIGRATION_MAX_SCRIPT_BYTES" || continue
			_migration_note "[+] Imported UserHub script: ${rel#scripts/}"
		elif [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
			_review_file "ReSuSFS" "$rel" "$MIGRATION_MAX_SCRIPT_BYTES" || continue
			_migration_note "[*] Kept existing UserHub script; legacy copy saved: ${rel#scripts/}"
		fi
	done
}

_finish_source_migration() {
	local label="$1"
	local marker="$2"
	if [ -e "$MIGRATION_ERROR_FILE" ]; then
		rm -f "$MIGRATION_ERROR_FILE"
		_migration_note "[!] $label migration incomplete; it will retry on the next install"
		return 1
	fi
	printf 'schema=%s\nsource=%s\nsnapshot=%s\n' "$MIGRATION_SCHEMA" "$MIGRATION_SOURCE" "$MIGRATION_RUN_DIR" > "$marker" || {
		_migration_fail "Could not write migration marker: $marker"
		return 1
	}
	chmod 600 "$marker" 2>/dev/null
	_migration_note "[+] $label migration completed"
}

migrate_resusfs_config() {
	local marker="$PERSISTENT_DIR/state/migrations/v${MIGRATION_SCHEMA}-resusfs.done"
	local rel limit
	[ -d "$LEGACY_RESUSFS_DIR" ] && [ ! -L "$LEGACY_RESUSFS_DIR" ] || return 0
	[ ! -f "$marker" ] || return 0
	_ensure_migration_layout || return 1
	MIGRATION_SOURCE="$LEGACY_RESUSFS_DIR"
	MIGRATION_ERROR_FILE="$PERSISTENT_DIR/state/migrations/.resusfs-error.$$"
	rm -f "$MIGRATION_ERROR_FILE"
	_migration_note "[*] Migrating legacy ReSuSFS configuration (source remains untouched)"

	for rel in sus_paths.txt sus_paths_loop.txt sus_maps.txt kstat_paths.txt open_redirect.txt scripts_postfs.txt scripts_bootcompleted.txt scripts_cron.txt; do
		[ -f "$MIGRATION_SOURCE/$rel" ] && [ ! -L "$MIGRATION_SOURCE/$rel" ] || continue
		_merge_unique_file "ReSuSFS" "$rel" 600
	done
	for rel in uname.txt cmdline_or_bootconfig.txt config.txt; do
		[ -f "$MIGRATION_SOURCE/$rel" ] && [ ! -L "$MIGRATION_SOURCE/$rel" ] || continue
		_import_file_if_missing "ReSuSFS" "$rel" 600
	done

	_import_resusfs_scripts

	for rel in .webui_config/custom.css .webui_config/custom_background.webp .webui_config/custom_background.jpg .webui_config/custom_background.png; do
		[ -f "$MIGRATION_SOURCE/$rel" ] && [ ! -L "$MIGRATION_SOURCE/$rel" ] || continue
		case "$rel" in
			*.css) limit="$MIGRATION_MAX_CONFIG_BYTES" ;;
			*) limit="$MIGRATION_MAX_BACKGROUND_BYTES" ;;
		esac
		_import_file_if_missing "ReSuSFS" "$rel" 600 "$limit"
	done

	_finish_source_migration "ReSuSFS" "$marker"
}

_merge_generated_paths() {
	local src="$1"
	local dst="$2"
	local label="$3"
	local tmp line
	[ -s "$src" ] || return 0
	if [ ! -e "$dst" ]; then
		mkdir -p "$(dirname "$dst")" || return 1
		cp "$src" "$dst" || return 1
		chmod 600 "$dst" 2>/dev/null
	else
		[ -f "$dst" ] && [ ! -L "$dst" ] || return 1
		tmp="${dst}.migration.$$"
		cp "$dst" "$tmp" || return 1
		while IFS= read -r line || [ -n "$line" ]; do
			grep -Fqx "$line" "$tmp" 2>/dev/null || printf '%s\n' "$line" >> "$tmp" || return 1
		done < "$src"
		mv "$tmp" "$dst" || return 1
		chmod 600 "$dst" 2>/dev/null
	fi
	_migration_note "[+] Imported validated paths from susfs4ksu/$label"
}

_translate_path_file() {
	local source_rel="$1"
	local target_rel="$2"
	local src="$MIGRATION_SOURCE/$source_rel"
	local translated
	[ -f "$src" ] && [ ! -L "$src" ] || return 0
	translated="$MIGRATION_RUN_DIR/translated/${source_rel%.txt}.txt"
	awk '
	{
		line=$0
		sub(/[[:space:]]*#.*/, "", line)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
		if (line == "") next
		split(line, fields, /[[:space:]]+/)
		path=fields[1]
		if (path ~ /^\// && !seen[path]++) print path
	}
	' "$src" > "$translated" || {
		_migration_fail "Could not translate susfs4ksu/$source_rel"
		return 1
	}
	_merge_generated_paths "$translated" "$PERSISTENT_DIR/$target_rel" "$source_rel" || {
		_migration_fail "Could not import translated susfs4ksu/$source_rel"
		return 1
	}
}

migrate_susfs4ksu_config() {
	local marker="$PERSISTENT_DIR/state/migrations/v${MIGRATION_SCHEMA}-susfs4ksu.done"
	local rel known
	[ -d "$LEGACY_SUSFS4KSU_DIR" ] && [ ! -L "$LEGACY_SUSFS4KSU_DIR" ] || return 0
	[ ! -f "$marker" ] || return 0
	_ensure_migration_layout || return 1
	MIGRATION_SOURCE="$LEGACY_SUSFS4KSU_DIR"
	MIGRATION_ERROR_FILE="$PERSISTENT_DIR/state/migrations/.susfs4ksu-error.$$"
	rm -f "$MIGRATION_ERROR_FILE"
	_migration_note "[*] Migrating understood susfs4ksu configuration (source remains untouched)"

	for rel in sus_path.txt sus_path_loop.txt sus_maps.txt try_umount.txt legit_mounts.txt sus_mount.txt sus_open_redirect.txt sus_kstat_statically.json config.sh; do
		[ -f "$MIGRATION_SOURCE/$rel" ] && [ ! -L "$MIGRATION_SOURCE/$rel" ] || continue
		_snapshot_file "susfs4ksu" "$rel" "$MIGRATION_MAX_CONFIG_BYTES"
	done

	_translate_path_file sus_path.txt sus_paths.txt
	_translate_path_file sus_path_loop.txt sus_paths_loop.txt
	_translate_path_file sus_maps.txt sus_maps.txt
	_translate_path_file try_umount.txt kernel_umount.txt
	_translate_path_file legit_mounts.txt legacy/legit_mounts.txt

	for rel in sus_mount.txt sus_open_redirect.txt sus_kstat_statically.json; do
		[ -f "$MIGRATION_SOURCE/$rel" ] && [ ! -L "$MIGRATION_SOURCE/$rel" ] || continue
		_review_file "susfs4ksu" "$rel" "$MIGRATION_MAX_CONFIG_BYTES"
	done

	if [ -f "$MIGRATION_SOURCE/config.sh" ] && [ ! -L "$MIGRATION_SOURCE/config.sh" ]; then
		known="$MIGRATION_RUN_DIR/review/susfs4ksu/config-known.txt"
		mkdir -p "$(dirname "$known")" || _migration_fail "Could not create susfs4ksu review directory"
		awk -F= '
		$1 ~ /^(susfs_log|sus_su|sus_su_active|hide_cusrom|hide_vendor_sepolicy|hide_compat_matrix|hide_gapps|hide_revanced|spoof_cmdline|hide_loops|force_hide_lsposed|spoof_uname|hide_sus_mnts_for_all_or_non_su_procs|umount_for_zygote_iso_service|auto_try_umount|skip_legit_mounts|avc_log_spoofing|emulate_vold_app_data|disable_webui_bin_update)$/ && $2 ~ /^[0-9]+$/ { print }
		' "$MIGRATION_SOURCE/config.sh" > "$known" || _migration_fail "Could not parse susfs4ksu/config.sh"
		chmod 600 "$known" 2>/dev/null
	fi

	_finish_source_migration "susfs4ksu" "$marker"
}

migrate_legacy_configs() {
	local result
	result=0
	migrate_resusfs_config || result=1
	migrate_susfs4ksu_config || result=1
	return "$result"
}

disable_legacy_resusfs_module() {
	[ -d "$LEGACY_MODULE_DIR" ] && [ ! -L "$LEGACY_MODULE_DIR" ] || return 0
	[ "$LEGACY_MODULE_DIR" != "$MODULE_DIR" ] || return 0
	touch "$LEGACY_MODULE_DIR/disable" || return 1
	_migration_note "[+] Disabled the legacy ReSuSFS module to prevent duplicate boot services"
}

#!/bin/sh

# Validated Sus'AF configuration export and restore. Archives never extract
# directly into the live persistent directory.

SUSAF_BACKUP_SCHEMA=1
SUSAF_BACKUP_MAX_ARCHIVE_BYTES="${SUSAF_BACKUP_MAX_ARCHIVE_BYTES:-67108864}"
SUSAF_BACKUP_MAX_TOTAL_BYTES="${SUSAF_BACKUP_MAX_TOTAL_BYTES:-67108864}"
SUSAF_BACKUP_MAX_ENTRIES="${SUSAF_BACKUP_MAX_ENTRIES:-512}"
SUSAF_BACKUP_MAX_CONFIG_BYTES="${SUSAF_BACKUP_MAX_CONFIG_BYTES:-4194304}"
SUSAF_BACKUP_MAX_SCRIPT_BYTES="${SUSAF_BACKUP_MAX_SCRIPT_BYTES:-2097152}"
SUSAF_BACKUP_MAX_BACKGROUND_BYTES="${SUSAF_BACKUP_MAX_BACKGROUND_BYTES:-33554432}"

susaf_backup_busybox() {
	local binary="${SUSAF_BUSYBOX_BIN:-}"
	[ -n "$binary" ] || binary=$(command -v busybox 2>/dev/null) || binary=""
	[ -n "$binary" ] && [ -x "$binary" ] || return 1
	printf '%s\n' "$binary"
}

susaf_backup_file_size() {
	wc -c < "$1" 2>/dev/null | tr -d '[:space:]'
}

susaf_backup_directory_safe() {
	[ ! -L "$1" ] && { [ ! -e "$1" ] || [ -d "$1" ]; }
}

susaf_backup_limit_for() {
	case "$1" in
		scripts/*.sh) printf '%s\n' "$SUSAF_BACKUP_MAX_SCRIPT_BYTES" ;;
		.webui_config/custom_background.webp|.webui_config/custom_background.jpg|.webui_config/custom_background.png)
			printf '%s\n' "$SUSAF_BACKUP_MAX_BACKGROUND_BYTES"
			;;
		*) printf '%s\n' "$SUSAF_BACKUP_MAX_CONFIG_BYTES" ;;
	esac
}

susaf_backup_member_allowed() {
	local rel="$1" base
	while [ "${rel#./}" != "$rel" ]; do rel=${rel#./}; done
	rel=${rel%/}
	[ -n "$rel" ] || return 0

	case "$rel" in
		/*|..|../*|*/..|*/../*|*/./*|*//*|*\\*) return 1 ;;
	esac
	case "$rel" in
		.susaf-backup-manifest|scripts|.webui_config|\
		config.txt|kernel_umount.txt|kstat_paths.txt|open_redirect.txt|\
		scripts_bootcompleted.txt|scripts_postfs.txt|scripts_cron.txt|\
		sus_maps.txt|sus_paths.txt|sus_paths_loop.txt|uname.txt|\
		cmdline_or_bootconfig.txt|\
		.webui_config/custom.css|\
		.webui_config/custom_background.webp|\
		.webui_config/custom_background.jpg|\
		.webui_config/custom_background.png)
			return 0
			;;
		scripts/*)
			base=${rel#scripts/}
			[ "${base#*/}" = "$base" ] || return 1
			case "$base" in
				*.sh) ;;
				*) return 1 ;;
			esac
			case "$base" in
				''|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-]*) return 1 ;;
			esac
			return 0
			;;
	esac
	return 1
}

susaf_backup_normalize_member() {
	local rel="$1"
	while [ "${rel#./}" != "$rel" ]; do rel=${rel#./}; done
	rel=${rel%/}
	printf '%s\n' "$rel"
}

susaf_restore_prepare_report() {
	local report_dir
	SUSAF_RESTORE_REPORT="${SUSAF_RESTORE_REPORT:-$PERSISTENT_DIR/state/restore.report.txt}"
	SUSAF_RESTORE_REPORT_TEMP="${SUSAF_RESTORE_REPORT}.tmp.$$"
	report_dir=$(dirname "$SUSAF_RESTORE_REPORT")
	umask 077
	mkdir -p "$report_dir" || return 1
	chmod 700 "$PERSISTENT_DIR" "$PERSISTENT_DIR/state" "$report_dir" 2>/dev/null
	: > "$SUSAF_RESTORE_REPORT_TEMP" || return 1
	chmod 600 "$SUSAF_RESTORE_REPORT_TEMP" 2>/dev/null
}

susaf_restore_note() {
	printf '%s\n' "$*" >> "$SUSAF_RESTORE_REPORT_TEMP"
	printf '[restore] %s\n' "$*"
}

susaf_restore_finish() {
	local result="$1"
	susaf_restore_note "result=$result"
	mv -f "$SUSAF_RESTORE_REPORT_TEMP" "$SUSAF_RESTORE_REPORT"
}

susaf_restore_reject() {
	local result="$1"
	shift
	[ "$#" -eq 0 ] || susaf_restore_note "detail=$*"
	susaf_restore_finish "$result"
	return 1
}

susaf_restore_manifest_valid() {
	local manifest="$1" expected="$2"
	[ -f "$manifest" ] && [ ! -L "$manifest" ] || return 1
	{
		printf 'schema=%s\n' "$SUSAF_BACKUP_SCHEMA"
		printf 'module_id=susaf\n'
		printf 'format=tar.gz\n'
	} > "$expected" || return 1
	cmp -s "$expected" "$manifest"
}

susaf_restore_add_file() {
	local stage="$1" rel="$2" list="$3"
	local source="$stage/$rel" size limit
	[ -e "$source" ] || return 0
	[ -f "$source" ] && [ ! -L "$source" ] || return 1
	size=$(susaf_backup_file_size "$source")
	case "$size" in ''|*[!0-9]*) return 1 ;; esac
	limit=$(susaf_backup_limit_for "$rel")
	[ "$size" -le "$limit" ] || return 1
	printf '%s\n' "$rel" >> "$list"
}

susaf_restore_rollback() {
	local installed="$1" preexisting="$2" replaced="$3"
	local rel destination temp
	while IFS= read -r rel || [ -n "$rel" ]; do
		[ -n "$rel" ] || continue
		destination="$PERSISTENT_DIR/$rel"
		if grep -Fqx -- "$rel" "$preexisting" 2>/dev/null; then
			temp="${destination}.rollback.$$"
			if cp -p "$replaced/$rel" "$temp" && mv -f "$temp" "$destination"; then
				:
			else
				rm -f "$temp"
				return 1
			fi
		else
			rm -f "$destination"
		fi
	done < "$installed"
	return 0
}

restore_susaf_config() {
	local archive="$1" busybox archive_size state_root stage work
	local members verbose normalized member_count verbose_count total_bytes
	local expected_manifest restore_files preexisting installed
	local stamp backup_root replaced rel source destination destination_dir temp mode
	local newline carriage_return
	local rollback_result=not-needed restored_count=0

	[ -d "$PERSISTENT_DIR" ] && [ ! -L "$PERSISTENT_DIR" ] || {
		echo '[!] Refused unsafe SusAF config directory'
		return 1
	}
	susaf_backup_directory_safe "$PERSISTENT_DIR/state" || {
		echo '[!] Refused unsafe SusAF state directory'
		return 1
	}
	susaf_restore_prepare_report || {
		echo '[!] Could not create restore report'
		return 1
	}
	susaf_restore_note "schema=$SUSAF_BACKUP_SCHEMA"

	[ -n "$archive" ] || { susaf_restore_reject archive-missing; return 1; }
	newline='
'
	carriage_return=$(printf '\r')
	case "$archive" in *"$newline"*|*"$carriage_return"*) susaf_restore_reject unsafe-archive-path; return 1 ;; esac
	[ -f "$archive" ] && [ ! -L "$archive" ] || { susaf_restore_reject unsafe-archive; return 1; }
	archive_size=$(susaf_backup_file_size "$archive")
	case "$archive_size" in ''|*[!0-9]*) susaf_restore_reject archive-size-unavailable; return 1 ;; esac
	susaf_restore_note "archive_bytes=$archive_size"
	[ "$archive_size" -le "$SUSAF_BACKUP_MAX_ARCHIVE_BYTES" ] || {
		susaf_restore_reject archive-too-large
		return 1
	}
	busybox=$(susaf_backup_busybox) || { susaf_restore_reject busybox-unavailable; return 1; }

	state_root="$PERSISTENT_DIR/state/restore"
	susaf_backup_directory_safe "$state_root" || {
		susaf_restore_reject unsafe-staging-directory
		return 1
	}
	for destination_dir in "$PERSISTENT_DIR/scripts" "$PERSISTENT_DIR/.webui_config" "$PERSISTENT_DIR/restore"; do
		susaf_backup_directory_safe "$destination_dir" || {
			susaf_restore_reject unsafe-live-directory
			return 1
		}
	done
	work="$state_root/work.$$"
	stage="$work/stage"
	members="$work/members.txt"
	verbose="$work/verbose.txt"
	normalized="$work/normalized.txt"
	expected_manifest="$work/expected-manifest"
	restore_files="$work/restore-files.txt"
	preexisting="$work/preexisting.txt"
	installed="$work/installed.txt"
	umask 077
	mkdir -p "$stage" || { susaf_restore_reject staging-failed; return 1; }
	: > "$normalized"; : > "$restore_files"; : > "$preexisting"; : > "$installed"

	if ! "$busybox" tar tzf "$archive" > "$members" 2>/dev/null || \
		! "$busybox" tar tvzf "$archive" > "$verbose" 2>/dev/null; then
		rm -rf "$work"
		susaf_restore_reject invalid-archive
		return 1
	fi
	member_count=$(wc -l < "$members" | tr -d '[:space:]')
	verbose_count=$(wc -l < "$verbose" | tr -d '[:space:]')
	case "$member_count$verbose_count" in *[!0-9]*) rm -rf "$work"; susaf_restore_reject invalid-member-list; return 1 ;; esac
	susaf_restore_note "archive_entries=$member_count"
	if [ "$member_count" -lt 1 ] || [ "$member_count" -gt "$SUSAF_BACKUP_MAX_ENTRIES" ] || [ "$verbose_count" -ne "$member_count" ]; then
		rm -rf "$work"
		susaf_restore_reject invalid-member-count
		return 1
	fi
	if ! awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { exit 1 }' "$verbose"; then
		rm -rf "$work"
		susaf_restore_reject unsafe-member-type
		return 1
	fi
	# BusyBox represents hard links with a regular-file mode plus " -> target".
	if grep -Fq ' -> ' "$verbose"; then
		rm -rf "$work"
		susaf_restore_reject unsafe-member-type
		return 1
	fi
	if ! total_bytes=$(awk -v limit="$SUSAF_BACKUP_MAX_TOTAL_BYTES" '
		substr($1,1,1) == "-" {
			if ($3 !~ /^[0-9]+$/) exit 2
			total += $3
			if (total > limit) exit 3
		}
		END { printf "%.0f\n", total + 0 }
	' "$verbose"); then
		rm -rf "$work"
		susaf_restore_reject extracted-size-invalid
		return 1
	fi
	susaf_restore_note "declared_bytes=$total_bytes"

	while IFS= read -r rel || [ -n "$rel" ]; do
		if ! susaf_backup_member_allowed "$rel"; then
			rm -rf "$work"
			susaf_restore_reject unsafe-member
			return 1
		fi
		rel=$(susaf_backup_normalize_member "$rel")
		[ -n "$rel" ] || continue
		if grep -Fqx -- "$rel" "$normalized" 2>/dev/null; then
			rm -rf "$work"
			susaf_restore_reject duplicate-member
			return 1
		fi
		printf '%s\n' "$rel" >> "$normalized"
	done < "$members"

	if ! "$busybox" tar xzf "$archive" -C "$stage" 2>/dev/null; then
		rm -rf "$work"
		susaf_restore_reject extraction-failed
		return 1
	fi
	if [ -n "$(find "$stage" ! -type f ! -type d -print 2>/dev/null | head -n1)" ]; then
		rm -rf "$work"
		susaf_restore_reject unsafe-extracted-type
		return 1
	fi
	if ! susaf_restore_manifest_valid "$stage/.susaf-backup-manifest" "$expected_manifest"; then
		rm -rf "$work"
		susaf_restore_reject invalid-manifest
		return 1
	fi

	for rel in config.txt kernel_umount.txt kstat_paths.txt open_redirect.txt \
		scripts_bootcompleted.txt scripts_postfs.txt scripts_cron.txt sus_maps.txt \
		sus_paths.txt sus_paths_loop.txt uname.txt cmdline_or_bootconfig.txt \
		.webui_config/custom.css .webui_config/custom_background.webp \
		.webui_config/custom_background.jpg .webui_config/custom_background.png; do
		susaf_restore_add_file "$stage" "$rel" "$restore_files" || {
			rm -rf "$work"; susaf_restore_reject invalid-staged-file; return 1;
		}
	done
	if [ -d "$stage/scripts" ]; then
		for source in "$stage"/scripts/*.sh; do
			[ -e "$source" ] || continue
			rel="scripts/${source##*/}"
			susaf_restore_add_file "$stage" "$rel" "$restore_files" || {
				rm -rf "$work"; susaf_restore_reject invalid-staged-script; return 1;
			}
		done
	fi
	[ -s "$restore_files" ] || { rm -rf "$work"; susaf_restore_reject empty-backup; return 1; }

	stamp="${SUSAF_RESTORE_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup_root="$PERSISTENT_DIR/restore/$stamp"
	[ ! -e "$backup_root" ] || backup_root="$PERSISTENT_DIR/restore/${stamp}_$$"
	replaced="$backup_root/replaced"
	mkdir -p "$replaced" || { rm -rf "$work"; susaf_restore_reject collision-backup-failed; return 1; }
	chmod 700 "$PERSISTENT_DIR/restore" "$backup_root" "$replaced" 2>/dev/null

	while IFS= read -r rel || [ -n "$rel" ]; do
		[ -n "$rel" ] || continue
		destination="$PERSISTENT_DIR/$rel"
		if [ -e "$destination" ] || [ -L "$destination" ]; then
			if [ ! -f "$destination" ] || [ -L "$destination" ]; then
				rm -rf "$work"
				susaf_restore_reject unsafe-live-destination
				return 1
			fi
			mkdir -p "$replaced/$(dirname "$rel")" || { rm -rf "$work"; susaf_restore_reject collision-backup-failed; return 1; }
			cp -p "$destination" "$replaced/$rel" || { rm -rf "$work"; susaf_restore_reject collision-backup-failed; return 1; }
			printf '%s\n' "$rel" >> "$preexisting"
		fi
	done < "$restore_files"

	while IFS= read -r rel || [ -n "$rel" ]; do
		[ -n "$rel" ] || continue
		source="$stage/$rel"
		destination="$PERSISTENT_DIR/$rel"
		destination_dir=$(dirname "$destination")
		mkdir -p "$destination_dir" || break
		temp="${destination}.restore.$$"
		if ! cp "$source" "$temp"; then rm -f "$temp"; break; fi
		case "$rel" in scripts/*.sh) mode=700 ;; *) mode=600 ;; esac
		if ! chmod "$mode" "$temp" 2>/dev/null || ! mv -f "$temp" "$destination"; then
			rm -f "$temp"
			break
		fi
		printf '%s\n' "$rel" >> "$installed"
		restored_count=$((restored_count + 1))
	done < "$restore_files"

	if [ "$restored_count" -ne "$(wc -l < "$restore_files" | tr -d '[:space:]')" ]; then
		if susaf_restore_rollback "$installed" "$preexisting" "$replaced"; then
			rollback_result=restored
		else
			rollback_result=failed
		fi
		rm -rf "$work"
		susaf_restore_note "collision_backup=$backup_root"
		susaf_restore_note "rollback=$rollback_result"
		susaf_restore_reject install-failed
		return 1
	fi

	rm -rf "$work"
	susaf_restore_note "restored_files=$restored_count"
	susaf_restore_note "collision_backup=$backup_root"
	susaf_restore_note "rollback=not-needed"
	susaf_restore_finish restored
	return 0
}

susaf_export_copy() {
	local stage="$1" rel="$2"
	local source="$PERSISTENT_DIR/$rel" destination="$stage/$rel" size limit
	[ -e "$source" ] || return 0
	[ -f "$source" ] && [ ! -L "$source" ] || return 1
	size=$(susaf_backup_file_size "$source")
	case "$size" in ''|*[!0-9]*) return 1 ;; esac
	limit=$(susaf_backup_limit_for "$rel")
	[ "$size" -le "$limit" ] || return 1
	mkdir -p "$(dirname "$destination")" || return 1
	cp -p "$source" "$destination" || return 1
	SUSAF_EXPORT_FILE_COUNT=$((SUSAF_EXPORT_FILE_COUNT + 1))
}

export_susaf_config() {
	local busybox export_dir state_root stage stamp out out_temp rel source
	busybox=$(susaf_backup_busybox) || { echo '[!] BusyBox is unavailable'; return 1; }
	export_dir="${SUSAF_EXPORT_DIR:-/storage/emulated/0/Download}"
	[ -d "$PERSISTENT_DIR" ] && [ ! -L "$PERSISTENT_DIR" ] || { echo '[!] SusAF config directory is unavailable'; return 1; }
	mkdir -p "$export_dir" || return 1
	[ -d "$export_dir" ] && [ ! -L "$export_dir" ] || return 1
	state_root="$PERSISTENT_DIR/state"
	susaf_backup_directory_safe "$state_root" || { echo '[!] Refused unsafe SusAF state directory'; return 1; }
	for rel in scripts .webui_config; do
		susaf_backup_directory_safe "$PERSISTENT_DIR/$rel" || { echo "[!] Refused unsafe SusAF directory: $rel"; return 1; }
	done
	stage="$state_root/export.$$"
	umask 077
	mkdir -p "$stage" || return 1
	{
		printf 'schema=%s\n' "$SUSAF_BACKUP_SCHEMA"
		printf 'module_id=susaf\n'
		printf 'format=tar.gz\n'
	} > "$stage/.susaf-backup-manifest" || { rm -rf "$stage"; return 1; }
	SUSAF_EXPORT_FILE_COUNT=0

	for rel in config.txt kernel_umount.txt kstat_paths.txt open_redirect.txt \
		scripts_bootcompleted.txt scripts_postfs.txt scripts_cron.txt sus_maps.txt \
		sus_paths.txt sus_paths_loop.txt uname.txt cmdline_or_bootconfig.txt \
		.webui_config/custom.css .webui_config/custom_background.webp \
		.webui_config/custom_background.jpg .webui_config/custom_background.png; do
		susaf_export_copy "$stage" "$rel" || { rm -rf "$stage"; echo "[!] Refused unsafe or oversized config: $rel"; return 1; }
	done
	if [ -d "$PERSISTENT_DIR/scripts" ] && [ ! -L "$PERSISTENT_DIR/scripts" ]; then
		for source in "$PERSISTENT_DIR"/scripts/*.sh; do
			[ -e "$source" ] || continue
			rel="scripts/${source##*/}"
			susaf_backup_member_allowed "$rel" || { rm -rf "$stage"; echo "[!] Refused unsafe script name: $rel"; return 1; }
			susaf_export_copy "$stage" "$rel" || { rm -rf "$stage"; echo "[!] Refused unsafe or oversized script: $rel"; return 1; }
		done
	elif [ -e "$PERSISTENT_DIR/scripts" ] || [ -L "$PERSISTENT_DIR/scripts" ]; then
		rm -rf "$stage"
		echo '[!] Refused unsafe scripts directory'
		return 1
	fi
	[ "$SUSAF_EXPORT_FILE_COUNT" -gt 0 ] || { rm -rf "$stage"; echo 'NOTHING_TO_EXPORT'; return 1; }

	stamp=$(date +%Y%m%d_%H%M%S)
	out="$export_dir/SusAF_config_${stamp}.tar.gz"
	[ ! -e "$out" ] || out="$export_dir/SusAF_config_${stamp}_$$.tar.gz"
	out_temp="${out}.tmp.$$"
	if ! "$busybox" tar czf "$out_temp" -C "$stage" . 2>/dev/null || [ ! -s "$out_temp" ]; then
		rm -f "$out_temp"
		rm -rf "$stage"
		return 1
	fi
	chmod 600 "$out_temp" 2>/dev/null || { rm -f "$out_temp"; rm -rf "$stage"; return 1; }
	mv -f "$out_temp" "$out" || { rm -f "$out_temp"; rm -rf "$stage"; return 1; }
	rm -rf "$stage"
	printf 'SUSAF_EXPORT_PATH=%s\n' "$out"
}

# EOF

#!/bin/sh

# Non-interactive, preservation-first installation of packaged configuration.
# Existing user configuration and UserHub schedules always win.

_install_note() {
	if command -v ui_print >/dev/null 2>&1; then
		ui_print "$1"
	else
		echo "$1"
	fi
}

merge_schedule_defaults() {
	local src="$1"
	local dst="$2"
	local tmp line added

	[ -f "$src" ] && [ ! -L "$src" ] || return 0
	mkdir -p "$(dirname "$dst")" || return 1
	if [ ! -e "$dst" ]; then
		cp "$src" "$dst" || return 1
		chmod 600 "$dst" 2>/dev/null
		_install_note "[+] Installed default schedule: $(basename "$dst")"
		return 0
	fi
	[ -f "$dst" ] && [ ! -L "$dst" ] || {
		_install_note "[!] Refusing to replace non-regular schedule: $dst"
		return 1
	}

	tmp="${dst}.install.$$"
	cp "$dst" "$tmp" || return 1
	added=0
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] || continue
		if ! grep -Fqx "$line" "$tmp" 2>/dev/null; then
			printf '%s\n' "$line" >> "$tmp" || {
				rm -f "$tmp"
				return 1
			}
			added=$((added + 1))
		fi
	done < "$src"
	mv "$tmp" "$dst" || {
		rm -f "$tmp"
		return 1
	}
	chmod 600 "$dst" 2>/dev/null
	_install_note "[+] Preserved $(basename "$dst"); added $added missing default entries"
}

install_packaged_builtins() {
	local src_dir="$1"
	local dst_dir="$2"
	local backup_root src name dst backup

	[ -d "$src_dir" ] && [ ! -L "$src_dir" ] || return 0
	backup_root="$PERSISTENT_DIR/migration/installer-$(date +%Y%m%d_%H%M%S)-$$/replaced-builtins"
	mkdir -p "$dst_dir" || return 1
	find "$src_dir" -type f -name '*.sh' 2>/dev/null | while IFS= read -r src; do
		name="${src#"$src_dir"/}"
		case "$name" in
			*.sh) ;;
			*) _install_note "[!] Rejected unexpected built-in path: $name"; return 1 ;;
		esac
		dst="$dst_dir/$name"
		mkdir -p "$(dirname "$dst")" || return 1
		if [ -e "$dst" ]; then
			[ -f "$dst" ] && [ ! -L "$dst" ] || {
				_install_note "[!] Refusing to replace non-regular built-in: $dst"
				return 1
			}
			if cmp -s "$src" "$dst"; then
				chmod 755 "$dst" 2>/dev/null
				continue
			fi
			backup="$backup_root/$name"
			mkdir -p "$(dirname "$backup")" || return 1
			cp -p "$dst" "$backup" || return 1
			chmod 600 "$backup" 2>/dev/null
		fi
		cp "$src" "$dst" || return 1
		chmod 755 "$dst" 2>/dev/null
		_install_note "[+] Installed built-in: $name"
	done
}

install_missing_defaults() {
	local src_dir="$1"
	local dst_dir="$2"
	local src rel dst

	[ -d "$src_dir" ] && [ ! -L "$src_dir" ] || return 0
	find "$src_dir" -type f ! -path "$src_dir/scripts/*" \
		! -name 'scripts_postfs.txt' ! -name 'scripts_bootcompleted.txt' 2>/dev/null |
	while IFS= read -r src; do
		rel="${src#"$src_dir"/}"
		dst="$dst_dir/$rel"
		if [ ! -e "$dst" ]; then
			mkdir -p "$(dirname "$dst")" || return 1
			cp "$src" "$dst" || return 1
			chmod 600 "$dst" 2>/dev/null
			_install_note "[+] Installed default config: $rel"
		elif [ ! -f "$dst" ] || [ -L "$dst" ]; then
			_install_note "[!] Refusing non-regular config destination: $dst"
			return 1
		else
			_install_note "[+] Preserved existing config: $rel"
		fi
	done
}

repair_oversized_cmdline_bootconfig() {
	local template="$1"
	local config="$PERSISTENT_DIR/cmdline_or_bootconfig.txt"
	local limit="${SUSAF_BOOTCONFIG_MAX_BYTES:-8191}"
	local size stamp backup temp

	[ -e "$config" ] || return 0
	[ -f "$config" ] && [ ! -L "$config" ] || {
		_install_note "[!] Refusing non-regular cmdline/bootconfig config: $config"
		return 1
	}
	size=$(wc -c < "$config" 2>/dev/null | tr -d '[:space:]')
	case "$size" in
		''|*[!0-9]*) _install_note "[!] Could not measure $config"; return 1 ;;
	esac
	[ "$size" -gt "$limit" ] || return 0
	[ -f "$template" ] && [ ! -L "$template" ] || {
		_install_note "[!] Packaged cmdline/bootconfig template is unavailable"
		return 1
	}

	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup="$PERSISTENT_DIR/migration/installer-$stamp-$$/repaired-config/cmdline_or_bootconfig.txt"
	temp="${config}.repair.$$"
	mkdir -p "$(dirname "$backup")" || return 1
	cp -p "$config" "$backup" || return 1
	cp "$template" "$temp" || return 1
	chmod 600 "$backup" "$temp" 2>/dev/null
	mv "$temp" "$config" || {
		rm -f "$temp"
		return 1
	}
	_install_note "[+] Archived oversized cmdline/bootconfig data ($size bytes) and restored a clean template"
}

remove_generated_kstat_entries() {
	local config="$PERSISTENT_DIR/kstat_paths.txt"
	local stamp backup temp

	[ -e "$config" ] || return 0
	[ -f "$config" ] && [ ! -L "$config" ] || {
		_install_note "[!] Refusing non-regular Sus Kstat config: $config"
		return 1
	}
	temp="${config}.repair.$$"
	awk '
	function generated_module_entry(    i) {
		if ($1 != "/data/adb/ReSuSFS" && $1 != "/data/adb/SusAF") return 0
		if (NF != 13) return 0
		for (i = 2; i <= NF; i++) if ($i != "default") return 0
		return 1
	}
	function legacy_hosts_entry() {
		return NF == 13 && $1 == "/system/etc/hosts" && $2 == "100" &&
			$3 == "default" && $4 == "default" && $5 == "64" &&
			$6 == "default" && $7 == "default" && $8 == "default" &&
			$9 == "default" && $10 == "default" && $11 == "default" &&
			$12 == "1" && $13 == "4096"
	}
	!generated_module_entry() && !legacy_hosts_entry() { print }
	' "$config" > "$temp" || {
		rm -f "$temp"
		return 1
	}
	if cmp -s "$config" "$temp"; then
		rm -f "$temp"
		return 0
	fi

	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup="$PERSISTENT_DIR/migration/installer-$stamp-$$/repaired-config/kstat_paths.txt"
	mkdir -p "$(dirname "$backup")" || { rm -f "$temp"; return 1; }
	cp -p "$config" "$backup" || { rm -f "$temp"; return 1; }
	chmod 600 "$backup" "$temp" 2>/dev/null
	mv "$temp" "$config" || { rm -f "$temp"; return 1; }
	_install_note "[+] Archived and removed stale generated Kstat entries"
}

_rewrite_legacy_builtin_schedule() {
	local schedule="$1"
	local backup_root="$2"
	local staged next suffix

	[ -e "$schedule" ] || return 0
	[ -f "$schedule" ] && [ ! -L "$schedule" ] || return 1
	grep -Fq 'ReSuSFS_' "$schedule" 2>/dev/null || return 0
	staged="${schedule}.rename.$$"
	cp "$schedule" "$staged" || return 1
	for suffix in \
		apply-cmdline-bootconfig apply-kstat-add apply-ksu-settings apply-uname \
		apply-mount-hiding apply-props apply-settings apply-sus-maps \
		apply-sus-paths-loop apply-sus-paths cleanup-markers; do
		next="${staged}.next"
		sed "s/ReSuSFS_${suffix}\.sh/SusAF_${suffix}.sh/g" "$staged" > "$next" || {
			rm -f "$staged" "$next"
			return 1
		}
		mv "$next" "$staged" || return 1
	done
	awk '!seen[$0]++' "$staged" > "${staged}.unique" || return 1
	mv "${staged}.unique" "$staged" || return 1
	if ! cmp -s "$schedule" "$staged"; then
		mkdir -p "$backup_root/schedules" || return 1
		cp -p "$schedule" "$backup_root/schedules/$(basename "$schedule")" || return 1
		mv "$staged" "$schedule" || return 1
		chmod 600 "$schedule" 2>/dev/null
		_install_note "[+] Updated legacy built-in names in $(basename "$schedule")"
	else
		rm -f "$staged"
	fi
}

retire_legacy_builtin_names() {
	local stamp backup_root suffix old
	stamp="${SUSAF_MIGRATION_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
	backup_root="$PERSISTENT_DIR/migration/renamed-builtins-$stamp-$$"

	for old in scripts_postfs.txt scripts_bootcompleted.txt scripts_cron.txt; do
		_rewrite_legacy_builtin_schedule "$PERSISTENT_DIR/$old" "$backup_root" || return 1
	done

	for suffix in \
		apply-cmdline-bootconfig apply-kstat-add apply-ksu-settings apply-uname \
		apply-mount-hiding apply-props apply-settings apply-sus-maps \
		apply-sus-paths-loop apply-sus-paths cleanup-markers; do
		old="$PERSISTENT_DIR/scripts/ReSuSFS_${suffix}.sh"
		[ -e "$old" ] || continue
		[ -f "$old" ] && [ ! -L "$old" ] || {
			_install_note "[!] Refusing unexpected legacy built-in: $old"
			return 1
		}
		mkdir -p "$backup_root/scripts" || return 1
		mv "$old" "$backup_root/scripts/$(basename "$old")" || return 1
		chmod 600 "$backup_root/scripts/$(basename "$old")" 2>/dev/null
		_install_note "[+] Archived renamed built-in: $(basename "$old")"
	done
}

#!/bin/sh

if ! command -v resolve_ksud_bin >/dev/null 2>&1 && [ -r "${MODULE_DIR:-}/lib/ksud.sh" ]; then
	. "$MODULE_DIR/lib/ksud.sh"
fi

collect_kernel_umount_candidates() {
	local mountinfo_file="$1"
	local output_file="$2"

	[ -f "$mountinfo_file" ] && [ -r "$mountinfo_file" ] || return 1

	awk '
	function module_path(value) {
		return value ~ /(^|\/)data\/adb\/modules(_update)?\// || value ~ /(^|\/)adb\/modules(_update)?\//
	}
	{
		separator=0
		for (i=7; i<=NF; i++) {
			if ($i == "-") {
				separator=i
				break
			}
		}
		if (!separator || separator + 3 > NF) next

		root=$4
		mountpoint=$5
		filesystem=$(separator + 1)
		source=$(separator + 2)
		super_options=$(separator + 3)
		reason=""

		if (source == "KSU") {
			reason="source:KSU"
		} else if (module_path(source) || module_path(root)) {
			reason="module-backed"
		} else if (filesystem == "overlay" && module_path(super_options)) {
			reason="module-overlay"
		}

		if (reason != "" && !seen[mountpoint]++) {
			gsub(/\\040/, " ", mountpoint)
			gsub(/\\011/, "\t", mountpoint)
			gsub(/\\012/, "\n", mountpoint)
			gsub(/\\134/, "\\", mountpoint)
			print mountpoint "\t" reason
		}
	}
	' "$mountinfo_file" > "$output_file"
}

kernel_umount_target_is_safe() {
	local target="$1"

	[ -n "$target" ] || return 1
	[ "${#target}" -lt 256 ] || return 1
	case "$target" in
		/*) ;;
		*) return 1 ;;
	esac
	case "$target" in
		/|*/../*|*/..|*/./*|*/.) return 1 ;;
	esac
	case "$target" in
		*[![:print:]]*|*[[:space:]]*) return 1 ;;
	esac
	return 0
}

kernel_umount_target_is_mounted() {
	local mountinfo_file="$1"
	local target="$2"
	awk -v target="$target" '$5 == target { found=1; exit } END { exit !found }' "$mountinfo_file"
}

kernel_umount_report() {
	printf '%s\n' "$*" >> "$KERNEL_UMOUNT_REPORT_TEMP"
	printf '[kernel_umount] %s\n' "$*"
}

kernel_umount_prepare_report() {
	local report_file="$1"
	local report_dir
	report_dir=$(dirname "$report_file")
	mkdir -p "$report_dir" || return 1
	chmod 700 "$report_dir" 2>/dev/null
	KERNEL_UMOUNT_REPORT_FILE="$report_file"
	KERNEL_UMOUNT_REPORT_TEMP="${report_file}.tmp.$$"
	: > "$KERNEL_UMOUNT_REPORT_TEMP" || return 1
	chmod 600 "$KERNEL_UMOUNT_REPORT_TEMP" 2>/dev/null
}

kernel_umount_finish_report() {
	mv "$KERNEL_UMOUNT_REPORT_TEMP" "$KERNEL_UMOUNT_REPORT_FILE"
}

kernel_umount_check_feature() {
	local ksu_bin="$1"
	local check

	check=$("$ksu_bin" feature check kernel_umount 2>/dev/null) || check="unavailable"
	case "$check" in
		supported|managed) ;;
		unsupported) ;;
		*) check="unavailable" ;;
	esac
	printf '%s\n' "$check"
}

apply_kernel_umount_feature() {
	local config_file="${1:-$PERSISTENT_DIR/config.txt}"
	local mode check desired current report_file ksu_bin
	umask 077

	mode=$(get_conf KERNEL_UMOUNT_MODE enabled "$config_file")
	report_file="${SUSAF_KERNEL_UMOUNT_FEATURE_REPORT:-$PERSISTENT_DIR/state/kernel_umount.feature.txt}"
	kernel_umount_prepare_report "$report_file" || return 1
	kernel_umount_report "mode=$mode"

	case "$mode" in
		unchanged|enabled|disabled) ;;
		*)
			kernel_umount_report "result=invalid-mode"
			kernel_umount_finish_report
			return 1
			;;
	esac

	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=""
	kernel_umount_report "binary=${ksu_bin:-unavailable}"
	if [ -z "$ksu_bin" ]; then
		kernel_umount_report "check=unavailable"
		kernel_umount_report "result=daemon-unavailable"
		kernel_umount_finish_report
		return 0
	fi

	check=$(kernel_umount_check_feature "$ksu_bin")
	kernel_umount_report "check=$check"
	case "$check" in
		unsupported)
			kernel_umount_report "result=not-supported"
			kernel_umount_finish_report
			return 0
			;;
		unavailable)
			kernel_umount_report "result=interface-unavailable"
			kernel_umount_finish_report
			return 0
			;;
	esac

	if [ "$mode" = "unchanged" ]; then
		kernel_umount_report "set=unchanged"
	else
		[ "$mode" = "enabled" ] && desired=1 || desired=0
		if KSU_MODULE="${MODULE_ID:-susaf}" "$ksu_bin" feature set kernel_umount "$desired" >/dev/null 2>&1; then
			kernel_umount_report "set=$mode"
		else
			kernel_umount_report "result=set-failed"
			kernel_umount_finish_report
			return 1
		fi
	fi

	current=$("$ksu_bin" feature get kernel_umount 2>/dev/null | awk -F': ' '$1 == "Status" { print $2; exit }') || current=""
	[ -n "$current" ] || current="unknown"
	kernel_umount_report "current=$current"
	kernel_umount_report "result=ok"
	kernel_umount_finish_report
}

apply_kernel_umount_mounts() {
	local config_file="${1:-$PERSISTENT_DIR/config.txt}"
	local list_file="${2:-$PERSISTENT_DIR/kernel_umount.txt}"
	local mountinfo_file="${SUSAF_MOUNTINFO:-/proc/1/mountinfo}"
	local mode auto check report_file candidate_file accepted_file ksu_bin
	local target reason line add_count reject_count
	umask 077

	mode=$(get_conf KERNEL_UMOUNT_MODE enabled "$config_file")
	auto=$(get_conf AUTO_KERNEL_UMOUNT 1 "$config_file")
	report_file="${SUSAF_KERNEL_UMOUNT_REPORT:-$PERSISTENT_DIR/state/kernel_umount.report.txt}"
	kernel_umount_prepare_report "$report_file" || return 1
	kernel_umount_report "mode=$mode"
	kernel_umount_report "auto=$auto"

	case "$mode" in
		unchanged|enabled) ;;
		disabled)
			kernel_umount_report "result=disabled"
			kernel_umount_finish_report
			return 0
			;;
		*)
			kernel_umount_report "result=invalid-mode"
			kernel_umount_finish_report
			return 1
			;;
	esac
	case "$auto" in
		0|1) ;;
		*)
			kernel_umount_report "result=invalid-auto-mode"
			kernel_umount_finish_report
			return 1
			;;
	esac

	ksu_bin=$(resolve_ksud_bin 2>/dev/null) || ksu_bin=""
	kernel_umount_report "binary=${ksu_bin:-unavailable}"
	if [ -z "$ksu_bin" ]; then
		kernel_umount_report "check=unavailable"
		kernel_umount_report "result=daemon-unavailable"
		kernel_umount_finish_report
		return 0
	fi

	check=$(kernel_umount_check_feature "$ksu_bin")
	kernel_umount_report "check=$check"
	case "$check" in
		unsupported)
			kernel_umount_report "result=not-supported"
			kernel_umount_finish_report
			return 0
			;;
		unavailable)
			kernel_umount_report "result=interface-unavailable"
			kernel_umount_finish_report
			return 0
			;;
	esac

	[ -f "$mountinfo_file" ] && [ -r "$mountinfo_file" ] || {
		kernel_umount_report "result=mountinfo-unavailable"
		kernel_umount_finish_report
		return 1
	}

	candidate_file="${report_file}.candidates.$$"
	accepted_file="${report_file}.accepted.$$"
	: > "$candidate_file"
	: > "$accepted_file"
	add_count=0
	reject_count=0

	if [ "$auto" = "1" ]; then
		collect_kernel_umount_candidates "$mountinfo_file" "$candidate_file" || {
			rm -f "$candidate_file" "$accepted_file"
			kernel_umount_report "result=parse-failed"
			kernel_umount_finish_report
			return 1
		}
	fi

	if [ -f "$list_file" ] && [ -r "$list_file" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			line=${line%%#*}
			line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
			[ -n "$line" ] || continue
			printf '%s\texplicit\n' "$line" >> "$candidate_file"
		done < "$list_file"
	fi

	while IFS="$(printf '\t')" read -r target reason || [ -n "$target" ]; do
		[ -n "$target" ] || continue
		if ! kernel_umount_target_is_safe "$target"; then
			kernel_umount_report "reject=$target|$reason|unsafe-path"
			reject_count=$((reject_count + 1))
			continue
		fi
		if ! kernel_umount_target_is_mounted "$mountinfo_file" "$target"; then
			kernel_umount_report "reject=$target|$reason|not-mounted"
			reject_count=$((reject_count + 1))
			continue
		fi
		if grep -Fqx "$target" "$accepted_file" 2>/dev/null; then
			kernel_umount_report "skip=$target|$reason|duplicate"
			continue
		fi
		printf '%s\n' "$target" >> "$accepted_file"
		if "$ksu_bin" kernel umount add "$target" --flags 2 >/dev/null 2>&1; then
			kernel_umount_report "add=$target|$reason|ok"
			add_count=$((add_count + 1))
		else
			kernel_umount_report "add=$target|$reason|failed"
			reject_count=$((reject_count + 1))
		fi
	done < "$candidate_file"

	rm -f "$candidate_file" "$accepted_file"
	kernel_umount_report "added=$add_count"
	kernel_umount_report "rejected=$reject_count"
	if "$ksu_bin" kernel notify-module-mounted >/dev/null 2>&1; then
		kernel_umount_report "notify=ok"
	else
		kernel_umount_report "notify=failed"
		kernel_umount_finish_report
		return 1
	fi
	kernel_umount_report "result=ok"
	kernel_umount_finish_report
}

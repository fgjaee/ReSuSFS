#!/bin/sh

adb_mode_get_conf() {
	local key="$1"
	local fallback="$2"
	local config_file="$3"
	local value
	value=$(grep "^$key=" "$config_file" 2>/dev/null | tail -n1 | cut -d= -f2-) || value=""
	[ -n "$value" ] || value="$fallback"
	printf '%s\n' "$value"
}

adb_mode_single_line() {
	printf '%s' "$1" | tr '\r\n' '  ' | sed 's/[[:space:]][[:space:]]*/ /g;s/^ //;s/ $//'
}

adb_mode_report() {
	printf '%s\n' "$*" >> "$ADB_MODE_REPORT_TEMP"
	printf '[adb_mode] %s\n' "$*"
}

adb_mode_read_setting() {
	local key="$1"
	local value
	value=$("$ADB_MODE_SETTINGS_BIN" get global "$key" 2>/dev/null) || value="unavailable"
	adb_mode_single_line "$value"
}

adb_mode_read_prop() {
	local key="$1"
	local value
	value=$("$ADB_MODE_GETPROP_BIN" "$key" 2>/dev/null) || value="unavailable"
	adb_mode_single_line "$value"
}

adb_mode_read_pids() {
	local value
	value=$("$ADB_MODE_PIDOF_BIN" adbd 2>/dev/null) || value=""
	adb_mode_single_line "$value"
}

adb_mode_snapshot() {
	local prefix="$1"
	adb_mode_report "$prefix.development_settings_enabled=$(adb_mode_read_setting development_settings_enabled)"
	adb_mode_report "$prefix.adb_enabled=$(adb_mode_read_setting adb_enabled)"
	adb_mode_report "$prefix.adb_wifi_enabled=$(adb_mode_read_setting adb_wifi_enabled)"
	adb_mode_report "$prefix.init.svc.adbd=$(adb_mode_read_prop init.svc.adbd)"
	adb_mode_report "$prefix.adbd_pid=$(adb_mode_read_pids)"
	adb_mode_report "$prefix.sys.usb.config=$(adb_mode_read_prop sys.usb.config)"
	adb_mode_report "$prefix.sys.usb.state=$(adb_mode_read_prop sys.usb.state)"
	adb_mode_report "$prefix.persist.sys.usb.config=$(adb_mode_read_prop persist.sys.usb.config)"
}

adb_mode_finish_report() {
	mv "$ADB_MODE_REPORT_TEMP" "$ADB_MODE_REPORT_FILE"
}

apply_adb_mode() {
	local config_file="${1:-$PERSISTENT_DIR/config.txt}"
	local mode confirmation report_dir wait_count service_state adbd_pids key

	ADB_MODE_SETTINGS_BIN="${SUSAF_SETTINGS_BIN:-settings}"
	ADB_MODE_GETPROP_BIN="${SUSAF_GETPROP_BIN:-getprop}"
	ADB_MODE_SETPROP_BIN="${SUSAF_SETPROP_BIN:-setprop}"
	ADB_MODE_PIDOF_BIN="${SUSAF_PIDOF_BIN:-pidof}"
	ADB_MODE_SLEEP_BIN="${SUSAF_SLEEP_BIN:-sleep}"
	ADB_MODE_REPORT_FILE="${SUSAF_ADB_MODE_REPORT:-$PERSISTENT_DIR/state/adb_mode.report.txt}"
	ADB_MODE_REPORT_TEMP="${ADB_MODE_REPORT_FILE}.tmp.$$"

	umask 077
	report_dir=$(dirname "$ADB_MODE_REPORT_FILE")
	mkdir -p "$report_dir" || return 1
	chmod 700 "$report_dir" 2>/dev/null
	: > "$ADB_MODE_REPORT_TEMP" || return 1
	chmod 600 "$ADB_MODE_REPORT_TEMP" 2>/dev/null

	mode=$(adb_mode_get_conf ADB_MODE unchanged "$config_file")
	confirmation=$(adb_mode_get_conf ADB_DISABLE_CONFIRM "" "$config_file")
	adb_mode_report "mode=$mode"
	adb_mode_snapshot before

	case "$mode" in
		unchanged)
			adb_mode_snapshot after
			adb_mode_report "result=unchanged"
			adb_mode_finish_report
			return 0
			;;
		spoof-off)
			adb_mode_snapshot after
			adb_mode_report "result=refused-no-safe-settings-spoof"
			adb_mode_finish_report
			return 1
			;;
		actually-disable)
			if [ "$confirmation" != "disable-adb" ]; then
				adb_mode_snapshot after
				adb_mode_report "result=refused-confirmation-required"
				adb_mode_finish_report
				return 1
			fi
			;;
		*)
			adb_mode_snapshot after
			adb_mode_report "result=invalid-mode"
			adb_mode_finish_report
			return 1
			;;
	esac

	for key in development_settings_enabled adb_enabled adb_wifi_enabled; do
		if ! "$ADB_MODE_SETTINGS_BIN" put global "$key" 0 >/dev/null 2>&1; then
			adb_mode_snapshot after
			adb_mode_report "result=settings-write-failed:$key"
			adb_mode_finish_report
			return 1
		fi
	done

	if ! "$ADB_MODE_SETPROP_BIN" ctl.stop adbd >/dev/null 2>&1; then
		adb_mode_snapshot after
		adb_mode_report "result=adbd-stop-request-failed"
		adb_mode_finish_report
		return 1
	fi

	wait_count=0
	while [ "$wait_count" -lt 5 ]; do
		service_state=$(adb_mode_read_prop init.svc.adbd)
		adbd_pids=$(adb_mode_read_pids)
		[ "$service_state" = "stopped" ] && [ -z "$adbd_pids" ] && break
		"$ADB_MODE_SLEEP_BIN" 1
		wait_count=$((wait_count + 1))
	done

	adb_mode_snapshot after
	for key in development_settings_enabled adb_enabled adb_wifi_enabled; do
		if [ "$(adb_mode_read_setting "$key")" != "0" ]; then
			adb_mode_report "result=settings-verification-failed:$key"
			adb_mode_finish_report
			return 1
		fi
	done
	service_state=$(adb_mode_read_prop init.svc.adbd)
	adbd_pids=$(adb_mode_read_pids)
	if [ "$service_state" != "stopped" ] || [ -n "$adbd_pids" ]; then
		adb_mode_report "result=adbd-still-running"
		adb_mode_finish_report
		return 1
	fi

	adb_mode_report "result=disabled"
	adb_mode_finish_report
}

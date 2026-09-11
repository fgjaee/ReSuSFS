#!/bin/sh

sanitize_bootconfig_file() {
	source_file="$1"
	output_file="$2"
	awk '
	function trim(value) {
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
		return value
	}
	function is_error_key(key) {
		return key == "verifiedbooterror" || key == "verifyerrorpart" || key ~ /\.verifiedbooterror$/ || key ~ /\.verifyerrorpart$/
	}
	function managed_value(key) {
		if (key == "androidboot.warranty_bit") return "0"
		if (key == "androidboot.verifiedbootstate") return "green"
		if (key == "androidboot.vbmeta.device_state") return "locked"
		if (key == "androidboot.flash.locked") return "1"
		if (key == "androidboot.veritymode") return "enforcing"
		return ""
	}
	{
		line=$0
		key=line
		sub(/[[:space:]]*=.*/, "", key)
		key=trim(key)
		if (is_error_key(key)) next
		value=managed_value(key)
		if (value != "") {
			if (seen[key]++) next
			print key " = \"" value "\""
			next
		}
		print line
	}
	' "$source_file" > "$output_file"
}

sanitize_cmdline_file() {
	source_file="$1"
	output_file="$2"
	awk '
	function is_error_key(key) {
		return key == "verifiedbooterror" || key == "verifyerrorpart" || key ~ /\.verifiedbooterror$/ || key ~ /\.verifyerrorpart$/
	}
	function managed_value(key) {
		if (key == "androidboot.warranty_bit") return "0"
		if (key == "androidboot.verifiedbootstate") return "green"
		if (key == "androidboot.vbmeta.device_state") return "locked"
		if (key == "androidboot.flash.locked") return "1"
		if (key == "androidboot.veritymode") return "enforcing"
		return ""
	}
	{
		output=""
		for (i=1; i<=NF; i++) {
			token=$i
			key=token
			sub(/=.*/, "", key)
			if (is_error_key(key)) continue
			value=managed_value(key)
			if (value != "") {
				if (seen[key]++) continue
				token=key "=" value
			}
			output=output (output == "" ? "" : " ") token
		}
		print output
	}
	' "$source_file" > "$output_file"
}


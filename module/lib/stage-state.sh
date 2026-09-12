#!/bin/sh

# Small, atomic boot-stage records consumed by the diagnostics snapshot.
# These files describe execution only; they never contain user script output.

stage_state_begin() {
	local stage="$1"
	local state_dir="$PERSISTENT_DIR/state"
	local report="$state_dir/stage.${stage}.properties"
	local temp="$state_dir/.stage.${stage}.$$"

	umask 077
	mkdir -p "$state_dir" || return 1
	chmod 700 "$state_dir" 2>/dev/null

	SUSAF_STAGE_START_EPOCH=$(date +%s 2>/dev/null)
	SUSAF_STAGE_START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
	case "$SUSAF_STAGE_START_EPOCH" in
		''|*[!0-9]*) SUSAF_STAGE_START_EPOCH=0 ;;
	esac

	{
		printf 'schema=1\n'
		printf 'stage=%s\n' "$stage"
		printf 'status=running\n'
		printf 'started_at=%s\n' "$SUSAF_STAGE_START_TIME"
		printf 'started_epoch=%s\n' "$SUSAF_STAGE_START_EPOCH"
		printf 'finished_at=\n'
		printf 'duration_seconds=\n'
		printf 'exit_status=\n'
	} > "$temp" || return 1
	chmod 600 "$temp" 2>/dev/null
	mv "$temp" "$report"
}

stage_state_finish() {
	local stage="$1"
	local exit_status="${2:-0}"
	local state_dir="$PERSISTENT_DIR/state"
	local report="$state_dir/stage.${stage}.properties"
	local temp="$state_dir/.stage.${stage}.$$"
	local finish_epoch finish_time duration

	finish_epoch=$(date +%s 2>/dev/null)
	finish_time=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
	case "$finish_epoch" in
		''|*[!0-9]*) finish_epoch=0 ;;
	esac
	case "${SUSAF_STAGE_START_EPOCH:-}" in
		''|*[!0-9]*) duration="" ;;
		*)
			duration=$((finish_epoch - SUSAF_STAGE_START_EPOCH))
			[ "$duration" -ge 0 ] 2>/dev/null || duration=""
			;;
	esac

	{
		printf 'schema=1\n'
		printf 'stage=%s\n' "$stage"
		printf 'status=finished\n'
		printf 'started_at=%s\n' "${SUSAF_STAGE_START_TIME:-}"
		printf 'started_epoch=%s\n' "${SUSAF_STAGE_START_EPOCH:-}"
		printf 'finished_at=%s\n' "$finish_time"
		printf 'duration_seconds=%s\n' "$duration"
		printf 'exit_status=%s\n' "$exit_status"
	} > "$temp" || return 1
	chmod 600 "$temp" 2>/dev/null
	mv "$temp" "$report"
}


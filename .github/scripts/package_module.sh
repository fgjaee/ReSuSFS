#!/bin/sh
set -eu

MODULE_SOURCE="${1:-module}"
OUTPUT_ARCHIVE="${2:-dist/SusAF.zip}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"

case "$SOURCE_DATE_EPOCH" in
	''|*[!0-9]*) echo 'SOURCE_DATE_EPOCH must be a Unix timestamp' >&2; exit 1 ;;
esac
[ "$SOURCE_DATE_EPOCH" -ge 315532800 ] || {
	echo 'SOURCE_DATE_EPOCH must be representable by the ZIP format' >&2
	exit 1
}
[ -d "$MODULE_SOURCE" ] && [ ! -L "$MODULE_SOURCE" ] || {
	echo "Unsafe module source: $MODULE_SOURCE" >&2
	exit 1
}
[ ! -e "$OUTPUT_ARCHIVE" ] && [ ! -L "$OUTPUT_ARCHIVE" ] || {
	echo "Refusing to overwrite archive: $OUTPUT_ARCHIVE" >&2
	exit 1
}
if [ -n "$(find "$MODULE_SOURCE" ! -type f ! -type d -print -quit)" ]; then
	echo 'Module source contains a link or special file' >&2
	exit 1
fi

OUTPUT_DIR=$(dirname "$OUTPUT_ARCHIVE")
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)
OUTPUT_ARCHIVE="$OUTPUT_DIR/$(basename "$OUTPUT_ARCHIVE")"
PACKAGE_WORK=$(mktemp -d)
trap 'rm -rf "$PACKAGE_WORK"' EXIT HUP INT TERM
PACKAGE_ROOT="$PACKAGE_WORK/package"
mkdir -p "$PACKAGE_ROOT"
cp -a "$MODULE_SOURCE"/. "$PACKAGE_ROOT"/

TZ=UTC
export TZ
find "$PACKAGE_ROOT" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
	cd "$PACKAGE_ROOT"
	find . -type f -printf '%P\0' \
		| LC_ALL=C sort -z \
		| xargs -0 zip -X -q "$OUTPUT_ARCHIVE"
)

[ -s "$OUTPUT_ARCHIVE" ] || {
	echo 'Packaging produced an empty archive' >&2
	exit 1
}

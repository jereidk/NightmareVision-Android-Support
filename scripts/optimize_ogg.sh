#!/usr/bin/env bash
# optimize_ogg.sh
# Re-encodes OGG Vorbis files larger than 1 MB to ~68 kbps / 44100 Hz.
# Run from the repository root before committing audio assets.
#
# Requires: ffmpeg with libvorbis support.
#
# Usage:
#   bash scripts/optimize_ogg.sh [directory]
#
# If no directory is supplied, defaults to ./assets

set -euo pipefail

TARGET_DIR="${1:-./assets}"
SIZE_THRESHOLD=1048576   # 1 MB in bytes
TARGET_BITRATE="68k"
TARGET_RATE=44100

if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg not found. Install it first."
    exit 1
fi

processed=0
skipped=0

while IFS= read -r -d '' file; do
    size=$(stat -c%s "$file")
    if [ "$size" -le "$SIZE_THRESHOLD" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    kb=$(( size / 1024 ))
    echo "Re-encoding ($kb KB): $file"

    tmpfile="${file%.ogg}._tmp_.ogg"
    if ffmpeg -i "$file" \
              -c:a libvorbis \
              -b:a "$TARGET_BITRATE" \
              -ar "$TARGET_RATE" \
              -y -loglevel error \
              "$tmpfile"; then
        newsize=$(stat -c%s "$tmpfile")
        newkb=$(( newsize / 1024 ))
        savings=$(( (size - newsize) * 100 / size ))
        mv "$tmpfile" "$file"
        echo "  Done: ${newkb} KB  (${savings}% smaller)"
        processed=$((processed + 1))
    else
        rm -f "$tmpfile"
        echo "  Warning: ffmpeg failed for $file — skipping"
    fi
done < <(find "$TARGET_DIR" -type f -name "*.ogg" -print0)

echo ""
echo "Done. Re-encoded: $processed file(s). Skipped (≤1 MB): $skipped file(s)."

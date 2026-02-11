#!/bin/bash
# Usage: ./drive_temp_logger.sh <csv_path> <disk1> <disk2> ...

CSV="$1"; shift
DRIVES=("$@")


# Initialize CSV and force write to disk
echo "timestamp,drive_wwn,temp_c" > "$CSV"

resolve_dev() { readlink -f "$1"; }

while true; do
    TS="$(date '+%F %T')"
    for wwn in "${DRIVES[@]}"; do
        dev="$(resolve_dev "$wwn")"
        # Specifically targets "Current Drive Temperature: 25 C" from your smartctl output
        temp=$(smartctl -a "$dev" | grep "Current Drive Temperature" | awk '{print $(NF-1)}' | grep -oE '[0-9]+' || echo "NaN")
        
        echo "$TS,$(basename "$wwn"),$temp" >> "$CSV"
    done
    # No sleep here for the first test, or keep at 60s
    sleep 60
done
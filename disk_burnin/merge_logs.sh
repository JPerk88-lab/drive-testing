#!/bin/bash
set -euo pipefail

HBA_LOG="$1/hba_temp.log"
DRIVE_LOG="$2/drive_temps.csv"
PHASE_DIR="$3"

OUT_CSV="$HOME/logs/drive_burnin_${RUN_ID}_timeline.csv"
echo "timestamp,hba_temp,drive_temp,phase" > "$OUT_CSV"

# Combine line by line (naive approach; assumes timestamps roughly aligned)
while read -r ts hba; do
    drive=$(grep "$ts" "$DRIVE_LOG" | awk -F',' '{print $2}')
    phase=$(grep "$ts" "$PHASE_DIR"/*.txt || echo "")
    echo "$ts,$hba,$drive,$phase" >> "$OUT_CSV"
done < <(awk -F',' '{print $1","$2}' "$HBA_LOG")

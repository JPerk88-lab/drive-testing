#!/bin/bash
# score_drives.sh - SAS-aware SMART post-burn scorer

set -euo pipefail

LOG_DIR="${1:-.}"
OUTPUT_CSV="$LOG_DIR/drive_scorecard.csv"

echo "Serial,WWN,Hours,Grown_Defects,Non_Medium_Errors,Uncorrected_Read,Uncorrected_Write,Tier,Verdict" \
    > "$OUTPUT_CSV"

for f in "$LOG_DIR"/smart_postburn_*.txt; do
    [ -e "$f" ] || continue

    WWN=$(basename "$f" | sed 's/smart_postburn_//;s/.txt//')

    SN=$(grep "Serial number:" "$f" | awk -F': ' '{print $2}' | xargs)

    HOURS=$(grep "number of hours powered up =" "$f" | grep -oE '[0-9]+' | head -1)

    GROWN=$(grep "Elements in grown defect list:" "$f" | awk -F': ' '{print $2}')
    NON_MED=$(grep "Non-medium error count:" "$f" | awk -F': ' '{print $2}')

    # SAS: uncorrected errors are LAST column
    UNC_R=$(grep "^read:" "$f" | awk '{print $NF}')
    UNC_W=$(grep "^write:" "$f" | awk '{print $NF}')

    # Defaults
    HOURS=${HOURS:-0}
    GROWN=${GROWN:-0}
    NON_MED=${NON_MED:-0}
    UNC_R=${UNC_R:-0}
    UNC_W=${UNC_W:-0}

    # Tiering (SAS-aware, conservative)
    if [ "$UNC_R" -gt 0 ] || [ "$UNC_W" -gt 0 ]; then
        TIER="D"; VERDICT="DISCARD"
    elif [ "$GROWN" -gt 0 ] || [ "$NON_MED" -gt 25 ]; then
        TIER="C"; VERDICT="MONITOR"
    elif [ "$HOURS" -gt 60000 ]; then
        TIER="B"; VERDICT="KEEP (AGING)"
    else
        TIER="A"; VERDICT="KEEP"
    fi

    echo "$SN,$WWN,$HOURS,$GROWN,$NON_MED,$UNC_R,$UNC_W,$TIER,$VERDICT" \
        >> "$OUTPUT_CSV"
done

echo "✅ Scorecard generated: $OUTPUT_CSV"

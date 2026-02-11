#!/bin/bash
# 01_preburn_screen.sh - SAS drive screening with "Soft Fail" and Short Test trigger

set -euo pipefail

TARGET_LOG_DIR="${LOG_DIR:-.}"
LOG_FILE="$TARGET_LOG_DIR/drive_screen.log"
DRIVES=("$@")

if [ "${#DRIVES[@]}" -eq 0 ]; then
    echo "Usage: $0 /dev/disk/by-id/wwn-XXXX [...]"
    exit 1
fi

echo "--- Screening Session: $(date) ---" >> "$LOG_FILE"
HEADER="WWN,Serial,Hours,Grown_Defects,Non_Med,UNC_Err,Decision"
echo "$HEADER" | tee -a "$LOG_FILE"

for d in "${DRIVES[@]}"; do
    INFO=$(smartctl -i -H -A -l error -d scsi "$d" 2>/dev/null || true)

    if [ -z "$INFO" ]; then
        echo "UNKNOWN,$d,0,0,0,0,SKIP (SMARTCTL FAILED)" | tee -a "$LOG_FILE"
        continue
    fi

    # Parsing
    WWN=$(echo "$INFO" | grep "Logical Unit id:" | awk '{print $NF}')
    SN=$(echo "$INFO" | grep "Serial number:" | awk -F': ' '{print $2}' | xargs)
    HOURS=$(echo "$INFO" | grep "number of hours powered up =" | grep -oE '[0-9]+' | head -1)
    GROWN=$(echo "$INFO" | grep "Elements in grown defect list:" | awk -F': ' '{print $2}' | xargs)
    NON_MED=$(echo "$INFO" | grep "Non-medium error count:" | awk -F': ' '{print $2}' | xargs)
    UNC=$(echo "$INFO" | grep "^read:" | awk '{print $8}')

    HOURS=${HOURS:-0}; GROWN=${GROWN:-0}; NON_MED=${NON_MED:-0}; UNC=${UNC:-0}

    # Logic: Change "SKIP" to "REJECT" so the wrapper knows to isolate it
    if [ "$UNC" -gt 0 ]; then DECISION="REJECT (UNCORRECTED)"
    elif [ "$GROWN" -gt 50 ]; then DECISION="REJECT (HIGH DEFECTS)"
    elif [ "$NON_MED" -gt 50 ]; then DECISION="OPTIONAL (MONITOR)"
    elif [ "$HOURS" -gt 65000 ]; then DECISION="OPTIONAL (OLD)"
    else DECISION="BURN-IN RECOMMENDED"; fi

    # Trigger Short Test for Rejected/Questionable drives
    # if [[ "$DECISION" == REJECT* ]] || [[ "$DECISION" == OPTIONAL* ]]; then
    #     echo "[!] $SN: Triggering Short Self-Test..." >&2 # Send to stderr for visibility
    #     # Capture the output of the trigger command to see why it might fail
    #     TRIGGER_RES=$(smartctl -t short -d scsi "$d" 2>&1) || true
    #     echo "    Result: $(echo "$TRIGGER_RES" | grep -i "test" | head -1)" >&2
    # fi

    echo "$WWN,$SN,$HOURS,$GROWN,$NON_MED,$UNC,$DECISION" | tee -a "$LOG_FILE"
    sync "$LOG_FILE"
done

echo "✅ Screening log saved to: $LOG_FILE"
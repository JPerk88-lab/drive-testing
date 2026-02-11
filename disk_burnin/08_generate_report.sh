#!/bin/bash

# Source the slot database
declare -A SLOTS
source "$HOME/scripts/drive-testing/disk_burnin/drive_slots.conf"

LOG_DIR=$(ls -d ~/logs/drive_burnin_$(date +%F)*/ 2>/dev/null | tail -n 1)

echo "### 📊 Burn-in Results: $(date +%F)"
echo ""
echo "| Status | Slot | WWN | Result / Errors |"
echo "| :--- | :--- | :--- | :--- |"

for log in "$LOG_DIR"badblocks_*.log; do
    [ -e "$log" ] || continue
    WWN=$(basename "$log" | sed 's/badblocks_//;s/.log//')
    MY_SLOT=${SLOTS[$WWN]:-"??"}
    
    ERRORS=$(grep -vE "done,|elapsed" "$log" | sed 's/[^[:print:]]//g' | grep -v "^$" | wc -l)
    PROGRESS=$(tr '\b' '\n' < "$log" | grep "done," | tail -n 1 | sed 's/[^[:print:]]//g')
    
    if [ "$ERRORS" -gt 0 ]; then
        STATUS="**REMOVE**"
        RESULT="FAILED ($ERRORS errors)"
    elif [[ "$PROGRESS" == *"100.00% done"* ]]; then
        STATUS="**KEEP**"
        RESULT="PASS"
    else
        STATUS="**TESTING**"
        RESULT="In Progress ($PROGRESS)"
    fi

    echo "| $STATUS | **$MY_SLOT** | \`$WWN\` | $RESULT |"
done
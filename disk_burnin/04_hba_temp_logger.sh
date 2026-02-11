#!/bin/bash
LOG_FILE="$1"
STORCLI="/usr/local/bin/storcli64"

echo "timestamp,hba,temp_c" > "$LOG_FILE"

while true; do
    TS="$(date '+%F %T')"
    # Capture HBA 0 ROC temperature
    T0=$($STORCLI /c0 show all | grep "ROC temperature" | awk '{print $NF}' | grep -oE '[0-9]+' || echo "0")
    
    if [ "$T0" != "0" ]; then
        echo "$TS,HBA0,$T0" >> "$LOG_FILE"
    fi
    sleep 60
done
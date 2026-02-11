#!/bin/bash
# Usage: ./summarize_burnin.sh <log_dir>

LOG_DIR="$1"
DRIVE_LOG="$LOG_DIR/drive_temps.csv"
HBA_LOG="$LOG_DIR/hba_temp.csv"

echo -e "\n=== FINAL THERMAL SUMMARY ==="

process_stats() {
    local file="$1"
    local label="$2"
    if [[ ! -f "$file" ]]; then return; fi

    echo -e "\n$label Statistics:"
    echo -e "IDENTIFIER\tMIN\tMAX\tAVG"
    echo "--------------------------------------------"
    
    awk -F',' 'NR > 1 {
        id=$2; val=$3;
        if(val == "" || val == "NaN" || val == 0) next;
        sum[id]+=val; count[id]++;
        if(!(id in min) || val < min[id]) min[id]=val;
        if(!(id in max) || val > max[id]) max[id]=val;
    } END {
        for (i in count) 
            printf "%s\t%d°C\t%d°C\t%.1f°C\n", i, min[i], max[i], sum[i]/count[i]
    }' "$file"
}

process_stats "$HBA_LOG" "HBA"
process_stats "$DRIVE_LOG" "Drive"
echo -e "============================================\n"
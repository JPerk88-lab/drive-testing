#!/bin/bash
# 08_score_drives_homelab.sh - Balanced SAS SMART scoring for Homelab ZFS use
# Usage: ./08_score_drives_homelab.sh /path/to/logs

set -euo pipefail

LOG_DIR="${1:-.}"
OUTPUT_CSV="$LOG_DIR/drive_scorecard_zfs.csv"

# Header matches 07_score_drives_zfs.sh for consistency
echo "Serial,WWN,Hours,Grown_Defects,Grown_Delta,UNC_Read,Score,Tier,Verdict,ZFS_Recommendation" > "$OUTPUT_CSV"

for f in "$LOG_DIR"/smart_postburn_*.txt; do
    [ -e "$f" ] || continue

    # --- 1. POST-BURN EXTRACTION ---
    WWN=$(basename "$f" | sed 's/smart_postburn_//;s/.txt//')
    SN=$(grep "Serial number:" "$f" | awk -F': ' '{print $2}' | xargs)
    HOURS=$(grep "number of hours powered up =" "$f" | grep -oE '[0-9]+' | head -1)
    GROWN_POST=$(grep "Elements in grown defect list:" "$f" | awk -F': ' '{print $2}' | xargs)
    UNC_R_POST=$(grep "^read:" "$f" | awk '{print $8}')
    NON_MED=$(grep "Non-medium error count:" "$f" | awk -F': ' '{print $2}' | xargs)

    # Defaults
    HOURS=${HOURS:-0}; GROWN_POST=${GROWN_POST:-0}; UNC_R_POST=${UNC_R_POST:-0}; NON_MED=${NON_MED:-0}

    # --- 2. DELTA ANALYSIS ---
    BASE_FILE="$LOG_DIR/smart_baseline_wwn-${WWN}.txt"
    GROWN_DELTA=0

    if [ -f "$BASE_FILE" ]; then
        GROWN_BASE=$(grep "Elements in grown defect list:" "$BASE_FILE" | awk -F': ' '{print $2}' | xargs || echo 0)
        GROWN_DELTA=$(( GROWN_POST - GROWN_BASE ))
    fi

    # --- 3. HOMELAB BALANCED SCORING MATH ---
    SCORE=100
    CRITICAL_FAIL=0
    REASON=""

    # RULE 1: Any NEW defects during burn-in = Immediate Fail
    if [ "$GROWN_DELTA" -gt 0 ]; then
        SCORE=0; CRITICAL_FAIL=1; REASON="INSTABILITY (New Defects)"
    
    # RULE 2: Existing Hard Failure
    elif [ "$UNC_R_POST" -gt 0 ]; then
        SCORE=0; CRITICAL_FAIL=1; REASON="UNCORRECTABLE ERRORS"

    else
        # A. Age Penalty: -1 per 4000 hours
        SCORE=$(( SCORE - (HOURS / 4000) ))
        
        # B. Defect Penalty: -15 base, -5 per extra
        if [ "$GROWN_POST" -gt 0 ]; then
            SCORE=$(( SCORE - 15 - (GROWN_POST * 5) ))
        fi
        
        # C. Non-Medium: Cap at -10 total
        NM_PENALTY=$NON_MED
        [ "$NM_PENALTY" -gt 10 ] && NM_PENALTY=10
        SCORE=$(( SCORE - NM_PENALTY ))
    fi

    # Clamp
    [ "$SCORE" -lt 0 ] && SCORE=0

    # --- 4. TIERING & VERDICT ---
    if [ "$CRITICAL_FAIL" -eq 1 ]; then
        TIER="D"; VERDICT="REJECT"; RECOMMEND="$REASON"
    elif [ "$SCORE" -ge 80 ]; then
        TIER="A"; VERDICT="KEEP"; RECOMMEND="Primary Pool"
    elif [ "$SCORE" -ge 60 ]; then
        TIER="B"; VERDICT="KEEP"; RECOMMEND="Mirror/Secondary Pool"
    elif [ "$SCORE" -ge 40 ]; then
        TIER="C"; VERDICT="MONITOR"; RECOMMEND="Scratch/Testing"
    else
        TIER="D"; VERDICT="REJECT"; RECOMMEND="Do Not Use"
    fi

    # --- 5. CSV LINE ---
    echo "$SN,$WWN,$HOURS,$GROWN_POST,$GROWN_DELTA,$UNC_R_POST,$SCORE,$TIER,$VERDICT,$RECOMMEND" >> "$OUTPUT_CSV"
done
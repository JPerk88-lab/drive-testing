#!/bin/bash
# 07_score_drives_zfs.sh - Strict Enterprise Scoring with Delta Tracking
# Usage: ./07_score_drives_zfs.sh /path/to/logs

set -euo pipefail

LOG_DIR="${1:-.}"
OUTPUT_CSV="$LOG_DIR/drive_scorecard_zfs.csv"

# Header matches the columns expected by the wrapper display
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
    # Look for the baseline file in the same directory
    BASE_FILE="$LOG_DIR/smart_baseline_wwn-${WWN}.txt"
    GROWN_BASE=0
    UNC_R_BASE=0
    GROWN_DELTA=0

    if [ -f "$BASE_FILE" ]; then
        GROWN_BASE=$(grep "Elements in grown defect list:" "$BASE_FILE" | awk -F': ' '{print $2}' | xargs || echo 0)
        UNC_R_BASE=$(grep "^read:" "$BASE_FILE" | awk '{print $8}' || echo 0)
        
        GROWN_DELTA=$(( GROWN_POST - GROWN_BASE ))
        UNC_DELTA=$(( UNC_R_POST - UNC_R_BASE ))
    else
        GROWN_DELTA=0
        UNC_DELTA=0
    fi

    # --- 3. STRICT SCORING MATH ---
    SCORE=100
    CRITICAL_FAIL=0
    REASON=""

    # RULE 1: Hardware Instability (Deltas)
    if [ "$GROWN_DELTA" -gt 0 ]; then
        SCORE=0; CRITICAL_FAIL=1; REASON="INSTABILITY (New Defects)"
    elif [ "$UNC_DELTA" -gt 0 ]; then
        SCORE=0; CRITICAL_FAIL=1; REASON="FAILURE (New UNC Errors)"
    
    # RULE 2: Critical Thresholds
    elif [ "$UNC_R_POST" -gt 0 ]; then
        SCORE=0; CRITICAL_FAIL=1; REASON="UNCORRECTABLE ERRORS"

    # RULE 3: Enterprise Penalties
    else
        # Strict Aging: -1 point per 1000 hours
        SCORE=$(( SCORE - (HOURS / 2000) ))
        # Strict Defects: -25 points per existing grown defect
        SCORE=$(( SCORE - (GROWN_POST * 25) ))
        # Non-Medium: -1 point per error
        SCORE=$(( SCORE - NON_MED ))
    fi

    # Clamp
    [ "$SCORE" -lt 0 ] && SCORE=0

    # --- 4. TIERING & VERDICT ---
    if [ "$CRITICAL_FAIL" -eq 1 ]; then
        TIER="D"; VERDICT="REJECT"; RECOMMEND="$REASON"
    elif [ "$SCORE" -ge 80 ]; then
        TIER="A"; VERDICT="KEEP"; RECOMMEND="Enterprise Primary"
    elif [ "$SCORE" -ge 60 ]; then
        TIER="B"; VERDICT="KEEP"; RECOMMEND="Secondary/Backup"
    else
        TIER="D"; VERDICT="REJECT"; RECOMMEND="High Risk / End of Life"
    fi

    # --- 5. CSV LINE ---
    echo "$SN,$WWN,$HOURS,$GROWN_POST,$GROWN_DELTA,$UNC_R_POST,$SCORE,$TIER,$VERDICT,$RECOMMEND" >> "$OUTPUT_CSV"
done

# echo "✅ Strict Delta Scorecard generated: $OUTPUT_CSV"
# column -s, -t "$OUTPUT_CSV"
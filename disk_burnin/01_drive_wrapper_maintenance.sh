#!/bin/bash
set -uo pipefail # Removed -e to handle grep misses gracefully, using manual checks instead

# ==========================================
# DRIVE MAINTENANCE WRAPPER (Read-Only Mode)
# ==========================================

# --- CONFIG ---
SCRIPT_DIR="/root/scripts/drive-testing/disk_burnin"
HBA_LOGGER="$SCRIPT_DIR/04_hba_temp_logger.sh"
DRIVE_LOGGER="$SCRIPT_DIR/04_drive_temp_logger.sh"
SUMMARY_SCRIPT="$SCRIPT_DIR/06_summarize_burnin.sh"
PREBURN_SCREEN="$SCRIPT_DIR/02_preburn_screen.sh"
REPORT_SCRIPT="$SCRIPT_DIR/08_generate_report.sh"

# Scoring Scripts
SCORE_BASIC="$SCRIPT_DIR/07_score_drives.sh"
SCORE_STRICT="$SCRIPT_DIR/07_score_drives_zfs.sh"
SCORE_HOMELAB="$SCRIPT_DIR/07_score_drives_homelab.sh"

# --- DRIVE LOADING & ZFS IDENTIFICATION ---
declare -A SLOTS
if [[ -f "$SCRIPT_DIR/drive_slots.conf" ]]; then
    source "$SCRIPT_DIR/drive_slots.conf"
else
    echo "❌ Error: drive_slots.conf not found!"
    exit 1
fi

DRIVES=()
# Get a list of all devices currently active in ZFS (added || true to prevent silent exit)
ZFS_DEVICES=$(zpool status -v 2>/dev/null | grep -E "wwn-|sd[a-z]" | awk '{print $1}' | sort -u || true)

echo "-------------------------------------------------------"
echo " 🛡️  ZFS STATUS CHECK (READ-ONLY)"
echo "-------------------------------------------------------"

for wwn in "${!SLOTS[@]}"; do
    if [[ -e "/dev/disk/by-id/$wwn" ]]; then
        DRIVES+=("/dev/disk/by-id/$wwn")
        if echo "$ZFS_DEVICES" | grep -q "$wwn"; then
            echo -e "\033[0;36m[POOL]\033[0m Drive $wwn is active in ZFS. (Monitoring Only)"
        else
            echo -e "\033[0;32m[FREE]\033[0m Drive $wwn is not in a pool."
        fi
    else
        echo -e "\033[0;33m[WARN]\033[0m Drive $wwn listed in config but NOT FOUND."
    fi
done

if [ ${#DRIVES[@]} -eq 0 ]; then
    echo "❌ No drives found to maintain. Exiting."
    exit 1
fi
echo "-------------------------------------------------------"

# --- INIT ---
RUN_ID="$(date +%F_%H%M%S)_MAINTENANCE"
export LOG_DIR="$HOME/logs/drive_maintenance_$RUN_ID"
export DRIVES_STR="${DRIVES[*]}"
mkdir -p "$LOG_DIR"

echo -e "\033[0;33m"
echo "🛠️  MAINTENANCE MODE: No destructive tests will be performed."
echo -e "\033[0m"
echo "[$(date '+%F %T')] Logs directory: $LOG_DIR"

# --- START LOGGERS ---
HBA_LOG="$LOG_DIR/hba_temp.csv"
DRIVE_LOG="$LOG_DIR/drive_temps.csv"

echo "[$(date '+%F %T')] Starting background loggers..."
nohup stdbuf -oL bash "$HBA_LOGGER" "$HBA_LOG" &>> "$LOG_DIR/hba_logger.log" &
HBA_PID=$!

nohup stdbuf -oL bash "$DRIVE_LOGGER" "$DRIVE_LOG" "${DRIVES[@]}" &>> "$LOG_DIR/drive_logger.log" &
DRIVE_PID=$!

# --- PLOTTER LOOP ---
echo "[$(date '+%F %T')] Starting automated plotter (every 10m)..."
(
    VENV_PYTHON="/root/scripts/drive-testing/hba_venv/bin/python"
    PLOT_SCRIPT="$SCRIPT_DIR/plot_burnin_temps.py"
    while true; do
        if [[ -f "$PLOT_SCRIPT" ]]; then
            $VENV_PYTHON "$PLOT_SCRIPT" "$LOG_DIR" > /dev/null 2>&1
        fi
        sleep 600
    done
) &
PLOTTER_PID=$!

cleanup() {
    echo ""
    echo "[$(date '+%F %T')] Stopping background loggers and plotter..."
    kill "$HBA_PID" "$DRIVE_PID" "$PLOTTER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- HEALTH SCREEN (BASELINE) ---
if [[ -f "$PREBURN_SCREEN" ]]; then
    echo "[$(date '+%F %T')] Capturing baseline SMART diagnostics..."
    # This generates the smart_baseline_*.txt files needed for the report
    bash "$PREBURN_SCREEN" "${DRIVES[@]}" | tee "$LOG_DIR/maintenance_health_check.log"
fi

# Trigger a fresh Short Self-Test
echo "[$(date '+%F %T')] Triggering 2-minute SMART Short Test..."
for d in "${DRIVES[@]}"; do
    smartctl -t short "$d" > /dev/null 2>&1
done

echo "Waiting 130 seconds for tests to complete..."
sleep 130

# --- CAPTURE POST-TEST SNAPSHOT ---
# This ensures the report can compare baseline vs current
echo "[$(date '+%F %T')] Capturing final SMART snapshot..."
for d in "${DRIVES[@]}"; do
    WWN=$(basename "$d")
    smartctl -a "$d" > "$LOG_DIR/smart_postburn_$WWN.txt"
done

# --- SUMMARY & SCORING ---
if [[ -f "$SUMMARY_SCRIPT" ]]; then
    echo "[$(date '+%F %T')] Generating thermal summary..."
    bash "$SUMMARY_SCRIPT" "$LOG_DIR" | tee -a "$LOG_DIR/summary_report.txt"
fi

echo "[$(date '+%F %T')] Analyzing drive health scores..."
[[ -f "$SCORE_BASIC" ]] && bash "$SCORE_BASIC" "$LOG_DIR" &>/dev/null

if [[ -f "$SCORE_STRICT" ]]; then
    echo "[$(date '+%F %T')] Generating Strict Scorecard..."
    bash "$SCORE_STRICT" "$LOG_DIR" > /dev/null
    mv "$LOG_DIR/drive_scorecard_zfs.csv" "$LOG_DIR/scorecard_strict.csv" 2>/dev/null || true
fi

if [[ -f "$SCORE_HOMELAB" ]]; then
    echo "[$(date '+%F %T')] Generating Homelab Scorecard..."
    bash "$SCORE_HOMELAB" "$LOG_DIR" > /dev/null
    mv "$LOG_DIR/drive_scorecard_zfs.csv" "$LOG_DIR/scorecard_homelab.csv" 2>/dev/null || true
    echo -e "\n--- [CURRENT HEALTH RANKINGS] ---"
    column -s, -t "$LOG_DIR/scorecard_homelab.csv" 2>/dev/null || true
fi

# --- FINAL REPORT ---
if [[ -f "$REPORT_SCRIPT" ]]; then
    echo "[$(date '+%F %T')] Generating Maintenance report..."
    bash "$REPORT_SCRIPT" "$LOG_DIR" > "$LOG_DIR/MAINTENANCE_REPORT.md"
    echo "✅ Report generated: $LOG_DIR/MAINTENANCE_REPORT.md"
fi

# --- CLEANUP / ORGANIZATION ---
echo "[$(date '+%F %T')] Organizing logs..."
mkdir -p "$LOG_DIR/raw_data" "$LOG_DIR/debug"

# Move logs to subfolders
mv "$LOG_DIR"/smart_*.txt "$LOG_DIR/raw_data/" 2>/dev/null || true
mv "$LOG_DIR"/*.csv "$LOG_DIR/raw_data/" 2>/dev/null || true
mv "$LOG_DIR"/*.log "$LOG_DIR/debug/" 2>/dev/null || true

# Promote key files back to root for visibility
[[ -f "$LOG_DIR/raw_data/scorecard_homelab.csv" ]] && cp "$LOG_DIR/raw_data/scorecard_homelab.csv" "$LOG_DIR/"
[[ -f "$LOG_DIR/raw_data/scorecard_strict.csv" ]] && cp "$LOG_DIR/raw_data/scorecard_strict.csv" "$LOG_DIR/"
[[ -f "$LOG_DIR/debug/summary_report.txt" ]] && cp "$LOG_DIR/debug/summary_report.txt" "$LOG_DIR/"

echo -e "\n[$(date '+%F %T')] Maintenance Check Completed."
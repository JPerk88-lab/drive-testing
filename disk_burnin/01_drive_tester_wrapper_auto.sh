#!/bin/bash
set -euo pipefail

# ==========================================
# DRIVE BURN-IN WRAPPER (Destructive Mode)
# ==========================================

# --- CONFIG ---
SCRIPT_DIR="/root/scripts/drive-testing/disk_burnin"
BURNIN_SCRIPT="$SCRIPT_DIR/03_drive_burnin.sh"
HBA_LOGGER="$SCRIPT_DIR/04_hba_temp_logger.sh"
DRIVE_LOGGER="$SCRIPT_DIR/04_drive_temp_logger.sh"
SUMMARY_SCRIPT="$SCRIPT_DIR/06_summarize_burnin.sh"
PREBURN_SCREEN="$SCRIPT_DIR/02_preburn_screen.sh"

# Scoring & Reporting
SCORE_BASIC="$SCRIPT_DIR/07_score_drives.sh"
SCORE_STRICT="$SCRIPT_DIR/07_score_drives_zfs.sh"      # Enterprise Logic
SCORE_HOMELAB="$SCRIPT_DIR/07_score_drives_homelab.sh" # Balanced Logic
REPORT_SCRIPT="$SCRIPT_DIR/08_generate_report.sh"

# --- DRIVE LOADING & ZFS SAFETY CHECK ---
declare -A SLOTS
if [[ -f "$SCRIPT_DIR/drive_slots.conf" ]]; then
    source "$SCRIPT_DIR/drive_slots.conf"
else
    echo "❌ Error: drive_slots.conf not found!"
    exit 1
fi

DRIVES=()
# Get a list of all devices currently active in ZFS
ZFS_DEVICES=$(zpool status -v 2>/dev/null | grep -E "wwn-|sd[a-z]" | awk '{print $1}' | sort -u || true)

echo "-------------------------------------------------------"
echo " 🛡️  ZFS SAFETY SCAN"
echo "-------------------------------------------------------"

for wwn in "${!SLOTS[@]}"; do
    # 1. Check if the WWN exists in the active ZFS pool output
    if echo "$ZFS_DEVICES" | grep -q "$wwn"; then
        echo -e "\033[0;31m[SKIP]\033[0m Drive $wwn is currently IN USE by ZFS. Protecting data!"
    else
        # 2. Verify the device actually exists physically
        if [[ -e "/dev/disk/by-id/$wwn" ]]; then
            DRIVES+=("/dev/disk/by-id/$wwn")
            echo -e "\033[0;32m[OK]\033[0m   Drive $wwn is free for testing."
        else
            echo -e "\033[0;33m[WARN]\033[0m Drive $wwn listed in config but NOT FOUND on system."
        fi
    fi
done
echo "-------------------------------------------------------"

# Safety check: Exit if no drives are eligible for testing
if [ ${#DRIVES[@]} -eq 0 ]; then
    echo "❌ No eligible drives found for testing (either missing or in ZFS). Exiting."
    exit 0
fi

# Optional arguments for burn-in
BURNIN_ARGS=("$@")

# --- INIT ---
RUN_ID="$(date +%F_%H%M%S)_$(hostname)"
export LOG_DIR="$HOME/logs/drive_burnin_$RUN_ID"
export DRIVES_STR="${DRIVES[*]}"
mkdir -p "$LOG_DIR"

echo "[$(date '+%F %T')] Logs directory: $LOG_DIR"

# --- START LOGGERS ---
HBA_LOG="$LOG_DIR/hba_temp.csv"
DRIVE_LOG="$LOG_DIR/drive_temps.csv"

echo "[$(date '+%F %T')] Starting background loggers..."
nohup stdbuf -oL bash "$HBA_LOGGER" "$HBA_LOG" &>> "$LOG_DIR/hba_logger.log" &
HBA_PID=$!

nohup stdbuf -oL bash "$DRIVE_LOGGER" "$DRIVE_LOG" "${DRIVES[@]}" &>> "$LOG_DIR/drive_logger.log" &
DRIVE_PID=$!

# === PLOTTER LOOP ===
echo "[$(date '+%F %T')] Starting automated plotter (every 10m)..."
(
    VENV_PYTHON="/root/scripts/drive-testing/hba_venv/bin/python"
    PLOT_SCRIPT="$SCRIPT_DIR/plot_burnin_temps.py"
    while true; do
        if [[ -f "$PLOT_SCRIPT" ]]; then
            $VENV_PYTHON "$PLOT_SCRIPT" "$LOG_DIR" > /dev/null 2>&1
        fi
        sleep 60
    done
) &
PLOTTER_PID=$!

cleanup() {
    echo ""
    echo "[$(date '+%F %T')] Stopping background loggers and plotter..."
    kill "$HBA_PID" "$DRIVE_PID" "$PLOTTER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- PRE-BURN SCREEN ---
if [[ -f "$PREBURN_SCREEN" ]]; then
    echo "[$(date '+%F %T')] Running health check & diagnostic trigger..."
    HEALTHY_DRIVES=()
    
    while IFS=',' read -r WWN SN HOURS GROWN NON_MED UNC DECISION; do
        [[ -z "$SN" || "$WWN" == "WWN" || "$WWN" == ---* ]] && continue
        
        DEVICE_PATH=""
        for original in "${DRIVES[@]}"; do
            if [[ "$original" == *"$WWN"* ]] || [[ "$original" == *"$SN"* ]]; then
                DEVICE_PATH="$original"
                break
            fi
        done

        if [[ "$DECISION" == REJECT* ]]; then
            echo "❌ Drive $SN REJECTED: $DECISION."
        elif [[ -n "$DEVICE_PATH" ]]; then
            echo "✅ Drive $SN PASSED: $DECISION."
            HEALTHY_DRIVES+=("$DEVICE_PATH")
        fi
    done < <(bash "$PREBURN_SCREEN" "${DRIVES[@]}")

    if [ ${#HEALTHY_DRIVES[@]} -eq 0 ]; then
        echo "[!] No healthy drives found to burn-in. Exiting."
        exit 1
    fi
    
    DRIVES=("${HEALTHY_DRIVES[@]}")
    export DRIVES_STR="${DRIVES[*]}"
    export DRIVES
fi

# # --- FINAL CONFIRMATION ---
# echo -e "\n\033[1;31m⚠️  WARNING: DESTRUCTIVE BURN-IN STARTING IN 10 SECONDS ⚠️\033[0m"
# echo "The following drives WILL BE WIPED:"
# for d in "${DRIVES[@]}"; do echo "  -> $d"; done
# echo -e "\nPress Ctrl+C now to abort!"
# sleep 10

# --- EXECUTION ---
echo "[$(date '+%F %T')] Starting burn-in suite..."
DRIVES="${DRIVES[@]}" bash "$BURNIN_SCRIPT" "${BURNIN_ARGS[@]}" 2>&1 | tee -a "$LOG_DIR/burnin.log"

# --- SUMMARY & SCORING ---
if [[ -f "$SUMMARY_SCRIPT" ]]; then
    echo "[$(date '+%F %T')] Generating thermal summary..."
    bash "$SUMMARY_SCRIPT" "$LOG_DIR" | tee -a "$LOG_DIR/summary_report.txt"
fi

[[ -f "$SCORE_BASIC" ]] && bash "$SCORE_BASIC" "$LOG_DIR" &>/dev/null

if [[ -f "$SCORE_STRICT" ]]; then
    echo "[$(date '+%F %T')] Generating Strict ZFS Scorecard..."
    bash "$SCORE_STRICT" "$LOG_DIR" > /dev/null
    mv "$LOG_DIR/drive_scorecard_zfs.csv" "$LOG_DIR/scorecard_strict.csv" 2>/dev/null || true
fi

if [[ -f "$SCORE_HOMELAB" ]]; then
    echo "[$(date '+%F %T')] Generating Homelab Balanced Scorecard..."
    bash "$SCORE_HOMELAB" "$LOG_DIR" > /dev/null
    mv "$LOG_DIR/drive_scorecard_zfs.csv" "$LOG_DIR/scorecard_homelab.csv" 2>/dev/null || true
    echo -e "\n--- [HOMELAB BALANCED RANKINGS] ---"
    column -s, -t "$LOG_DIR/scorecard_homelab.csv" 2>/dev/null || true
fi

# --- GENERATE BOOKSTACK REPORT ---
if [[ -f "$REPORT_SCRIPT" ]]; then
    echo "[$(date '+%F %T')] Generating Markdown report for BookStack..."
    bash "$REPORT_SCRIPT" "$LOG_DIR" > "$LOG_DIR/FINAL_BURNIN_REPORT.md"
fi

# --- CLEANUP / ORGANIZATION ---
echo "[$(date '+%F %T')] Organizing logs into subfolders..."
mkdir -p "$LOG_DIR/raw_data" "$LOG_DIR/debug"

mv "$LOG_DIR"/smart_*.txt "$LOG_DIR/raw_data/" 2>/dev/null || true
mv "$LOG_DIR"/*.csv "$LOG_DIR/raw_data/" 2>/dev/null || true
mv "$LOG_DIR"/*.log "$LOG_DIR/debug/" 2>/dev/null || true

# Promote Key Files
mv "$LOG_DIR/raw_data/scorecard_homelab.csv" "$LOG_DIR/" 2>/dev/null || true
mv "$LOG_DIR/raw_data/scorecard_strict.csv" "$LOG_DIR/" 2>/dev/null || true
mv "$LOG_DIR/debug/summary_report.txt" "$LOG_DIR/" 2>/dev/null || true
mv "$LOG_DIR/debug/burnin.log" "$LOG_DIR/" 2>/dev/null || true

echo -e "\n[$(date '+%F %T')] All tasks completed. Report: $LOG_DIR/FINAL_BURNIN_REPORT.md"
#!/bin/bash
# 03_drive_burnin.sh - Automated Burn-in Suite with Thermal Monitoring
set -euo pipefail

# --- REBUILD DRIVES FROM WRAPPER ---
if [[ -z "${DRIVES_STR:-}" ]]; then 
    echo "ERROR: DRIVES_STR not defined. Please run via the wrapper script." >&2
    exit 1
fi

DRIVES=($DRIVES_STR)
echo "[$(date)] Initializing burn-in for: ${DRIVES[*]}"

# --- CONFIGURATION ---
TEMP_CRIT=55          
TEMP_SAFE=48          
TEMP_POLL=60          
SMART_SLEEP_SHORT=180 
SMART_SLEEP_LONG=28800 

# --- ARGUMENT PARSING ---
SKIP_PHASES=()
RESUME_FROM=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip) IFS=',' read -r -a SKIP_PHASES <<< "$2"; shift 2 ;;
        --resume-from) RESUME_FROM="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# --- HELPERS ---
resolve_dev() { echo "$1"; }

check_drive_temps() {
    local max_t=0
    for d in "${DRIVES[@]}"; do
        local t=$(smartctl -a "$d" | grep -i "Temperature" | grep -oE '[0-9]{2}' | head -n 1 || echo 0)
        [[ -n "$t" && "$t" -gt "$max_t" ]] && max_t=$t
    done
    echo "$max_t"
}

thermal_monitor() {
    local pids=("$@")
    while kill -0 "${pids[@]}" 2>/dev/null; do
        curr=$(check_drive_temps)
        if (( curr >= TEMP_CRIT )); then
            echo "[$(date)] ALERT: High Temp (${curr}°C). Suspending processes."
            kill -STOP "${pids[@]}"
            while (( $(check_drive_temps) > TEMP_SAFE )); do sleep "$TEMP_POLL"; done
            echo "[$(date)] Safe temp reached. Resuming..."
            kill -CONT "${pids[@]}"
        fi
        sleep "$TEMP_POLL"
    done
}

should_run() {
    local phase="$1"
    for skip in "${SKIP_PHASES[@]:-}"; do 
        [[ -n "$skip" && "$phase" == *"$skip"* ]] && return 1
    done
    if [[ -n "$RESUME_FROM" && "$phase" < "$RESUME_FROM" ]]; then return 1; fi
    return 0
}

# --- PHASES ---

# PHASE 01: BASELINE
if should_run PHASE_01_BASELINE; then
    echo "[$(date)] Phase 01: Capturing SMART Baseline..."
    for d in "${DRIVES[@]}"; do
        smartctl -a "$d" > "$LOG_DIR/smart_baseline_$(basename "$d").txt"
    done
fi

# PHASE 02: SMART SHORT (Forced)
if should_run PHASE_02_SMART_SHORT; then
    echo "[$(date)] Phase 02: Starting SMART Short..."
    for d in "${DRIVES[@]}"; do
        echo "Triggering Short Test on $(basename "$d")..."
        # -t force overrides any existing test to prevent Code 255
        if smartctl -t short -t force "$d" >/dev/null 2>&1 || smartctl -d scsi -t short -t force "$d" >/dev/null 2>&1; then
            echo "  [OK] Short test triggered."
        else
            echo "  [ERROR] Failed to trigger Short test."
        fi
    done
    echo "Waiting $SMART_SLEEP_SHORT seconds..."
    sleep "$SMART_SLEEP_SHORT"
fi

# PHASE 03: SMART LONG (Forced)
if should_run PHASE_03_SMART_LONG; then
    echo "[$(date)] Phase 03: Starting SMART Long..."
    for d in "${DRIVES[@]}"; do
        echo "Triggering Long Test on $(basename "$d")..."
        if smartctl -t long -t force "$d" >/dev/null 2>&1 || smartctl -d scsi -t long -t force "$d" >/dev/null 2>&1; then
            echo "  [OK] Long test triggered."
        else
            echo "  [ERROR] Failed to trigger Long test."
        fi
    done
    echo "Waiting $SMART_SLEEP_LONG seconds (8h)..."
    sleep "$SMART_SLEEP_LONG"
fi

# PHASE 04: WRITE TEST (badblocks)
if should_run PHASE_04_WRITE_TEST; then
    echo "[$(date)] Phase 04: Parallel badblocks Write Test..."
    pids=()
    for d in "${DRIVES[@]}"; do
        badblocks -w -s -b 4096 -t 0x00 "$d" > "$LOG_DIR/badblocks_$(basename "$d").log" 2>&1 &
        pids+=($!)
    done
    thermal_monitor "${pids[@]}"
    wait "${pids[@]}"
fi

# PHASE 05: READ VERIFY (dd)
if should_run PHASE_05_READ_VERIFY; then
    echo "[$(date)] Phase 05: Parallel Read Verification..."
    pids=()
    for d in "${DRIVES[@]}"; do
        dd if="$d" of=/dev/null bs=1M iflag=direct status=progress 2> "$LOG_DIR/dd_read_$(basename "$d").log" &
        pids+=($!)
    done
    thermal_monitor "${pids[@]}"
    wait "${pids[@]}"
fi

# PHASE 06: POST-BURN BASELINE
if should_run PHASE_06_POSTBURN; then
    echo "[$(date)] Phase 06: Capturing SMART Post-burn..."
    for d in "${DRIVES[@]}"; do
        smartctl -a "$d" > "$LOG_DIR/smart_postburn_$(basename "$d").txt"
    done
fi

echo "[$(date)] Burn-in process complete. Logs in: $LOG_DIR"
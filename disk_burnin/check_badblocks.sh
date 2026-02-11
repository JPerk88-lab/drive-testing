#!/bin/bash

############################################################################
# check_badblocks.sh
# Description: Parses badblocks log output to summarize drive health and progress.
# Optimized for: VS Code Terminal, SAS/SATA Seagates, and Slot Mapping.
############################################################################

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

LOG_FILE=$1
WWN_NAME=$(basename "$LOG_FILE" | sed 's/badblocks_//;s/.log//')

# --- SLOT MAPPING DATABASE ---
declare -A SLOTS
source "$HOME/scripts/drive-testing/disk_burnin/drive_slots.conf"
MY_SLOT=${SLOTS[$WWN_NAME]:-"Unknown Slot"}
# -----------------------------

if [[ ! -f "$LOG_FILE" ]]; then
    echo -e "${RED}Error: File $LOG_FILE not found.${NC}"
    exit 1
fi

echo -e "${BLUE}-------------------------------------------------------${NC}"

# --- IMPROVED TEMPERATURE HUNTER ---
# Stage 1: Standard SMART attributes (SATA)
TEMP=$(sudo smartctl -a /dev/disk/by-id/$WWN_NAME 2>/dev/null | awk '/Temperature_Celsius|Airflow_Temperature_Cel|Current Drive Temperature|target internal temperature/ {print $NF}' | grep -oE '[0-9]+' | head -n 1)

# Stage 2: SAS/SCSI Protocol Specific Fallback
if [ -z "$TEMP" ]; then
    TEMP=$(sudo smartctl -i -A /dev/disk/by-id/$WWN_NAME 2>/dev/null | grep "Current Drive Temperature" | awk '{print $4}' | grep -oE '[0-9]+')
fi

# Default if both fail
if [ -z "$TEMP" ]; then TEMP="??"; fi

# Apply Temperature Coloring
TEMP_COLOR=$GREEN
if [[ "$TEMP" =~ ^[0-9]+$ ]]; then
    if [ "$TEMP" -ge 45 ]; then TEMP_COLOR=$YELLOW; fi
    if [ "$TEMP" -ge 55 ]; then TEMP_COLOR=$RED; fi
fi

echo -e " SLOT: ${YELLOW}$MY_SLOT${NC} | TEMP: ${TEMP_COLOR}${TEMP}°C${NC}"
echo -e " WWN:  $WWN_NAME"
echo -e "${BLUE}-------------------------------------------------------${NC}"

# --- PROGRESS EXTRACTION ---
# Use tr to handle the backspace characters used by badblocks for live updates
PROGRESS=$(tr '\b' '\n' < "$LOG_FILE" | grep "done," | tail -n 1 | sed 's/[^[:print:]]//g')

if [ -z "$PROGRESS" ]; then
    echo -e " STATUS: ${YELLOW}Initializing...${NC}"
else
    # Red text if any of the (read/write/corruption) error counters are non-zero
    if [[ "$PROGRESS" =~ \([1-9] || "$PROGRESS" =~ /[1-9] ]]; then
        echo -e " PROGRESS: ${RED}$PROGRESS${NC}"
    else
        echo -e " PROGRESS: ${GREEN}$PROGRESS${NC}"
    fi
fi

# --- ERROR SUMMARY ---
echo -e "${BLUE}-------------------------------------------------------${NC}"
echo -e " ERRORS FOUND:"
ERROR_DATA=$(grep -vE "done,|elapsed|Testing with pattern" "$LOG_FILE" | sed 's/[^[:print:]]//g' | grep -v "^$")

if [ -z "$ERROR_DATA" ]; then
    echo -e "  ${GREEN}None (Healthy)${NC}"
else
    echo -e "  ${RED}$ERROR_DATA${NC}"
fi
echo -e "${BLUE}-------------------------------------------------------${NC}"
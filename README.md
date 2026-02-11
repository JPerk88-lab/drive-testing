# 🚀 Drive Burn-in Suite: The "Is My Drive Healthy?" Tool

### 📖 The ELI5 Intro

Imagine you just bought a used car. Before you put your family in it and drive across the country, you’d probably want to:

1. **Check the odometer:** See how many miles are on it (**SMART Screening**).
2. **Test the engine:** Drive it fast on the highway to see if it overheats (**Thermal Monitoring**).
3. **Stress the suspension:** Fill it with heavy boxes to see if it holds up (**Badblocks Stress Test**).

**This script suite does exactly that for your hard drives.** It puts them through a "stress test" (Burn-in) to make sure they won't lose your photos, videos, or documents later.

---

### 🚦 How to use it (The Simple Version)

#### 1. The "Name Tag" Phase (`00_add_wwn.sh`)

Before we start, we need to know which drive is which. This script finds every drive and asks you where it is sitting in your computer (e.g., "Top Left Slot"). This way, if a drive fails, you know exactly which one to pull out.

#### 2. The "Physical Map" (`drive_slots.conf`)

This is just a notebook where the computer stores the "Name Tags" you created in Step 1.

#### 3. The "Stress Test" (`01_drive_tester_wrapper_auto.sh`)

This is the main button. When you press it:

* **Safety Check:** It checks if you have any important files on the drives. If you do, it **stops** and won't touch them.
* **The Workout:** It writes data to every single "room" on the hard drive and then reads it back to make sure nothing changed.
* **The Thermostat:** If the drives get too hot (like a phone sitting in the sun), the script **pauses** the work automatically to let them cool down, then starts again when it's safe.

#### 4. The "Report Card" (`07_score_drives_...`)

Once the test is over, the script gives each drive a grade:

* **Grade A:** Perfect. Use this for your most important files.
* **Grade B/C:** It has some "scratches" (old age or minor errors). Maybe use it for things you have copies of elsewhere.
* **Grade D (Reject):** The drive is broken or about to break. Put it in the trash!

---

### 📈 Why we do this

Hard drives are like lightbulbs; they usually break either in the first few days of use or after many years. By running these scripts, we force those "early breaks" to happen **now** while the drives are empty, rather than **later** when they are holding your memories.

---

# 🗄️ Drive Burn-in & Inventory Management

### 🛠️ Quick Commands

> [!TIP]
> Always verify the WWN matches the physical slot before starting a destructive write test. Use the **Last 4 characters** of the WWN for quick physical identification.

---

## 📂 Script Library Reference

### 🛠️ Phase 0: Intake & Preparation

| Script | Description |
| --- | --- |
| **`00_add_wwn.sh`** | **The Gatekeeper.** Identifies new drives, maps them to physical Slot IDs in `drive_slots.conf`, and generates `wipefs` cleanup commands. |
| **`check_badblocks.sh`** | **The Engine.** The core logic used by `burn-status` and `burn-watch` to parse logs, calculate percentage, and report drive temperature. |

### 🚀 Phase 1-5: The Testing Pipeline

| Script | Description |
| --- | --- |
| **`01_drive_tester_wrapper.sh`** | **The Orchestrator.** The main entry point. Runs the full battery of tests (Baseline, SMART, Badblocks) across all defined drives. |
| **`02_preburn_screen.sh`** | **The Filter.** Performs initial SMART health checks to catch "Dead on Arrival" drives before starting long-running tests. |
| **`03_drive_burnin.sh`** | **The Stressor.** Executes the heavy-lifting `badblocks` destructive write/read patterns to stress the platters and heads. |

### 🌡️ Monitoring & Logging

| Script | Description |
| --- | --- |
| **`04_drive_temp_logger.sh`** | **HDD Monitor.** Periodically polls and logs drive temperatures to ensure they stay within safe thermal limits during the burn-in. |
| **`04_hba_temp_logger.sh`** | **Controller Monitor.** Logs the temperature of your SAS HBA/RAID card to prevent controller throttling or overheating. |

### 📊 Phase 6: Analysis & Reporting

| Script | Description |
| --- | --- |
| **`06_summarize_burnin.sh`** | **The Aggregator.** Collects all raw logs into a single summary file for post-test review. |
| **`07_score_drives.sh`** | **The Judge.** Compares Pre- and Post-burn SMART data to find "hidden" hardware degradation. |
| **`07_score_drives_homelab.sh`** | **Homelab Filter.** A version of the scoring script with slightly more relaxed criteria for used/refurbished drives. |
| **`07_score_drives_zfs.sh`** | **The ZFS Finalist.** High-stringency scoring specifically for drives intended for mission-critical ZFS VDEVs. |
| **`08_generate_report.sh`** | **The Publisher.** Converts final results into a clean Markdown table ready for copy-pasting into BookStack. |

---

> **Future Note:** If you find yourself frequently using the ZFS scoring script over the others, you can create a symlink named `final-score` pointing to `07_score_drives_zfs.sh` to save yourself some typing!

---


### 🗺️ Operational Workflow (Diff Style)

```diff
+ 00_INTAKE    : Run 00_add_wwn.sh (Assign Slots & Wipe)
+ 01_START     : Run 01_drive_tester_wrapper.sh
! 02_SCREEN    : Catch DOA drives with 02_preburn_screen.sh
! 03_BURNIN    : badblocks stress test (Use 'burn-watch' here)
! 04_THERMAL   : Monitor 04_temp_loggers.sh
- 07_SCORE     : Judge results (Standard, Homelab, or ZFS)
- 08_REPORT    : 08_generate_report.sh (Update BookStack)

```

---

### 🗄️ ZFS VDEV Strategy (Diff Style)

> Paste this into your "VDEV Planning" section to quickly identify where drives should go based on their score.

```diff
*** TIER A: PRODUCTION POOL (Mirror / RAIDZ2) ***
+ Health: 0 Badblocks / 0 Reallocated / Low Hours
+ Use for: Proxmox OS, LXC/VM Root Disks, Critical Docs
+ Note: These are your "Gold" drives.

*** TIER B: BULK STORAGE (RAIDZ2 / RAIDZ3) ***
! Health: 0 Badblocks / Minor Hours / Stable SMART
! Use for: Media Server, Backups, ISO Library
! Note: High reliability via parity, despite drive age.

*** TIER C: COLD SPARE / NON-CRITICAL ***
- Health: Passed badblocks / High Hours / "Weakest" link
- Use for: Emergency off-site spare or Scratch Disk
- Note: Do not rely on for primary uptime.

*** FAIL: SCRAP / RMA ***
- Health: Any Badblocks or Increasing Reallocated Count
- Action: Pull immediately. Do not add to any pool.

```

---

**1. Identify New Drives**
Run this to find the WWNs to add to your `drive_slots.conf`.

```bash
# Identify ONLY data drives (Excluding boot drive sda)
ls -l /dev/disk/by-id | grep wwn | grep -vE "part|sda"

# Add WWN's to drive_slots.conf
sudo ./00_add_wwn.sh

```
**Wipe Drive (SKIP - automatic discovery now)**

```bash
# wipefs -a /dev/disk/by-id/wwn-id-here
wipefs -a /dev/disk/by-id/wwn-0x5000c500a7d6d9af
```

**2. Pre-Burn Health Screen**
Gatekeep your drives. If they fail baseline SMART stats, don't waste 48 hours burning them in.

```bash
cd ~/scripts/drive-testing/disk_burnin
sudo ./01_drive_tester_wrapper_auto.sh --skip PHASE_01_BASELINE,PHASE_02_SMART_SHORT,PHASE_03_SMART_LONG,PHASE_04_WRITE_TEST,PHASE_05_READ_VERIFY
# sudo ./01_drive_tester_wrapper.sh --skip PHASE_01_BASELINE,PHASE_02_SMART_SHORT,PHASE_03_SMART_LONG,PHASE_04_WRITE_TEST,PHASE_05_READ_VERIFY

```

**3. Execution & Monitoring**

```bash
# Pre-screen and Smart Short
sudo ./01_drive_tester_wrapper_auto.sh --skip PHASE_03_SMART_LONG,PHASE_04_WRITE_TEST,PHASE_05_READ_VERIFY
# sudo ./01_drive_tester_wrapper.sh --skip PHASE_03_SMART_LONG,PHASE_04_WRITE_TEST,PHASE_05_READ_VERIFY

# Full Burn-in (Remove --skip flags for total soak test)
sudo ./01_drive_tester_wrapper_auto.sh
# sudo ./01_drive_tester_wrapper.sh

# Monitor using aliases (ensure these are in your .zshrc)
burn-status  # Snapshot view
burn-watch   # Live auto-refreshing dashboard

```

**4. Manual Monitoring**

```bash
# Manual status run
for f in ~/logs/drive_burnin_$(date +%F)*/badblocks_*.log; do ~/scripts/drive-testing/disk_burnin/check_badblocks.sh "$f"; done

# Watch debug log for wrapper script errors
tail -f ~/logs/drive_burnin_$(date +%F)*/debug/burnin.log

```

---

## 📊 Drive Status Summary

*Generated via `08_generate_report.sh*`

| Status | WWN / Drive ID | Location | Notes / Action |
| --- | --- | --- | --- |
| <span style="color: #3498db;">**TESTING**</span> | `wwn-0x5000c500af2e15b3` | Oc1-6 | Pending |
| <span style="color: #3498db;">**TESTING**</span> | `wwn-0x5000c500a7d70dcb` | Oc1-7 | **BURN-IN RECOMMENDED** |
| <span style="color: #3498db;">**TESTING**</span> | `wwn-` | Oc1-0 | Pending |
|  |  |  |  |
| <span style="color: #2ecc71;">**KEEP**</span> | `wwn-0x5000c500a6be884f` | Oc1-2 | **Tier A (Healthy)** |
| <span style="color: #f1c40f;">**MARGINAL**</span> | `wwn-0x5000c500a7d70ebf` | Oc2-7 | Tier B (Watch closely) |
|  |  |  |  |
| <span style="color: #e74c3c;">**REMOVE**</span> | `wwn-0x5000c50094ecc9d7` | Oc1-3 | Pull from array |
| <span style="color: #e74c3c;">**REMOVE**</span> | `wwn-0x5000c500a7d6d9af` | Oc2-6 | **HIGH DEFECT COUNT** |

---

## 🧠 Logic & Tiering Criteria

* **Testing Group:** Active work-in-progress. Verify Slot Mapping in `drive_slots.conf` before Phase 4.
* **Marginal (Tier B):** Drives that passed `badblocks` but show non-zero `Reallocated_Sector_Ct` or high `Seek_Error_Rate`. Use for non-critical datasets.
* **Remove:** Non-negotiable failure. Any `badblocks` error or `Current_Pending_Sector` count > 0 post-burn.

---

## 📺 Monitoring Workflow

### 1. The "Command Center"

The `burn-watch` alias uses `check_badblocks.sh` to clean the terminal output, removing backspace noise and adding color-coding:

* **Green:** Healthy / Progressing.
* **Yellow:** Temperature Warning ().
* **Red:** Errors detected in `(0/0/0)` triplet or high heat ().

### 2. Decision Tree

| Observation | Immediate Action | Classification |
| --- | --- | --- |
| **Percentage is increasing** | None. Let it cook. | **TESTING** |
| **(0/0/1+) Corruption** | Stop; Check SAS Cables/Backplane. | **CHECK CABLES** |
| **Percentage frozen > 1hr** | Check `dmesg` for SATA link resets. | **TIMEOUT / FAIL** |
| **Test Interrupted** | Verify power/reboot; resume test. | **RE-TEST** |

---

## Error Tables

### 1. Monitoring Workflow Dashboard

When you run your `burn-watch` alias now, the visual feedback will look like this:

* **Green:** Drive is humming along perfectly.
* **Yellow:** Drive is starting up or has no data yet.
* **Red:** **Action Required.** An error has been logged or the test was killed.

---

### 2. Troubleshooting Guide (Final Piece)

Add this table to your BookStack page to help you interpret the "Red" errors when they appear.

| Script Output | SMART Attribute | Likely Hardware Culprit |
| --- | --- | --- |
| **(1/0/0)** | `197 Current_Pending_Sector` | Platter defect / Weak head. |
| **(0/1/0)** | `196 Reallocated_Event_Count` | Disk firmware failed to map out a bad spot. |
| **(0/0/1)** | `199 UDMA_CRC_Error_Count` | **SATA/SAS Cable.** High chance of a bad connection. |
| **Interrupted** | `12 Power_Cycle_Count` | Power supply issue or loose molex/sata power. |

---



### 3. Your Final BookStack "Management" Setup

Three main tools that all talk to each other:

| Script | Purpose | When to run |
| --- | --- | --- |
| `00_add_wwn.sh` | **The Intake:** Assigns physical locations to new hardware. | When plugging in new drives. |
| `check_badblocks.sh` | **The Monitor:** Shows live progress/temp with Slot IDs. | While tests are running. |
| `08_generate_report.sh` | **The Reporter:** Spits out a Markdown table for BookStack. | When a batch of tests finishes. |

---

### 💡 Pro-Tip: Changing a Slot

If you ever move a drive from `Oc1-7` to `Oc2-1`, you don't need to touch your code or your testing logs. Just run:
`nano ~/scripts/disk_burnin/drive_slots.conf`
Change the name in that one file, and the next time you run `burn-status` or your report generator, the location will be updated everywhere.

---

To wrap up your setup, this **Final Verification Checklist** ensures that any drive marked "PASS" by `badblocks` is truly healthy at the hardware level before you trust it with your data.

You can paste this directly into your BookStack "Drive Validation SOP" page.

---

## 🏁 Final Drive Acceptance Checklist

*Post-Phase 4 Verification*

### 1. The Health Delta Check

Run `07_score_drives.sh` or check manually:

```bash
sudo smartctl -A /dev/disk/by-id/wwn-YOUR_ID

```

| Attribute | Threshold for Failure | Reason |
| --- | --- | --- |
| **ID 5: Reallocated_Sector_Ct** | **> 0** | The drive is physically wearing out. |
| **ID 197: Current_Pending_Sector** | **> 0** | Unstable sectors waiting to be remapped. |
| **ID 199: UDMA_CRC_Error_Count** | **Increasing** | Bad SATA/SAS cable or backplane port. |

### 2. Physical Labeling

Once the drive passes the SMART delta check:

* [ ] Print/Write a label with the **Last 4 of the WWN**.
* [ ] Mark the **Date of Completion**.
* [ ] Affix label to the **Drive Tray handle**.

### 3. ZFS Integration

```bash
# Add by ID to ensure mount persistence
zpool add <pool_name> /dev/disk/by-id/wwn-YOUR_ID

```

---

## 🗂️ Script Inventory & Source of Truth

| Script | Purpose | When to run |
| --- | --- | --- |
| `00_add_wwn.sh` | Updates `drive_slots.conf` | On drive intake. |
| `check_badblocks.sh` | Logic for `burn-watch` dashboard | During active testing. |
| `08_generate_report.sh` | Formats Markdown for BookStack | After batch completion. |
| `drive_slots.conf` | **Source of Truth** for Slot IDs | Update via `00_add_wwn.sh`. |

---

### 💡 Pro-Tip: Changing a Slot

If you move a drive (e.g., `Oc1-7` to `Oc2-1`), do not edit the testing logs. Just update the mapping file:
`nano ~/scripts/drive-testing/disk_burnin/drive_slots.conf`

---

## Aliases for .zshrc and .bashrc

```bash
#############################################################################
# RIGOROUS DRIVE MONITOR (ZSH Version)
# Optimized for 4-Pass badblocks and Parallel Read Verification
#############################################################################
function burn-status() {
    local days_ago=${1:-0}
    local target_date=$(date -d "$days_ago days ago" +%F)
    local base_dir="/root/logs"
    
    local count_healthy=0
    local count_warn=0
    local total_drives=0
    local stale_threshold=3600 # 1 hour threshold for completed phases

    echo -e "\n\033[1;34m=======================================================\033[0m"
    echo -e "\033[1;34m🔍 DRIVE TEST MONITOR: $target_date\033[0m"
    echo -e "\033[1;34m=======================================================\033[0m"

    # --- PHASE 04: WRITE (badblocks) ---
    echo -e "\n\033[1;33m[PHASE 04: WRITE (badblocks)]\033[0m"
    local bb_logs=$(find "$base_dir" -maxdepth 2 -type f -path "*drive_burnin_${target_date}*/*badblocks_*.log" 2>/dev/null | sort)

    if [[ -n "$bb_logs" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            ((total_drives++))
            
            local last_mod=$(stat -c %Y "$f")
            local age=$(($(date +%s) - last_mod))
            local age_color="\033[0;90m"
            
            # Extract progress to see if 100%
            local progress=$(tr -d '\r' < "$f" | grep -oE "[0-9.]+% done" | tail -n 1)
            
            if [[ "$progress" == "100.00% done" ]]; then
                echo -e "\033[0;32mFile: $(basename "$f") \033[1;30m[COMPLETED]\033[0m"
                ((count_healthy++))
            else
                # Clean log parsing for active runs
                local clean_tail=$(tail -n 15 "$f" | sed 's/\r//g; s/[^[:print:]\t]//g')
                local current_pat=$(echo "$clean_tail" | grep "pattern" | tail -n 1 | grep -oE "0x[0-9a-fA-F]+" | head -n 1)
                [[ -z "$current_pat" ]] && current_pat="0x00"
                
                echo -e "\033[0;32mFile: $(basename "$f") \033[1;35m[Pat: $current_pat]\033[0m ${age_color}(Log: ${age}s)\033[0m"
                timeout 3s bash "/root/scripts/drive-testing/disk_burnin/check_badblocks.sh" "$f"
                [[ $age -gt $stale_threshold ]] && ((count_warn++)) || ((count_healthy++))
            fi
            echo -e "\033[0;90m-------------------------------------------------------\033[0m"
        done <<< "$bb_logs"
    fi

    # --- PHASE 05: READ (dd) ---
    echo -e "\n\033[1;33m[PHASE 05: PARALLEL READ VERIFY (dd)]\033[0m"
    local dd_logs=$(find "$base_dir" -maxdepth 2 -type f -path "*drive_burnin_${target_date}*/*dd_read_*.log" 2>/dev/null | sort)
    
    if [[ -z "$dd_logs" ]]; then
        echo -e " \033[0;90mPhase 05 has not started yet.\033[0m"
    else
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            local wwn=$(basename "$f" | sed 's/dd_read_//;s/.log//')
            local dev_name=$(ls -l /dev/disk/by-id/"$wwn" 2>/dev/null | awk '{print $NF}' | sed 's/..\/..\///')
            local last_line=$(tail -n 1 "$f")
            
            # Live Pulse for DD
            local pulse="IDLE"
            if [[ -n "$dev_name" ]]; then
                local s1=$(grep " $dev_name " /proc/diskstats | awk '{print $6}')
                sleep 0.1
                local s2=$(grep " $dev_name " /proc/diskstats | awk '{print $6}')
                local diff=$(( (s2 - s1) * 512 / 1048576 )) 
                [[ $diff -gt 0 ]] && pulse="${diff}MB/s" || pulse="WAITING"
            fi

            echo -e "\033[0;36mDrive: $wwn\033[0m"
            echo -e " ├─ Activity: \033[1;32m$pulse\033[0m"
            echo -e " └─ Progress: \033[0;90m$last_line\033[0m"
            echo -e "\033[0;90m-------------------------------------------------------\033[0m"
        done <<< "$dd_logs"
    fi
    
    # --- SUMMARY ---
    echo -e "\n\033[1;37m=======================================================\033[0m"
    echo -e "📈 SUMMARY: $total_drives Drives | Healthy: $count_healthy | Stale: $count_warn"
    
    local errors=$(dmesg | grep -Ei "sd[a-z]|ata[0-9]|scsi|sector" | grep -Ei "exception|error|failed|status: { DRDY ERR }" | tail -n 3)
    [[ -n "$errors" ]] && echo -e "Alerts: \033[1;31mHARDWARE ERRORS DETECTED\033[0m" || echo -e "Alerts: \033[0;32mNone (Hardware Clean)\033[0m"
    echo -e "\033[1;37m=======================================================\033[0m\n"
}

#############################################################################
# Function to watch burn-in status in real-time (auto-refresh every 30s)
#############################################################################
function burn-watch() {
    local days_ago=${1:-0}
    
    # Check if bc is installed for calculations
    if ! command -v bc &> /dev/null; then
        echo "Error: 'bc' is not installed. Install with: apt install bc"
        return 1
    fi

    while true; do
        # Use clear to keep the dashboard static in the terminal
        clear
        
        # Call the status function we just optimized
        # It now handles the timeouts and speed checks internally
        burn-status "$days_ago"
        
        echo -e "\033[1;30mRefreshing in 30s... Press Ctrl+C to stop.\033[0m"
        
        # Last Update timestamp helps you know if the loop itself hung
        echo -e "\033[1;30mLast Loop Refresh: $(date '+%H:%M:%S')\033[0m"
        
        sleep 30
    done
}

#############################################################################
# Function to estimate remaining burn-in Phase 05 time based on dd read logs
#############################################################################
burn-time() {
    # Colors for that Proxmox aesthetic
    local YEL=$'\e[1;33m'
    local CYA=$'\e[0;36m'
    local GRE=$'\e[1;32m'
    local NC=$'\e[0m' # No Color

    local target_gb=${1:-4000}
    
    echo "${YEL}=======================================================${NC}"
    echo "🔍 ${YEL}DRIVE BURN-IN MONITOR:${NC} $(date +'%Y-%m-%d %H:%M')"
    echo "📊 ${YEL}Target Capacity:${NC} ${target_gb}GB"
    echo "${YEL}=======================================================${NC}"

    for f in /root/logs/drive_burnin_*/dd_read_wwn-*.log(N); do
        local wwn=${${f:t}#dd_read_}
        wwn=${wwn%.log}
        
        local dev=$(readlink -f /dev/disk/by-id/$wwn)
        if [[ -e $dev ]]; then
            local actual_sz=$(blockdev --getsize64 $dev | awk '{print $1/1073741824}')
            local raw_line=$(tail -1 "$f")
            
            # Header
            echo "Drive: ${YEL}${wwn}${NC}"
            
            # Raw Line
            echo " ├─ ${CYA}Activity:${NC} $raw_line"
            
            # Formatted Progress Line
            echo "$raw_line" | tr -d '(),' | awk -v sz="$actual_sz" -v gre="$GRE" -v cya="$CYA" -v nc="$NC" '{
                d=0; s=0;
                for(i=1; i<=NF; i++) {
                    if($i ~ /G[i]*B/) d=$(i-1);
                    if($i ~ /MB\/s/) s=$(i-1);
                }
                if(s > 0) {
                    pct=(d/sz)*100;
                    rem=((sz-d)*1024)/s/3600;
                    # Speed in Cyan, Progress/ETA in Green
                    printf " └─ %sProgress: %6.2f%% %s| %sSpeed: %s MB/s %s| %sETA: %.2f Hours%s\n", 
                        gre, pct, nc, cya, s, nc, gre, rem, nc;
                }
            }'
            echo "${YEL}-------------------------------------------------------${NC}"
        fi
    done
}

```



# Attach to a tmux session named "burnin" and run the drive tester script with the specified options.

```bash
tmux new -s burnin
sudo ./01_drive_tester_wrapper_auto.sh --resume-from PHASE_01_BASELINE
```

**Detach**

Press Ctrl + B, then release and press D.

**Reattach later:** 

```bash
tmux attach -t burnin
```


### 1. Get back into your session

To see the live progress of the script and the `badblocks` output:

```bash
tmux attach -t burnin

```

*Note: If you get an error saying the session doesn't exist, it might have finished or crashed—but with 4 healthy drives, it should be humming along.*

---

### 2. Check the "Grown Defect List"

SAS drives handle "bad sectors" differently than SATA drives. They use a **Primary Defect List (P-List)** from the factory and a **Grown Defect List (G-List)** for sectors that failed during use. You want the **Grown** list to be **0**.

Run this to see if the Long Test found anything:

```bash
for d in /dev/disk/by-id/wwn-0x5000c500a6be939f \
         /dev/disk/by-id/wwn-0x5000c500a6be84af \
         /dev/disk/by-id/wwn-0x5000c500a6be8113 \
         /dev/disk/by-id/wwn-0x5000c500a6bec9c7; do 
    echo "Drive: ${d##*/}"
    sudo smartctl -d scsi -l grown "$d" | grep "elements" || echo "No data"
    echo "-------------------"
done

ps aux | grep badblocks

# tail logs
tail -n 20 /root/logs/drive_burnin_2026-02-09_210901_pve-test/badblocks_*.log

# temp
for d in /dev/disk/by-id/wwn-0x5000c500a6be939f /dev/disk/by-id/wwn-0x5000c500a6be84af /dev/disk/by-id/wwn-0x5000c500a6be8113 /dev/disk/by-id/wwn-0x5000c500a6bec9c7; do
    echo -n "Drive ${d##*be}: "
    sudo smartctl -A "$d" | grep -i "Temperature" || echo "Busy..."
done

# Test for transport errors (cable end-to-end)
for d in /dev/disk/by-id/wwn-0x5000c500a6be939f \
         /dev/disk/by-id/wwn-0x5000c500a6be84af \
         /dev/disk/by-id/wwn-0x5000c500a6be8113 \
         /dev/disk/by-id/wwn-0x5000c500a6bec9c7; do 
    echo -n "Drive ${d##*be}: "
    sudo smartctl -A "$d" | grep -Ei "End-to-End|CRC_Error" || echo "No transport errors"
done



```

---

### 3. Quick Status Check (The "Health Overview")

If you don't want to dig through logs, this command will show you the result of the last test each drive performed:

```bash
for d in /dev/disk/by-id/wwn-0x5000c500a6be939f \
         /dev/disk/by-id/wwn-0x5000c500a6be84af \
         /dev/disk/by-id/wwn-0x5000c500a6be8113 \
         /dev/disk/by-id/wwn-0x5000c500a6bec9c7; do 
    echo "Drive: ${d##*/}"
    sudo smartctl -l selftest "$d" | grep -A 1 "Num  Test_Description" | tail -n 1
    echo "-------------------"
done

```

**What you want to see:** `Completed without error` or `Self-test routine in progress` (if it's still running).

---

### Summary of what to expect tomorrow morning:

* **The Script:** Should be in **Phase 04 (Badblocks)**.
* **The Graph:** If you run your plotter tomorrow, you'll see a flat line during the SMART test (HBA is idle), followed by a steep climb when the script hit Phase 04.
* **The Noise:** Your server fans might be a bit louder as those 4 drives will be drawing max power for the write tests!








#!/bin/bash

CONF_FILE="$HOME/scripts/drive-testing/disk_burnin/drive_slots.conf"
touch "$CONF_FILE"

# Array to store new mappings for the final summary
NEW_MAPPINGS=()

echo "-------------------------------------------------------"
echo " 🔍 SCANNING FOR UNMAPPED DRIVES"
echo "-------------------------------------------------------"

# Get WWNs, excluding partitions and the OS drive (sda)
ls -l /dev/disk/by-id/wwn-* | grep -v "part" | grep -v "sda" | while read -r line; do
    # Extract the filename part of the path correctly
    WWN=$(echo "$line" | awk '{print $9}' | xargs basename)
    
    if ! grep -q "$WWN" "$CONF_FILE"; then
        echo -e "\033[0;32m[NEW]\033[0m Found: $WWN"
        
        # Read input from terminal
        read -p "Assign Slot ID (e.g., Oc1-0) or [Enter] to skip: " SLOT_ID </dev/tty
        
        if [ ! -z "$SLOT_ID" ]; then
            echo "SLOTS[\"$WWN\"]=\"$SLOT_ID\"" >> "$CONF_FILE"
            echo "✅ Mapped $WWN to $SLOT_ID"
            # Add to our list for the end summary
            echo "$WWN" >> /tmp/new_drives_mapped.txt
        fi
        echo "-------------------------------------------------------"
    fi
done

echo "Scan complete. Your mappings are saved in drive_slots.conf"

# Check if we mapped anything new and print the wipe commands
if [ -f /tmp/new_drives_mapped.txt ]; then
    echo -e "\n\033[1;33m🛠️  POST-MAPPING STEPS\033[0m"
    echo "If these drives contain old ZFS/GPT metadata, run these commands before burn-in:"
    echo "-------------------------------------------------------"
    while read -r wwn_to_wipe; do
        echo "sudo wipefs -a /dev/disk/by-id/$wwn_to_wipe"
    done < /tmp/new_drives_mapped.txt
    echo "-------------------------------------------------------"
    # Clean up the temp file
    rm /tmp/new_drives_mapped.txt
fi
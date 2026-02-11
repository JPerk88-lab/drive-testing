############################
# Usage: python3 plot_burnin_temps.py /root/logs/drive_burnin_...
############################

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import sys
import os

log_dir = sys.argv[1] if len(sys.argv) > 1 else "."

def plot_temps(log_dir):
    print(f"📊 Generating Thermal Report for: {log_dir}")
    plt.figure(figsize=(15, 8)) 
    has_data = False
    max_hba = 0
    max_drive = 0
    
    def find_file(name):
        paths = [os.path.join(log_dir, name), os.path.join(log_dir, "raw_data", name)]
        for p in paths:
            if os.path.exists(p) and os.path.getsize(p) > 0:
                return p
        return None

    # 1. Plot HBA Temp
    hba_path = find_file("hba_temp.csv")
    if hba_path:
        try:
            df_hba = pd.read_csv(hba_path).dropna()
            df_hba['timestamp'] = pd.to_datetime(df_hba['timestamp'])
            df_hba = df_hba.sort_values('timestamp')
            
            # Record Max
            max_hba = df_hba['temp_c'].max()
            
            # Smoothing (15-point window)
            df_hba['sma'] = df_hba['temp_c'].rolling(window=15, min_periods=1).mean()
            
            plt.plot(df_hba['timestamp'], df_hba['sma'], label='HBA (LSI 9300-8i)', color='red', linewidth=2.5, zorder=5)
            has_data = True
        except Exception as e:
            print(f"Error HBA: {e}")

    # 2. Plot Drive Temps
    drive_path = find_file("drive_temps.csv")
    if drive_path:
        try:
            df_drives = pd.read_csv(drive_path).dropna()
            df_drives['timestamp'] = pd.to_datetime(df_drives['timestamp'])
            
            unique_wwns = df_drives['drive_wwn'].unique()
            max_drive = df_drives['temp_c'].max()

            for i, drive_id in enumerate(unique_wwns):
                subset = df_drives[df_drives['drive_wwn'] == drive_id].copy()
                subset = subset.sort_values('timestamp')
                
                # Smoothing
                subset['sma'] = subset['temp_c'].rolling(window=15, min_periods=1).mean()
                
                short_id = str(drive_id)[-8:] 
                plt.plot(subset['timestamp'], subset['sma'], label=f'Drive: {short_id}', alpha=0.7, linewidth=1.5)
                has_data = True
        except Exception as e:
            print(f"Error Drives: {e}")

    if not has_data:
        print("❌ CRITICAL: No data found.")
        return

    # --- Limit Lines ---
    plt.axhline(y=55, color='orange', linestyle='--', linewidth=1.2, label='Drive Limit (55°C)', alpha=0.8)
    plt.axhline(y=85, color='darkred', linestyle=':', linewidth=1.2, label='HBA Warning (85°C)', alpha=0.8)

    # --- Formatting ---
    plt.title(f"Burn-in Thermal Profile: {os.path.basename(log_dir)}", fontsize=14, pad=20)
    plt.xlabel("Time (HH:MM)", fontsize=10)
    plt.ylabel("Temperature (°C)", fontsize=10)
    
    ax = plt.gca()
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    plt.gcf().autofmt_xdate()

    # Legend outside
    plt.legend(loc='center left', bbox_to_anchor=(1, 0.5), fontsize=9)
    plt.grid(True, linestyle=':', alpha=0.5)
    
    # Text box with Peak Stats
    stats_text = f"PEAK TEMPS\nHBA: {max_hba}°C\nDrive: {max_drive}°C"
    plt.text(0.02, 0.95, stats_text, transform=ax.transAxes, fontsize=10,
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))

    plt.ylim(20, 95) # Broad enough to see HBA and ambient floor
    plt.tight_layout()
    
    output_path = os.path.join(log_dir, "thermal_report_final.png")
    plt.savefig(output_path, dpi=150)
    print(f"✅ Success! Report saved as: {output_path}")

if __name__ == "__main__":
    plot_temps(log_dir)
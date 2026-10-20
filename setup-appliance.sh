#!/bin/bash
set -e

echo "=== 1. Core System & Hostname ==="
echo "minecraft" > /etc/hostname
echo "127.0.0.1 minecraft" >> /etc/hosts

# NetworkManager global DNS fallback
mkdir -p /etc/NetworkManager/conf.d
cat << 'EOF' > /etc/NetworkManager/conf.d/dns.conf
[global-dns-domain-*]
servers=1.1.1.1,8.8.8.8
EOF

echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Cap log size to 100MB to protect storage
mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]\nSystemMaxUse=100M" > /etc/systemd/journald.conf.d/limit.conf

echo "=== 2. Packages, Drivers & Hardware Tools ==="
apt-get update
apt-get install -y --no-install-recommends \
    curl wget sudo git gnupg \
    openssh-server \
    default-jre-headless \
    avahi-daemon libnss-mdns \
    python3 python3-venv python3-pip python3-flask \
    zram-tools cpufrequtils systemd-timesyncd \
    network-manager wpasupplicant \
    firmware-iwlwifi firmware-realtek firmware-atheros firmware-brcm80211 \
    parted dosfstools e2fsprogs rsync \
    grub-efi-amd64-bin grub-pc-bin grub2-common \
    kbd console-setup fonts-terminus

mkdir -p /etc/default
cat << 'EOF' > /etc/default/console-setup
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="TerminusBold"
FONTSIZE="16x32"
EOF

# Universal ZRAM memory compression
echo "ALGO=lz4" > /etc/default/zramswap
echo "PERCENT=50" >> /etc/default/zramswap

systemctl enable avahi-daemon
systemctl enable ssh
systemctl enable zramswap
systemctl enable systemd-timesyncd
systemctl enable NetworkManager

# Stop login terminal from interfering with dashboard
systemctl mask getty@tty1.service

echo "=== 3. Power Management for Laptops ==="
sed -i 's/.*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sed -i 's/.*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "=== 4. Security & Access ==="
id -u user &>/dev/null || useradd -m -s /bin/bash -G sudo user
echo "user:admin" | chpasswd
echo "root:admin" | chpasswd
sed -i 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true

echo "=== 5. Playit Engine & Background Claim Service ==="
curl -SsL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/playit.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" > /etc/apt/sources.list.d/playit.list
apt-get update
apt-get install -y playit
usermod -aG playit user
systemctl enable playit

# Background script that runs setup once and keeps the handshake alive
cat << 'EOF' > /usr/local/bin/mcboot-playit-claim
#!/bin/bash
if [ -s /etc/playit/playit.toml ]; then
    exit 0
fi

mkdir -p /run/playit
exec playit setup > /run/playit/claim.txt 2>&1
EOF
chmod +x /usr/local/bin/mcboot-playit-claim

cat << 'EOF' > /etc/systemd/system/playit-claim.service
[Unit]
Description=McBoot Playit Claim Manager
After=network-online.target NetworkManager.service playit.service
Wants=network-online.target
ConditionPathExists=!/etc/playit/playit.toml

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/mcboot-playit-claim
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl enable playit-claim.service

echo "=== 6. Crafty Controller Setup ==="
mkdir -p /var/opt/minecraft/crafty
cd /var/opt/minecraft/crafty

git config --global http.version HTTP/1.1
git clone --depth 1 https://gitlab.com/crafty-controller/crafty-4.git crafty-4
cd crafty-4
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt

mkdir -p /var/opt/minecraft/crafty/crafty-4/app/config
cat << 'EOF' > /var/opt/minecraft/crafty/crafty-4/app/config/default.json
{
    "username": "admin",
    "password": "mcboot_2468"
}
EOF

chown -R user:user /var/opt/minecraft/crafty

cat << 'EOF' > /etc/systemd/system/crafty.service
[Unit]
Description=Crafty Controller 4
After=network.target

[Service]
Type=simple
User=user
Group=user
WorkingDirectory=/var/opt/minecraft/crafty/crafty-4
ExecStart=/var/opt/minecraft/crafty/crafty-4/.venv/bin/python3 /var/opt/minecraft/crafty/crafty-4/main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable crafty.service

echo "=== 7. Minimal Web Portal (Port 80) ==="
mkdir -p /opt/appliance-portal
cat << 'EOF' > /opt/appliance-portal/portal.py
import re
import os
from flask import Flask, render_template_string

app = Flask(__name__)

HTML_PAGE = """
<!DOCTYPE html>
<html>
<head>
    <title>McBoot</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #121824; color: #fff; text-align: center; padding: 40px 20px; }
        .card { background: #1e293b; max-width: 520px; margin: auto; padding: 30px; border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.4); }
        h1 { margin-bottom: 8px; color: #38bdf8; font-size: 32px; }
        p { color: #94a3b8; font-size: 15px; }
        .btn { display: block; padding: 14px 20px; margin: 15px 0; border-radius: 8px; text-decoration: none; font-weight: bold; font-size: 16px; }
        .btn-playit { background: #10b981; color: #fff; }
        .btn-crafty { background: #3b82f6; color: #fff; }
        .creds { background: #0f172a; padding: 15px; border-radius: 8px; margin-top: 25px; text-align: left; font-size: 14px; font-family: monospace; border-left: 4px solid #38bdf8; }
        .creds span { color: #38bdf8; font-weight: bold; }
        .notice { background: #1a2234; padding: 15px; border-radius: 8px; margin-top: 15px; text-align: left; font-size: 13px; color: #cbd5e1; border-left: 4px solid #eab308; }
        .notice strong { color: #facc15; }
        .warning-box { background: #3b1812; padding: 15px; border-radius: 8px; margin-top: 15px; text-align: left; font-size: 13px; color: #fca5a5; border-left: 4px solid #ef4444; }
        .warning-box strong { color: #f87171; }
        .warning-box code { color: #fff; font-family: monospace; white-space: nowrap; }
    </style>
</head>
<body>
    <div class="card">
        <h1>McBoot</h1>
        <p>Your self-hosted Minecraft server management dashboard is ready.</p>

        <a href="{{ playit_url }}" target="_blank" class="btn btn-playit">
            1. Link / View Playit Tunnel
        </a>

        <a href="#" id="crafty-link" class="btn btn-crafty">
            2. Open Crafty Dashboard
        </a>

        <div class="creds">
            <strong>Default Crafty Credentials:</strong><br>
            Username: <span>admin</span><br>
            Password: <span>mcboot_2468</span>
        </div>

        <div class="notice">
            <strong>Security Notice:</strong><br>
            When opening the Crafty Dashboard, your browser will display a privacy warning. This is expected because the server generates a local encryption certificate. Select <em>Advanced</em> and choose <em>Proceed</em> to continue.
        </div>

        {% if is_live %}
        <div class="warning-box">
            <strong>Temporary Mode (RAM):</strong><br>
            Server data and worlds will not be saved after powering off.<br>
            To install permanently to the internal drive, run: <code>sudo mcboot-install</code>
        </div>
        {% endif %}
    </div>
    <script>
        document.getElementById('crafty-link').href = 'https://' + window.location.hostname + ':8443';
    </script>
</body>
</html>
"""

def get_playit_url():
    if os.path.exists("/etc/playit/playit.toml") and os.path.getsize("/etc/playit/playit.toml") > 0:
        return "https://playit.gg/account"
    try:
        if os.path.exists("/run/playit/claim.txt"):
            with open("/run/playit/claim.txt", "r") as f:
                content = f.read()
            match = re.search(r"https://playit\.gg/claim/\S+", content)
            if match:
                return match.group(0).rstrip('.)",\'')
    except Exception:
        pass
    return "https://playit.gg/account"

@app.route("/")
def index():
    is_live = os.path.exists("/run/live")
    return render_template_string(HTML_PAGE, playit_url=get_playit_url(), is_live=is_live)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
EOF

cat << 'EOF' > /etc/systemd/system/appliance-portal.service
[Unit]
Description=McBoot Web Portal
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/appliance-portal
ExecStart=/usr/bin/python3 /opt/appliance-portal/portal.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable appliance-portal.service

echo "=== 8. Centered Monitor Dashboard with Auto Wi-Fi ==="
cat << 'EOF' > /usr/local/bin/mcboot-screen
#!/usr/bin/env python3
import os
import shutil
import subprocess
import time

if shutil.which("setfont"):
    subprocess.run(["setfont", "Lat15-TerminusBold32x16"], stderr=subprocess.DEVNULL)

def get_ip():
    try:
        ip = subprocess.getoutput("hostname -I").split()[0]
        return ip
    except Exception:
        return None

def wifi_wizard():
    print("\033[H\033[J", end="")
    print("=============================================================")
    print("                     McBoot Wi-Fi Setup")
    print("=============================================================")
    print("No network connection detected. Scanning for Wi-Fi...\n")
    try:
        subprocess.run(["nmcli", "device", "wifi", "rescan"], check=False)
        time.sleep(1)
        raw = subprocess.getoutput("nmcli -t -f SSID device wifi list | grep -v '^$'").strip().split('\n')
        ssids = list(dict.fromkeys([s for s in raw if s]))
        if not ssids:
            print("No wireless networks found. Plug in an Ethernet cable or wait...")
            time.sleep(5)
            return
        
        for idx, s in enumerate(ssids[:10], 1):
            print(f"  [{idx}] {s}")
        print("")
        choice = input(f"Select your Wi-Fi number [1-{len(ssids[:10])}]: ")
        selected = ssids[int(choice) - 1]
        password = input(f"Enter password for {selected}: ")
        print(f"\nConnecting to {selected}...")
        subprocess.run(["nmcli", "device", "wifi", "connect", selected, "password", password], check=True)
        print("Connected successfully.")
        time.sleep(2)
    except Exception:
        print("Connection failed. Retrying...")
        time.sleep(3)

def get_processor():
    try:
        with open("/proc/stat", "r") as f:
            fields = [float(x) for x in f.readline().strip().split()[1:5]]
        idle1, total1 = fields[3], sum(fields)
        time.sleep(0.5)
        with open("/proc/stat", "r") as f:
            fields = [float(x) for x in f.readline().strip().split()[1:5]]
        idle2, total2 = fields[3], sum(fields)
        usage = 100.0 * (1.0 - (idle2 - idle1) / (total2 - total1))
        return f"{int(usage)}%"
    except Exception:
        return "0%"

def get_ram():
    try:
        mem = {}
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split(":")
                mem[parts[0].strip()] = int(parts[1].split()[0])
        total = mem["MemTotal"] / 1024 / 1024
        avail = mem["MemAvailable"] / 1024 / 1024
        used = total - avail
        percent = int((used / total) * 100)
        return f"{percent}% (Used: {used:.1f} GB / Available: {avail:.1f} GB)"
    except Exception:
        return "0% (Used: 0 GB / Available: 0 GB)"

while not get_ip():
    wifi_wizard()

box_width = 61
while True:
    ip = get_ip() or "No connection"
    proc = get_processor()
    ram = get_ram()

    cols, rows = shutil.get_terminal_size((80, 24))
    pad_left = " " * max(0, (cols - box_width) // 2)
    pad_top = "\n" * max(0, (rows - 9) // 3)

    lines = [
        "=" * box_width,
        "McBoot".center(box_width),
        "=" * box_width,
        f" IP:         {ip}".ljust(box_width),
        f" Processor:  {proc}".ljust(box_width),
        f" RAM:        {ram}".ljust(box_width),
        "=" * box_width
    ]

    print("\033[H\033[J", end="")
    print(pad_top, end="")
    for l in lines:
        print(f"{pad_left}{l}")
    time.sleep(2)
EOF
chmod +x /usr/local/bin/mcboot-screen

cat << 'EOF' > /etc/systemd/system/mcboot-screen.service
[Unit]
Description=McBoot Monitor Dashboard
After=multi-user.target NetworkManager.service
Conflicts=getty@tty1.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/mcboot-screen
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable mcboot-screen.service

echo "=== 9. Hybrid BIOS/UEFI Disk Installer (mcboot-install) ==="
cat << 'EOF' > /usr/local/bin/mcboot-install
#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run as root (sudo mcboot-install)"
    exit 1
fi

echo "================================================="
echo "           McBoot Disk Installation"
echo "================================================="

BOOT_DEV=$(findmnt -n -o SOURCE /run/live/medium 2>/dev/null | sed -E 's/[0-9]+$//' | sed 's/p$//' || true)

DISKS=()
while read -r line; do
    DEV=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MODEL=$(echo "$line" | cut -d' ' -f3-)
    if [ "/dev/$DEV" != "$BOOT_DEV" ]; then
        DISKS+=("/dev/$DEV" "$SIZE - $MODEL")
    fi
done < <(lsblk -d -n -o NAME,SIZE,MODEL | grep -E "^(sd|vd|nvme|mmcblk)")

if [ ${#DISKS[@]} -eq 0 ]; then
    echo "No target drives detected."
    exit 1
fi

echo "Available target drives:"
COUNT=1
DRIVE_PATHS=()
for ((i=0; i<${#DISKS[@]}; i+=2)); do
    echo "  [$COUNT] ${DISKS[i]} (${DISKS[i+1]})"
    DRIVE_PATHS+=("${DISKS[i]}")
    ((COUNT++))
done

read -p "Select drive number to install to [1-${#DRIVE_PATHS[@]}]: " CHOICE
TARGET="${DRIVE_PATHS[$((CHOICE-1))]}"

if [ -z "$TARGET" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

echo "WARNING: ALL DATA ON $TARGET WILL BE PERMANENTLY ERASED."
read -p "Type 'YES' to confirm: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 0
fi

echo "Partitioning $TARGET with hybrid BIOS/UEFI support..."
wipefs -a "$TARGET"
parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart bios_grub 1MiB 2MiB
parted -s "$TARGET" set 1 bios_grub on
parted -s "$TARGET" mkpart ESP fat32 2MiB 514MiB
parted -s "$TARGET" set 2 esp on
parted -s "$TARGET" mkpart Root ext4 514MiB 100%

if [[ "$TARGET" =~ [0-9]$ ]]; then
    PART_BOOT="${TARGET}p2"
    PART_ROOT="${TARGET}p3"
else
    PART_BOOT="${TARGET}2"
    PART_ROOT="${TARGET}3"
fi

sleep 2
echo "Formatting filesystems..."
mkfs.vfat -F32 -n EFI "$PART_BOOT"
mkfs.ext4 -F -L MCBOOT "$PART_ROOT"

mkdir -p /mnt/target
mount "$PART_ROOT" /mnt/target
mkdir -p /mnt/target/boot/efi
mount "$PART_BOOT" /mnt/target/boot/efi

echo "Copying files to drive..."
rsync -aAX --info=progress2 \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    / /mnt/target/

ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")
BOOT_UUID=$(blkid -s UUID -o value "$PART_BOOT")

cat << FSTAB > /mnt/target/etc/fstab
UUID=$ROOT_UUID / ext4 errors=remount-ro 0 1
UUID=$BOOT_UUID /boot/efi vfat umask=0077 0 1
FSTAB

mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys
mount --bind /run /mnt/target/run

echo "Installing dual bootloaders (UEFI and Legacy BIOS)..."
chroot /mnt/target grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=McBoot --removable --recheck
chroot /mnt/target grub-install --target=i386-pc "$TARGET" --recheck
chroot /mnt/target update-initramfs -u
chroot /mnt/target update-grub

chroot /mnt/target systemctl mask getty@tty1.service 2>/dev/null || true

umount /mnt/target/boot/efi
umount -l /mnt/target/dev /mnt/target/proc /mnt/target/sys /mnt/target/run /mnt/target

echo "================================================="
echo "Installation complete. Remove USB stick and reboot."
echo "================================================="
EOF
chmod +x /usr/local/bin/mcboot-install

echo "=== McBoot Setup Complete ==="

# McBoot v1.0 - Self-Hosted Minecraft Appliance OS

Turn any spare computer or laptop into a dedicated, zero-configuration Minecraft server appliance.

McBoot is a lightweight, out-of-the-box Debian Bookworm appliance image configured with **Crafty Controller 4** and built-in **Playit.gg** tunneling.

---

## 🚀 Features

- **Zero Terminal Configuration**: Plug into Ethernet or connect via the built-in terminal Wi-Fi wizard.
- **Global Network & DNS Fallback**: Configured with Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`) DNS fallbacks to run seamlessly behind any home router.
- **Built-in Playit.gg Tunneling**: Play with friends anywhere without port forwarding. The automated claim service generates a linking URL directly on the monitor and web portal.
- **Crafty Controller 4**: Modern web-based Minecraft server manager (Java/Bedrock, modpacks, automated backups, and world management).
- **Web Portal (Port 80)**: Accessible from any device on your local network at `http://minecraft.local` or `http://<SERVER_IP>`.
- **Live USB Mode & Internal Drive Installer**: Run straight from a live USB stick or permanently install to the machine's internal disk using `sudo mcboot-install`.

---

## ⚡ Quick Start for Users

### 1. Download & Flash
1. Download **`mcboot-v1.0-amd64.iso`** from the [Releases](../../releases) tab.
2. (Optional) Verify download integrity:
   ```bash
   sha256sum -c mcboot-v1.0-amd64.iso.sha256
   ```
3. Flash the ISO to a USB flash drive (8 GB or larger) using [BalenaEtcher](https://etcher.balena.io/) or [Rufus](https://rufus.ie/).

### 2. Boot the Appliance
1. Insert the USB drive into your server PC and boot from USB.
2. Connect an Ethernet cable, or follow the on-screen Wi-Fi setup wizard on the monitor.
3. Once connected, the screen displays the server's local IP address and Playit claim link.

### 3. Manage Your Server
- **Web Portal**: Open a web browser on your phone or PC and visit:
  ```
  http://minecraft.local
  ```
  *(or visit `http://<SERVER_IP>` displayed on your screen)*
- **Crafty Dashboard**: Available at `https://minecraft.local:8443`
  - **Username**: `admin`
  - **Password**: `mcboot_2468`
  *(Accept the self-signed SSL certificate warning to proceed)*

---

## 🛠️ Building From Source

Requirements: Fedora, Debian, or any Linux system with **Podman** or **Docker**.

### Build Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/<your-username>/mineboot.git ~/mineboot
   cd ~/mineboot
   ```

2. Run the build container:
   ```bash
   sudo podman run --privileged -it --rm -v $(pwd):/workspace -w /workspace debian:bookworm-slim bash
   ```

3. Inside the container, run:
   ```bash
   apt-get update && apt-get install -y live-build
   rm -rf chroot .build
   lb config \
       --distribution bookworm \
       --architecture amd64 \
       --binary-images iso-hybrid \
       --archive-areas "main contrib non-free non-free-firmware" \
       --bootappend-live "boot=live components persistence consoleblank=0" \
       --system live
   cp setup-appliance.sh config/hooks/live/99-appliance.hook.chroot
   chmod +x config/hooks/live/99-appliance.hook.chroot
   lb build
   exit
   ```

4. Rename and generate checksums:
   ```bash
   sudo chown $USER:$USER *.iso
   mv live-image-amd64.hybrid.iso mcboot-v1.0-amd64.iso
   sha256sum mcboot-v1.0-amd64.iso > mcboot-v1.0-amd64.iso.sha256
   ```

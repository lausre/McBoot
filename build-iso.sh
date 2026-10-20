#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "=== Launching McBoot v1.0 Live Build in Podman ==="
sudo podman run --privileged --rm -it -v "$(pwd)":/workspace -w /workspace debian:bookworm-slim bash -c '
    set -e
    apt-get update && apt-get install -y live-build
    echo "=== Cleaning cache markers ==="
    rm -rf chroot .build
    echo "=== Running lb config ==="
    lb config \
        --distribution bookworm \
        --architecture amd64 \
        --binary-images iso-hybrid \
        --archive-areas "main contrib non-free non-free-firmware" \
        --bootappend-live "boot=live components persistence consoleblank=0" \
        --system live
    echo "=== Updating hook ==="
    mkdir -p config/hooks/live
    cp setup-appliance.sh config/hooks/live/99-appliance.hook.chroot
    chmod +x config/hooks/live/99-appliance.hook.chroot
    echo "=== Running lb build ==="
    lb build
'

echo "=== Fixing ownership and finalizing release ISO ==="
sudo chown $USER:$USER *.iso 2>/dev/null || true
if [ -f live-image-amd64.hybrid.iso ]; then
    mv -v live-image-amd64.hybrid.iso mcboot-v1.0-amd64.iso
    sha256sum mcboot-v1.0-amd64.iso > mcboot-v1.0-amd64.iso.sha256
    echo "=== McBoot v1.0 Build Complete ==="
    echo "Image:    $(pwd)/mcboot-v1.0-amd64.iso"
    echo "Checksum: $(cat mcboot-v1.0-amd64.iso.sha256)"
fi

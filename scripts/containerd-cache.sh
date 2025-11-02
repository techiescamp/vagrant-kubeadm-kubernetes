#!/bin/bash
#
# Configure CRI-O to use shared cache directory for persistent image storage

set -euxo pipefail

echo "Configuring CRI-O to use shared cache..."

# Create cache directory structure
sudo mkdir -p /var/lib/containerd-cache/containers
sudo mkdir -p /var/lib/containerd-cache/overlay
sudo mkdir -p /var/lib/containerd-cache/overlay-images

# Set proper permissions
sudo chown -R root:root /var/lib/containerd-cache
sudo chmod -R 755 /var/lib/containerd-cache

# Stop CRI-O
sudo systemctl stop crio || true

# Backup original CRI-O storage config if it exists
if [ -f /etc/containers/storage.conf ] && [ ! -f /etc/containers/storage.conf.bak ]; then
  sudo cp /etc/containers/storage.conf /etc/containers/storage.conf.bak
fi

# Create/update CRI-O storage configuration to use cache directory
sudo mkdir -p /etc/containers
sudo tee /etc/containers/storage.conf > /dev/null <<EOF
[storage]
  driver = "overlay"
  runroot = "/run/containers/storage"
  graphroot = "/var/lib/containerd-cache"

[storage.options]
  additionalimagestores = []

[storage.options.overlay]
  mountopt = "nodev"
  mount_program = "/usr/bin/fuse-overlayfs"
EOF

# Start CRI-O
sudo systemctl start crio
sudo systemctl enable crio

echo "CRI-O cache configuration completed!"
echo "Images will now be stored in: /var/lib/containerd-cache"

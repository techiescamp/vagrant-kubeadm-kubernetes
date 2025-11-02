#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

# Variable Declaration

# DNS Setting
if [ ! -d /etc/systemd/resolved.conf.d ]; then
	sudo mkdir /etc/systemd/resolved.conf.d/
fi
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF

sudo systemctl restart systemd-resolved

# disable swap
sudo swapoff -a

# keeps the swaf off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y


# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

## Load required kernel modules for storage (OpenEBS Mayastor, Longhorn)
echo "Loading required kernel modules..."
sudo apt-get install -y linux-modules-extra-$(uname -r) || true

# Load nvme-tcp module (required for OpenEBS Mayastor)
sudo modprobe nvme_tcp || true
echo 'nvme_tcp' | sudo tee -a /etc/modules-load.d/storage.conf

# Load iscsi_tcp module (required for Longhorn and OpenEBS)
sudo modprobe iscsi_tcp || true
echo 'iscsi_tcp' | sudo tee -a /etc/modules-load.d/storage.conf

echo "Kernel modules loaded successfully"

## Configure HugePages (required for OpenEBS Mayastor and Longhorn v2)
HOSTNAME=$(hostname)

# For Mayastor storage nodes
if [[ "${HOSTNAME}" == storage0* ]]; then
  # Read HugePages from settings.yaml (in GB)
  HUGEPAGES_GB=$(grep -A10 "mayastor:" /vagrant/settings.yaml | grep "hugepages_gb:" | awk '{print $2}' | tr -d '\r' | head -1)
  if [ -z "${HUGEPAGES_GB}" ]; then
    HUGEPAGES_GB="2"  # Default: 2GB
  fi

  # Convert GB to number of 2MB pages (1GB = 512 pages of 2MB)
  HUGEPAGES=$((HUGEPAGES_GB * 512))

  echo "Configuring HugePages for Mayastor storage node (${HUGEPAGES_GB}GB = ${HUGEPAGES} x 2MB pages)..."
  sudo sysctl -w vm.nr_hugepages=${HUGEPAGES}
  if ! grep -q "vm.nr_hugepages" /etc/sysctl.d/99-hugepages.conf 2>/dev/null; then
    echo "vm.nr_hugepages=${HUGEPAGES}" | sudo tee -a /etc/sysctl.d/99-hugepages.conf
  fi
  echo "HugePages configured successfully for storage node"

# For worker nodes (if Longhorn v2 is being used)
elif [[ "${HOSTNAME}" == node* ]]; then
  # Read HugePages from settings.yaml (in GB)
  HUGEPAGES_GB=$(grep -A15 "workers:" /vagrant/settings.yaml | grep "hugepages_gb:" | awk '{print $2}' | tr -d '\r' | head -1)

  # Default to 0 if not found or empty
  if [ -z "${HUGEPAGES_GB}" ]; then
    HUGEPAGES_GB="0"
  fi

  # Only configure if > 0 (disabled by default for workers)
  if [ "${HUGEPAGES_GB}" -gt 0 ] 2>/dev/null; then
    # Convert GB to number of 2MB pages
    HUGEPAGES=$((HUGEPAGES_GB * 512))

    echo "Configuring HugePages for worker node (${HUGEPAGES_GB}GB = ${HUGEPAGES} x 2MB pages)..."
    sudo sysctl -w vm.nr_hugepages=${HUGEPAGES}
    if ! grep -q "vm.nr_hugepages" /etc/sysctl.d/99-hugepages.conf 2>/dev/null; then
      echo "vm.nr_hugepages=${HUGEPAGES}" | sudo tee -a /etc/sysctl.d/99-hugepages.conf
    fi
    echo "HugePages configured successfully for worker node"
  else
    echo "Skipping HugePages configuration for worker node (hugepages_gb: ${HUGEPAGES_GB})"
  fi
else
  echo "Skipping HugePages configuration (not a storage or worker node)"
fi

## Install CRIO Runtime

sudo apt-get update -y
apt-get install -y software-properties-common curl apt-transport-https ca-certificates

curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

sudo systemctl daemon-reload
sudo systemctl enable crio --now
sudo systemctl start crio.service

echo "CRI runtime installed successfully"

# Configure CRI-O to use shared cache via disk image (workaround for VirtualBox symlink limitation)
echo "Configuring CRI-O persistent cache..."

# Create disk image file in shared folder if it doesn't exist
CACHE_IMG="/var/lib/containerd-cache/crio-cache.img"
CACHE_MOUNT="/var/lib/containers"

if [ ! -f "$CACHE_IMG" ]; then
  echo "Creating 50GB disk image for container cache..."
  sudo mkdir -p /var/lib/containerd-cache
  # Create a sparse file (doesn't actually use 50GB initially)
  sudo dd if=/dev/zero of="$CACHE_IMG" bs=1 count=0 seek=50G
  sudo mkfs.ext4 -F "$CACHE_IMG"
  echo "Disk image created successfully!"
else
  echo "Using existing cache disk image..."
fi

# Create mount point and mount the image
sudo mkdir -p "$CACHE_MOUNT"
sudo mount -o loop "$CACHE_IMG" "$CACHE_MOUNT" || true

# Make mount persistent across reboots
if ! grep -q "$CACHE_IMG" /etc/fstab; then
  echo "$CACHE_IMG $CACHE_MOUNT ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab
fi

# Stop CRI-O to update configuration
sudo systemctl stop crio

# Backup original CRI-O storage config if it exists
if [ -f /etc/containers/storage.conf ] && [ ! -f /etc/containers/storage.conf.bak ]; then
  sudo cp /etc/containers/storage.conf /etc/containers/storage.conf.bak
fi

# Create/update CRI-O storage configuration to use mounted cache
sudo mkdir -p /etc/containers
sudo tee /etc/containers/storage.conf > /dev/null <<EOF
[storage]
  driver = "overlay"
  runroot = "/run/containers/storage"
  graphroot = "$CACHE_MOUNT"

[storage.options]
  additionalimagestores = []

[storage.options.overlay]
  mountopt = "nodev"
EOF

# Restart CRI-O with new configuration
sudo systemctl start crio
echo "CRI-O cache configuration completed! Using $CACHE_MOUNT (backed by $CACHE_IMG)"

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION_SHORT/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION_SHORT/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list


sudo apt-get update -y
sudo apt-get install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
sudo apt-get update -y
sudo apt-get install -y jq

# Disable auto-update services
sudo apt-mark hold kubelet kubectl kubeadm cri-o


local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "eth1" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
${ENVIRONMENT}
EOF

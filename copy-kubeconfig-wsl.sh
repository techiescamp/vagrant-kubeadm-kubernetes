#!/bin/bash
#
# Bash script to copy Kubernetes config from Vagrant to WSL
# Run this from the project root directory in WSL

set -e

echo "========================================"
echo "Copying Kubernetes Config to WSL"
echo "========================================"
echo ""

# Get the current directory in Windows path format and convert to WSL path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/configs/config"

# Check if config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "ERROR: Config file not found at $CONFIG_PATH"
    echo "Make sure your Vagrant cluster is running and provisioned."
    exit 1
fi

# Create .kube directory in WSL home if it doesn't exist
KUBE_DIR="$HOME/.kube"
if [ ! -d "$KUBE_DIR" ]; then
    echo "Creating directory: $KUBE_DIR"
    mkdir -p "$KUBE_DIR"
fi

# Backup existing config if it exists
DEST_PATH="$KUBE_DIR/config"
if [ -f "$DEST_PATH" ]; then
    BACKUP_PATH="$KUBE_DIR/config.backup.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing config to: $BACKUP_PATH"
    cp "$DEST_PATH" "$BACKUP_PATH"
fi

# Copy the config file
echo "Copying config to: $DEST_PATH"
cp "$CONFIG_PATH" "$DEST_PATH"

# Update the server address in the config
echo "Updating server address in config..."
sed -i 's|https://[0-9.]*:6443|https://10.0.0.10:6443|g' "$DEST_PATH"

# Set proper permissions
chmod 600 "$DEST_PATH"

echo ""
echo "========================================"
echo "SUCCESS! Kubeconfig copied successfully"
echo "========================================"
echo ""
echo "Location: $DEST_PATH"
echo ""
echo "You can now use kubectl from WSL:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
echo "Make sure kubectl is installed in WSL. Install with:"
echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
echo ""

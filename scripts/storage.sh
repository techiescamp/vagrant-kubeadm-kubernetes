#!/bin/bash
#
# Deploys storage providers (Longhorn, OpenEBS Mayastor, OpenEBS LocalPV) based on settings.yaml configuration
# Supports multiple storage providers simultaneously for comparison and testing
#

set -euxo pipefail

echo "=== Storage Provider Installation Script ==="

# Helper function to extract nested YAML values
get_yaml_value() {
  local yaml_path="$1"
  local default_value="${2:-}"

  # Use grep with context to find nested values
  result=$(grep -A 10 "$yaml_path" /vagrant/settings.yaml 2>/dev/null | grep -E '^\s*(enabled|version|set_default|replicas):' | head -1 | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]' || echo "$default_value")
  echo "$result"
}

# Check which storage providers are enabled
LONGHORN_ENABLED=$(get_yaml_value "longhorn:" "false" | grep -E "enabled.*true" > /dev/null && echo "true" || echo "false")
if [ "$LONGHORN_ENABLED" = "false" ]; then
  LONGHORN_ENABLED=$(grep -A2 "longhorn:" /vagrant/settings.yaml | grep "enabled:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
fi

MAYASTOR_ENABLED=$(grep -A30 "networkpv:" /vagrant/settings.yaml | grep -A5 "mayastor:" | grep "enabled:" | head -1 | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')

# Check LocalPV configuration
LOCALPV_ENABLED=$(grep -A15 "localpv:" /vagrant/settings.yaml | grep "enabled:" | head -1 | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
LOCALPV_HOSTPATH=$(grep -A15 "localpv:" /vagrant/settings.yaml | grep "hostpath_enabled:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
LOCALPV_LVM=$(grep -A15 "localpv:" /vagrant/settings.yaml | grep "lvm_enabled:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
LOCALPV_ZFS=$(grep -A15 "localpv:" /vagrant/settings.yaml | grep "zfs_enabled:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')

# Default hostpath to true if localpv is enabled and hostpath_enabled is not explicitly set to false
if [ "${LOCALPV_ENABLED}" = "true" ] && [ -z "${LOCALPV_HOSTPATH}" ]; then
  LOCALPV_HOSTPATH="true"
fi

echo "Storage providers configuration:"
echo "  Longhorn: ${LONGHORN_ENABLED}"
echo "  OpenEBS Mayastor: ${MAYASTOR_ENABLED}"
echo "  OpenEBS LocalPV: ${LOCALPV_ENABLED}"
if [ "${LOCALPV_ENABLED}" = "true" ]; then
  echo "    - Hostpath: ${LOCALPV_HOSTPATH}"
  echo "    - LVM: ${LOCALPV_LVM}"
  echo "    - ZFS: ${LOCALPV_ZFS}"
fi

# Check if at least one provider is enabled
if [ "${LONGHORN_ENABLED}" != "true" ] && [ "${MAYASTOR_ENABLED}" != "true" ] && [ "${LOCALPV_ENABLED}" != "true" ]; then
  echo "No storage providers enabled. Skipping storage installation."
  exit 0
fi

# Wait for all nodes to be ready
echo "Waiting for all nodes to be ready..."
while sudo -i -u vagrant kubectl get nodes | grep -v "Ready" | grep -q "NotReady"; do
  echo "Waiting for nodes to be ready..."
  sleep 5
done

# Install Helm if not present (required for all providers)
if ! command -v helm &> /dev/null; then
  echo "Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

INSTALLED_PROVIDERS=()
DEFAULT_SC=""

#########################################
# Install Longhorn
#########################################
if [ "${LONGHORN_ENABLED}" = "true" ]; then
  echo ""
  echo "========================================="
  echo "Installing Longhorn..."
  echo "========================================="

  LONGHORN_VERSION=$(grep -A40 "longhorn:" /vagrant/settings.yaml | grep "version:" | head -1 | awk '{print $2}' | tr -d '\r')
  LONGHORN_DEFAULT=$(grep -A40 "longhorn:" /vagrant/settings.yaml | grep "set_default:" | head -1 | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  LONGHORN_ENGINE=$(grep -A40 "longhorn:" /vagrant/settings.yaml | grep "engine:" | head -1 | awk '{print $2}' | tr -d '\r')

  # Default to v1 if not specified
  if [ -z "${LONGHORN_ENGINE}" ]; then
    LONGHORN_ENGINE="v1"
  fi

  echo "Version: ${LONGHORN_VERSION}"
  echo "Engine: ${LONGHORN_ENGINE}"
  echo "Set as default: ${LONGHORN_DEFAULT}"

  # Install base prerequisites
  sudo apt-get update
  sudo apt-get install -y open-iscsi jq curl

  # V1 Engine prerequisites (iSCSI-based)
  if [ "${LONGHORN_ENGINE}" = "v1" ]; then
    echo "Installing Longhorn v1 engine prerequisites..."
    sudo systemctl enable iscsid
    sudo systemctl start iscsid

  # V2 Engine prerequisites (SPDK/NVMe-oF based)
  elif [ "${LONGHORN_ENGINE}" = "v2" ]; then
    echo "Installing Longhorn v2 engine prerequisites..."

    # Verify kernel version (REQUIRED: 5.19+, RECOMMENDED: 6.7+)
    KERNEL_VERSION=$(uname -r | cut -d'.' -f1-2)
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d'.' -f1)
    KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d'.' -f2)

    echo "Current kernel: $(uname -r)"

    # Check minimum requirement (5.19+)
    if [ "$KERNEL_MAJOR" -lt 5 ] || ([ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -lt 19 ]); then
      echo "ERROR: Longhorn v2 requires kernel 5.19 or higher"
      echo "Current kernel: $KERNEL_VERSION"
      echo ""
      echo "⚠️  CRITICAL: Kernel < 5.19 may cause unexpected reboots on volume IO errors"
      echo "Ubuntu 24.04 ships with kernel 6.8 (recommended)"
      exit 1
    fi

    # Warn if not on recommended version (6.7+)
    if [ "$KERNEL_MAJOR" -eq 5 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 7 ]); then
      echo "⚠️  WARNING: Kernel $KERNEL_VERSION is below recommended 6.7+"
      echo "   Risk of memory corruption during IO timeouts (SPDK issue #3116)"
      echo "   See: https://github.com/spdk/spdk/issues/3116#issuecomment-1890984674"
      echo "   Continuing anyway, but upgrade to 6.7+ recommended for production"
      echo ""
    else
      echo "✓ Kernel version check passed ($KERNEL_VERSION >= 6.7)"
    fi

    # Install NVMe-oF kernel modules and tools
    echo "Installing NVMe-oF support..."
    sudo apt-get install -y nvme-cli linux-modules-extra-$(uname -r)

    # Load NVMe-oF kernel modules
    sudo modprobe nvme-tcp || echo "WARNING: Failed to load nvme-tcp module"
    sudo modprobe nvmet || echo "WARNING: Failed to load nvmet module"
    sudo modprobe nvmet-tcp || echo "WARNING: Failed to load nvmet-tcp module"

    # Make modules load on boot
    echo "nvme-tcp" | sudo tee -a /etc/modules
    echo "nvmet" | sudo tee -a /etc/modules
    echo "nvmet-tcp" | sudo tee -a /etc/modules

    # Get HugePages and SPDK driver configuration from settings
    V2_SPDK_DRIVER=$(grep -A40 "longhorn:" /vagrant/settings.yaml | grep "v2_spdk_driver:" | awk '{print $2}' | tr -d '\r' | head -1)
    WORKER_HUGEPAGES_GB=$(grep -A15 "workers:" /vagrant/settings.yaml | grep "hugepages_gb:" | awk '{print $2}' | tr -d '\r' | head -1)

    # Default values
    if [ -z "${V2_SPDK_DRIVER}" ]; then
      V2_SPDK_DRIVER="uio_pci_generic"
    fi
    if [ -z "${WORKER_HUGEPAGES_GB}" ]; then
      WORKER_HUGEPAGES_GB="2"  # 2GB (REQUIRED minimum for Longhorn v2)
    fi

    # Convert GB to number of 2MB pages (1GB = 512 pages of 2MB)
    WORKER_HUGEPAGES=$((WORKER_HUGEPAGES_GB * 512))

    # Validate HugePages are configured (Longhorn v2 requires at least 2GB)
    if [ "${WORKER_HUGEPAGES_GB}" -lt 2 ]; then
      echo "❌ ERROR: Longhorn v2 requires at least 2GB HugePages"
      echo "   Current setting: workers.hugepages_gb: ${WORKER_HUGEPAGES_GB}"
      echo "   Please update settings.yaml -> nodes -> workers -> hugepages_gb to 2 or higher"
      exit 1
    fi

    echo "Configuring HugePages for SPDK..."
    echo "  HugePages: ${WORKER_HUGEPAGES_GB}GB (${WORKER_HUGEPAGES} x 2MB pages)"
    echo "  SPDK Driver: ${V2_SPDK_DRIVER}"
    echo ""
    echo "  Driver explanation:"
    if [ "${V2_SPDK_DRIVER}" = "uio_pci_generic" ]; then
      echo "  - Using uio_pci_generic: Simple, works in VirtualBox (RECOMMENDED for VMs/testing)"
    elif [ "${V2_SPDK_DRIVER}" = "vfio_pci" ]; then
      echo "  - Using vfio_pci: Secure, requires IOMMU (RECOMMENDED for bare-metal production)"
      echo "  - NOTE: May not work in VirtualBox without nested virtualization"
    else
      echo "  - Unknown driver: ${V2_SPDK_DRIVER}"
      echo "  - Supported: uio_pci_generic, vfio_pci"
    fi
    echo ""

    # Configure HugePages (2MB pages)
    sudo sysctl -w vm.nr_hugepages=${WORKER_HUGEPAGES}
    echo "vm.nr_hugepages=${WORKER_HUGEPAGES}" | sudo tee -a /etc/sysctl.conf

    # Mount hugetlbfs if not already mounted
    if ! mount | grep -q hugetlbfs; then
      sudo mkdir -p /dev/hugepages
      sudo mount -t hugetlbfs nodev /dev/hugepages
      echo "nodev /dev/hugepages hugetlbfs defaults 0 0" | sudo tee -a /etc/fstab
    fi

    # Load SPDK UIO driver
    if [ "${V2_SPDK_DRIVER}" = "uio_pci_generic" ]; then
      sudo modprobe uio_pci_generic
      echo "uio_pci_generic" | sudo tee -a /etc/modules
    elif [ "${V2_SPDK_DRIVER}" = "vfio-pci" ]; then
      sudo modprobe vfio-pci
      echo "vfio-pci" | sudo tee -a /etc/modules
    fi

    # Verify HugePages configuration
    CONFIGURED_HUGEPAGES=$(cat /proc/meminfo | grep HugePages_Total | awk '{print $2}')
    echo "✓ HugePages configured: ${CONFIGURED_HUGEPAGES} x 2MB = $((CONFIGURED_HUGEPAGES * 2))MB"

    # Enable iSCSI for fallback (v2 can use both NVMe-oF and iSCSI)
    sudo systemctl enable iscsid
    sudo systemctl start iscsid

  else
    echo "ERROR: Unknown Longhorn engine: ${LONGHORN_ENGINE}"
    echo "Supported engines: v1, v2"
    exit 1
  fi

  # Add Longhorn Helm repository
  echo "Adding Longhorn Helm repository..."
  sudo -i -u vagrant helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
  sudo -i -u vagrant helm repo update

  # Install Longhorn using Helm with engine-specific configuration
  echo "Installing Longhorn v${LONGHORN_VERSION} (${LONGHORN_ENGINE} engine) using Helm..."

  if [ "${LONGHORN_ENGINE}" = "v2" ]; then
    # Install with v2 engine enabled
    sudo -i -u vagrant helm install longhorn longhorn/longhorn \
      --namespace longhorn-system \
      --create-namespace \
      --version ${LONGHORN_VERSION} \
      --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
      --set defaultSettings.v2DataEngine=true \
      --set defaultSettings.guaranteedInstanceManagerCPU=10
  else
    # Install with v1 engine (default)
    sudo -i -u vagrant helm install longhorn longhorn/longhorn \
      --namespace longhorn-system \
      --create-namespace \
      --version ${LONGHORN_VERSION} \
      --set defaultSettings.defaultDataPath="/var/lib/longhorn"
  fi

  # Wait for Longhorn to be fully ready
  echo "Waiting for Longhorn to be fully ready (timeout: 20 minutes)..."
  TIMEOUT=1200
  ELAPSED=0
  INTERVAL=10

  # Wait for storage class to exist
  while [ $ELAPSED -lt $TIMEOUT ]; do
    if sudo -i -u vagrant kubectl get storageclass longhorn &>/dev/null; then
      echo "Longhorn storage class detected!"
      break
    fi
    echo "Waiting for Longhorn storage class to be created... (${ELAPSED}s / ${TIMEOUT}s)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: Timeout waiting for Longhorn storage class"
  else
    # Wait for all Longhorn pods to be ready
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
      TOTAL_PODS=$(sudo -i -u vagrant kubectl get pods -n longhorn-system --no-headers 2>/dev/null | wc -l)
      READY_PODS=$(sudo -i -u vagrant kubectl get pods -n longhorn-system --no-headers 2>/dev/null | grep -E "Running|Completed" | wc -l)

      if [ "$TOTAL_PODS" -gt 0 ] && [ "$TOTAL_PODS" -eq "$READY_PODS" ]; then
        echo "All Longhorn pods are ready! (${READY_PODS}/${TOTAL_PODS})"
        break
      fi

      echo "Waiting for Longhorn pods to be ready... (${READY_PODS}/${TOTAL_PODS} ready, ${ELAPSED}s / ${TIMEOUT}s)"
      sleep $INTERVAL
      ELAPSED=$((ELAPSED + INTERVAL))
    done

    # Additional wait for CSI driver components
    echo "Waiting for Longhorn CSI components..."
    sleep 30

    # Set Longhorn as default if configured
    if [ "${LONGHORN_DEFAULT}" = "true" ]; then
      echo "Setting Longhorn as default storage class..."
      sudo -i -u vagrant kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
      DEFAULT_SC="longhorn"
    fi

    INSTALLED_PROVIDERS+=("longhorn")
    echo "Longhorn installation completed successfully!"
    echo "Access Longhorn UI at: http://localhost:8001/api/v1/namespaces/longhorn-system/services/http:longhorn-frontend:80/proxy/"
  fi
fi

#########################################
# Install OpenEBS Mayastor
#########################################
if [ "${MAYASTOR_ENABLED}" = "true" ]; then
  echo ""
  echo "========================================="
  echo "Installing OpenEBS Mayastor..."
  echo "========================================="

  # Get OpenEBS Helm chart version (global, not under mayastor)
  OPENEBS_VERSION=$(grep -A2 "openebs:" /vagrant/settings.yaml | grep "version:" | head -1 | awk '{print $2}' | tr -d '\r')
  if [ -z "${OPENEBS_VERSION}" ]; then
    OPENEBS_VERSION="4.3.3"  # Default version
  fi

  MAYASTOR_DEFAULT=$(grep -A30 "networkpv:" /vagrant/settings.yaml | grep -A5 "mayastor:" | grep "set_default:" | head -1 | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  MAYASTOR_REPLICAS=$(grep -A30 "networkpv:" /vagrant/settings.yaml | grep -A5 "mayastor:" | grep "replicas:" | head -1 | awk '{print $2}' | tr -d '\r')

  echo "OpenEBS Helm Chart Version: ${OPENEBS_VERSION}"
  echo "Set as default: ${MAYASTOR_DEFAULT}"
  echo "Replicas: ${MAYASTOR_REPLICAS}"

  # Install prerequisites for Mayastor
  echo "Installing Mayastor prerequisites..."
  sudo apt-get update
  sudo apt-get install -y nvme-cli

  # Note: HugePages are configured in common.sh on storage nodes only

  # Add OpenEBS Helm repository
  echo "Adding OpenEBS Helm repository..."
  sudo -i -u vagrant helm repo add openebs https://openebs.github.io/openebs 2>/dev/null || true
  sudo -i -u vagrant helm repo update

  # Install OpenEBS with ONLY Mayastor enabled (disable all other engines)
  echo "Installing OpenEBS Helm chart v${OPENEBS_VERSION} with Mayastor enabled..."
  sudo -i -u vagrant helm install openebs --namespace openebs openebs/openebs \
    --create-namespace \
    --version ${OPENEBS_VERSION} \
    --set engines.local.lvm.enabled=false \
    --set engines.local.zfs.enabled=false \
    --set engines.local.hostpath.enabled=false \
    --set engines.replicated.mayastor.enabled=true \
    --set mayastor.csi.node.initContainers.enabled=true

  # Wait for OpenEBS pods to be ready
  echo "Waiting for OpenEBS to be fully ready (timeout: 20 minutes)..."
  TIMEOUT=1200
  ELAPSED=0
  INTERVAL=10

  while [ $ELAPSED -lt $TIMEOUT ]; do
    TOTAL_PODS=$(sudo -i -u vagrant kubectl get pods -n openebs --no-headers 2>/dev/null | wc -l)
    READY_PODS=$(sudo -i -u vagrant kubectl get pods -n openebs --no-headers 2>/dev/null | grep -E "Running|Completed" | wc -l)

    if [ "$TOTAL_PODS" -gt 0 ] && [ "$TOTAL_PODS" -eq "$READY_PODS" ]; then
      echo "All OpenEBS pods are ready! (${READY_PODS}/${TOTAL_PODS})"
      break
    fi

    echo "Waiting for OpenEBS pods to be ready... (${READY_PODS}/${TOTAL_PODS} ready, ${ELAPSED}s / ${TIMEOUT}s)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Timeout waiting for OpenEBS pods, but continuing anyway..."
    echo "You can check pod status with: kubectl get pods -n openebs"
  fi

  # Label storage nodes for Mayastor (required for io-engine DaemonSet scheduling)
  echo "Labeling storage nodes for Mayastor..."
  for node in $(sudo -i -u vagrant kubectl get nodes --no-headers | grep "storage0" | awk '{print $1}'); do
    echo "Labeling node: $node"
    sudo -i -u vagrant kubectl label node $node openebs.io/engine=mayastor --overwrite
    sudo -i -u vagrant kubectl label node $node openebs.io/data-plane=true --overwrite
  done

  # Apply taints to storage nodes if configured (dedicate nodes for storage only)
  MAYASTOR_TAINT=$(grep -A6 "^[[:space:]]*mayastor:" /vagrant/settings.yaml | grep "taint:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  if [ "${MAYASTOR_TAINT}" = "true" ]; then
    echo "Applying taints to dedicate storage nodes for Mayastor only..."
    for node in $(sudo -i -u vagrant kubectl get nodes --no-headers | grep "storage0" | awk '{print $1}'); do
      echo "Tainting node: $node with storage=mayastor:NoSchedule"
      sudo -i -u vagrant kubectl taint nodes $node storage=mayastor:NoSchedule --overwrite || true
    done
    echo "Storage nodes tainted successfully - only storage pods will be scheduled"
  else
    echo "Skipping taints - storage nodes will accept regular workloads"
  fi

  # Additional wait for all OpenEBS components to be fully ready
  echo "Waiting for all OpenEBS components to stabilize..."
  sleep 30

  # Wait for io-engine DaemonSet pods to start and be ready
  echo "Waiting for io-engine pods to start..."
  EXPECTED_IO_ENGINES=$(sudo -i -u vagrant kubectl get nodes -l openebs.io/engine=mayastor --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')

  for i in {1..60}; do
    RUNNING_IO_ENGINES=$(sudo -i -u vagrant kubectl get pods -n openebs -l app=io-engine --no-headers 2>/dev/null | grep "Running" | wc -l | tr -d '[:space:]')
    RUNNING_IO_ENGINES=${RUNNING_IO_ENGINES:-0}

    if [ "$RUNNING_IO_ENGINES" -ge "$EXPECTED_IO_ENGINES" ] && [ "$RUNNING_IO_ENGINES" -gt 0 ]; then
      echo "All io-engine pods are running! (${RUNNING_IO_ENGINES}/${EXPECTED_IO_ENGINES})"
      # Extra wait to ensure io-engine has registered with API
      echo "Waiting for io-engine to register with OpenEBS API..."
      sleep 15
      break
    fi

    echo "Waiting for io-engine pods... (${RUNNING_IO_ENGINES}/${EXPECTED_IO_ENGINES} running, attempt ${i}/60)"
    sleep 5
  done

  if [ "$RUNNING_IO_ENGINES" -eq 0 ]; then
    echo "ERROR: No io-engine pods are running!"
    echo "Check DaemonSet: kubectl get daemonset -n openebs"
    echo "Check pods: kubectl get pods -n openebs -l app=io-engine"
  else
    # Create disk pools on storage nodes using persistent device paths
    echo "Creating Mayastor disk pools on storage nodes..."

    # Create a DaemonSet that will run on each storage node to create its own DiskPool
    cat <<'EOF' | sudo -i -u vagrant kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: diskpool-creator
  namespace: openebs
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: diskpool-creator
rules:
- apiGroups: ["openebs.io"]
  resources: ["diskpools"]
  verbs: ["create", "get", "list", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: diskpool-creator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: diskpool-creator
subjects:
- kind: ServiceAccount
  name: diskpool-creator
  namespace: openebs
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: diskpool-creator
  namespace: openebs
spec:
  selector:
    matchLabels:
      app: diskpool-creator
  template:
    metadata:
      labels:
        app: diskpool-creator
    spec:
      serviceAccountName: diskpool-creator
      hostNetwork: true
      hostPID: true
      nodeSelector:
        openebs.io/engine: mayastor
      containers:
      - name: creator
        image: bitnami/kubectl:latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -e
            NODE_NAME=$(cat /etc/hostname)

            # Wait a bit for io-engine to be ready
            sleep 30

            # Check if DiskPool already exists
            if kubectl get diskpool pool-${NODE_NAME} -n openebs 2>/dev/null; then
              echo "DiskPool pool-${NODE_NAME} already exists, skipping creation"
              sleep infinity
              exit 0
            fi

            # Find the persistent device path for /dev/sdb
            DEVICE_ID=$(ls -la /host/dev/disk/by-id/ 2>/dev/null | grep 'ata-VBOX_HARDDISK' | grep 'sdb$' | awk '{print $9}' | head -1 || echo "")

            if [ -z "$DEVICE_ID" ]; then
              echo "ERROR: Could not find persistent device for /dev/sdb on ${NODE_NAME}"
              echo "Available devices:"
              ls -la /host/dev/disk/by-id/ | grep VBOX || true
              sleep infinity
              exit 1
            fi

            DEVICE_PATH="/dev/disk/by-id/${DEVICE_ID}"
            echo "Creating DiskPool for ${NODE_NAME} with device: ${DEVICE_PATH}"

            cat <<DISKPOOL | kubectl apply -f -
            apiVersion: openebs.io/v1beta3
            kind: DiskPool
            metadata:
              name: pool-${NODE_NAME}
              namespace: openebs
            spec:
              node: ${NODE_NAME}
              disks:
                - ${DEVICE_PATH}
            DISKPOOL

            echo "DiskPool created successfully for ${NODE_NAME}"

            # Keep pod running
            sleep infinity
        volumeMounts:
        - name: host-dev
          mountPath: /host/dev
          readOnly: true
        securityContext:
          privileged: true
      volumes:
      - name: host-dev
        hostPath:
          path: /dev
          type: Directory
      tolerations:
      - effect: NoSchedule
        operator: Exists
EOF

    echo "DaemonSet created to discover and create disk pools on each storage node"
    echo "Waiting for disk pools to be created (this may take 30-60 seconds)..."
    sleep 45

    # Wait for disk pools to be online
    echo "Waiting for disk pools to be online..."
    sleep 10
    for i in {1..60}; do
      TOTAL_POOLS=$(sudo -i -u vagrant kubectl get diskpool -n openebs --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
      ONLINE_POOLS=$(sudo -i -u vagrant kubectl get diskpool -n openebs --no-headers 2>/dev/null | grep "Online" | wc -l | tr -d '[:space:]')

      # Default to 0 if empty
      TOTAL_POOLS=${TOTAL_POOLS:-0}
      ONLINE_POOLS=${ONLINE_POOLS:-0}

      if [ "$TOTAL_POOLS" -gt 0 ] && [ "$TOTAL_POOLS" -eq "$ONLINE_POOLS" ]; then
        echo "All disk pools are online! (${ONLINE_POOLS}/${TOTAL_POOLS})"
        break
      fi

      echo "Waiting for disk pools to be online... (${ONLINE_POOLS}/${TOTAL_POOLS} online, attempt ${i}/60)"
      sleep 5
    done

    echo "Disk pool status:"
    sudo -i -u vagrant kubectl get diskpool -n openebs 2>/dev/null || echo "Unable to get disk pool status"

    # Verify CSI controller is ready
    echo "Verifying Mayastor CSI controller is ready..."
    for i in {1..30}; do
      if sudo -i -u vagrant kubectl get pods -n openebs -l app=csi-controller --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✓ Mayastor CSI controller is ready!"
        break
      fi
      if [ $i -eq 30 ]; then
        echo "⚠ WARNING: CSI controller not ready, but continuing..."
      else
        echo "  Waiting for CSI controller pod... ($i/30)"
        sleep 5
      fi
    done

    # Create storage class with configured replica count
    echo "Creating Mayastor storage class with ${MAYASTOR_REPLICAS} replicas..."

    SC_NAME="openebs-mayastor-${MAYASTOR_REPLICAS}replica"
    IS_DEFAULT="false"
    if [ "${MAYASTOR_DEFAULT}" = "true" ]; then
      IS_DEFAULT="true"
      DEFAULT_SC="${SC_NAME}"
    fi

    cat <<EOF | sudo -i -u vagrant kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${SC_NAME}
  annotations:
    storageclass.kubernetes.io/is-default-class: "${IS_DEFAULT}"
provisioner: io.openebs.csi-mayastor
parameters:
  repl: "${MAYASTOR_REPLICAS}"
  protocol: nvmf
  ioTimeout: "60"
volumeBindingMode: Immediate
allowVolumeExpansion: true
EOF

    echo "Created ${SC_NAME} storage class (default: ${IS_DEFAULT})"

    INSTALLED_PROVIDERS+=("openebs-mayastor")
    echo "OpenEBS Mayastor installation completed!"
  fi
fi

#########################################
# Install OpenEBS LocalPV
#########################################
if [ "${LOCALPV_ENABLED}" = "true" ]; then
  echo ""
  echo "========================================="
  echo "Installing OpenEBS LocalPV..."
  echo "========================================="

  # Check if we're installing alongside Mayastor
  if [ "${MAYASTOR_ENABLED}" = "true" ]; then
    echo "LocalPV will be added to existing OpenEBS installation"
  else
    echo "Installing OpenEBS with LocalPV engines only"

    # Add OpenEBS Helm repository
    echo "Adding OpenEBS Helm repository..."
    sudo -i -u vagrant helm repo add openebs https://openebs.github.io/openebs 2>/dev/null || true
    sudo -i -u vagrant helm repo update

    # Get OpenEBS version (use Mayastor version if available, otherwise default)
    OPENEBS_VERSION=$(grep -A2 "openebs:" /vagrant/settings.yaml | grep "version:" | head -1 | awk '{print $2}' | tr -d '\r')
    if [ -z "${OPENEBS_VERSION}" ]; then
      OPENEBS_VERSION="4.3.3"  # Default version
    fi

    # Install OpenEBS with LocalPV engines only (disable Mayastor)
    echo "Installing OpenEBS v${OPENEBS_VERSION} with LocalPV engines..."
    sudo -i -u vagrant helm install openebs --namespace openebs openebs/openebs \
      --create-namespace \
      --version ${OPENEBS_VERSION} \
      --set engines.local.lvm.enabled=${LOCALPV_LVM} \
      --set engines.local.zfs.enabled=${LOCALPV_ZFS} \
      --set engines.local.hostpath.enabled=${LOCALPV_HOSTPATH} \
      --set engines.replicated.mayastor.enabled=false

    # Wait for OpenEBS pods
    echo "Waiting for OpenEBS LocalPV to be ready..."
    sleep 30
  fi

  # Configure storage classes for enabled backends
  echo "Configuring LocalPV storage classes..."

  # Hostpath storage class
  if [ "${LOCALPV_HOSTPATH}" = "true" ]; then
    echo "Configuring Hostpath storage class..."

    HOSTPATH_DEFAULT=$(grep -A10 "localpv:" /vagrant/settings.yaml | grep "hostpath_set_default:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    HOSTPATH_IS_DEFAULT="false"
    if [ "${HOSTPATH_DEFAULT}" = "true" ]; then
      HOSTPATH_IS_DEFAULT="true"
      DEFAULT_SC="openebs-hostpath"
    fi

    # Hostpath storage class is created by OpenEBS automatically
    # Just set it as default if needed
    if [ "${HOSTPATH_IS_DEFAULT}" = "true" ]; then
      sudo -i -u vagrant kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
    fi

    INSTALLED_PROVIDERS+=("openebs-hostpath")
    echo "OpenEBS Hostpath configured (default: ${HOSTPATH_IS_DEFAULT})"
  fi

  # LVM storage class
  if [ "${LOCALPV_LVM}" = "true" ]; then
    echo "Configuring LVM storage class..."

    LVM_DEFAULT=$(grep -A10 "localpv:" /vagrant/settings.yaml | grep "lvm_set_default:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    LVM_IS_DEFAULT="false"
    if [ "${LVM_DEFAULT}" = "true" ]; then
      LVM_IS_DEFAULT="true"
      DEFAULT_SC="openebs-lvm"
    fi

    # LVM storage class is created by OpenEBS automatically
    # Just set it as default if needed
    if [ "${LVM_IS_DEFAULT}" = "true" ]; then
      sudo -i -u vagrant kubectl patch storageclass openebs-lvm -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
    fi

    INSTALLED_PROVIDERS+=("openebs-lvm")
    echo "OpenEBS LVM configured (default: ${LVM_IS_DEFAULT})"
  fi

  # ZFS storage class
  if [ "${LOCALPV_ZFS}" = "true" ]; then
    echo "Configuring ZFS storage class..."

    ZFS_DEFAULT=$(grep -A10 "localpv:" /vagrant/settings.yaml | grep "zfs_set_default:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    ZFS_IS_DEFAULT="false"
    if [ "${ZFS_DEFAULT}" = "true" ]; then
      ZFS_IS_DEFAULT="true"
      DEFAULT_SC="openebs-zfs"
    fi

    # ZFS storage class is created by OpenEBS automatically
    # Just set it as default if needed
    if [ "${ZFS_IS_DEFAULT}" = "true" ]; then
      sudo -i -u vagrant kubectl patch storageclass openebs-zfs -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
    fi

    INSTALLED_PROVIDERS+=("openebs-zfs")
    echo "OpenEBS ZFS configured (default: ${ZFS_IS_DEFAULT})"
  fi

  echo "OpenEBS LocalPV installation completed!"
fi

#########################################
# Summary
#########################################
echo ""
echo "========================================="
echo "Storage Installation Summary"
echo "========================================="
echo "Installed providers: ${INSTALLED_PROVIDERS[@]}"
if [ -n "$DEFAULT_SC" ]; then
  echo "Default storage class: ${DEFAULT_SC}"
fi

echo ""
echo "All storage classes:"
sudo -i -u vagrant kubectl get sc

# Run performance tests if enabled
RUN_STORAGE_TESTS=$(grep -A80 "storage:" /vagrant/settings.yaml | grep "run_tests:" | awk '{print $2}' | tr -d '\r' | tr '[:upper:]' '[:lower:]')

if [ "${RUN_STORAGE_TESTS}" = "true" ] && [ ${#INSTALLED_PROVIDERS[@]} -gt 0 ]; then
  echo ""
  echo "========================================="
  echo "Starting storage performance tests..."
  echo "========================================="

  # Run tests for each installed provider
  for provider in "${INSTALLED_PROVIDERS[@]}"; do
    echo "Testing ${provider}..."
    bash /vagrant/scripts/storage-test.sh "${provider}" || echo "WARNING: Tests failed for ${provider}"
  done

  echo "All storage tests completed! Reports are in /vagrant/storage-reports/"
else
  echo "Storage performance testing is disabled or no providers installed."
  echo "Set 'storage.run_tests: true' in settings.yaml to enable."
fi

echo ""
echo "Storage provider installation completed successfully!"

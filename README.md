## Setup Prerequisites

- A working Vagrant setup using Vagrant + VirtualBox

Here is the high level workflow.


<p align="center">
  <img src="https://github.com/user-attachments/assets/cc5594b5-42c2-4c56-be21-6441f849f537" width="65%" />
</p>

## Documentation

The setup is updated with 1.33.5 cluster version.

Refer to this link for documentation full: https://devopscube.com/kubernetes-cluster-vagrant/


## Prerequisites

1. Working Vagrant setup
2. **Minimum RAM Requirements:**
   - **Longhorn**: 8GB+ (1 control + 3 workers × 2GB)
   - **OpenEBS Mayastor**: 14GB+ (1 control at 4GB + 3 workers at 2GB + 3 storage nodes at 6GB)
   - **No Storage**: 8GB+ (1 control + 3 workers)

## For MAC/Linux Users

The latest version of Virtualbox for Mac/Linux can cause issues.

Create/edit the /etc/vbox/networks.conf file and add the following to avoid any network-related issues.
<pre>* 0.0.0.0/0 ::/0</pre>

or run below commands

```shell
sudo mkdir -p /etc/vbox/
echo "* 0.0.0.0/0 ::/0" | sudo tee -a /etc/vbox/networks.conf
```

So that the host only networks can be in any range, not just 192.168.56.0/21 as described here:
https://discuss.hashicorp.com/t/vagrant-2-2-18-osx-11-6-cannot-create-private-network/30984/23

## Bring Up the Cluster

To provision the cluster, execute the following commands.

```shell
git clone https://github.com/scriptcamp/vagrant-kubeadm-kubernetes.git
cd vagrant-kubeadm-kubernetes
vagrant up
```
## Set Kubeconfig file variable

```shell
cd vagrant-kubeadm-kubernetes
cd configs
export KUBECONFIG=$(pwd)/config
```

or you can copy the config file to .kube directory.

```shell
cp config ~/.kube/
```

## Install Kubernetes Dashboard

The dashboard is automatically installed by default, but it can be skipped by commenting out the dashboard version in _settings.yaml_ before running `vagrant up`.

If you skip the dashboard installation, you can deploy it later by enabling it in _settings.yaml_ and running the following:
```shell
vagrant ssh -c "/vagrant/scripts/dashboard.sh" controlplane
```

## Kubernetes Dashboard Access

To get the login token, copy it from _config/token_ or run the following command:
```shell
kubectl -n kubernetes-dashboard get secret/admin-user -o go-template="{{.data.token | base64decode}}"
```

Make the dashboard accessible:
```shell
kubectl proxy
```

Open the site in your browser:
```shell
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login
```

## Common Operations

### Cluster Management
```shell
vagrant halt                  # Shutdown cluster (preserves state)
vagrant up                    # Start/restart cluster
vagrant destroy -f            # Delete cluster completely (image cache persists)
vagrant status                # Check VM status
```

### Run Storage Performance Tests
```shell
# After vagrant up completes, run storage tests manually:
vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh longhorn"
vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh openebs-mayastor"

# Reports will be in: storage-reports/report-<provider>-<date>.pdf
# Each enabled provider gets its own separate report!
```

### Access Nodes
```shell
vagrant ssh controlplane      # SSH into control plane
vagrant ssh node01            # SSH into worker node 1
vagrant ssh node02            # SSH into worker node 2
vagrant ssh node03            # SSH into worker node 3
vagrant ssh storage01         # SSH into storage node 1 (if using OpenEBS)
vagrant ssh storage02         # SSH into storage node 2 (if using OpenEBS)
vagrant ssh storage03         # SSH into storage node 3 (if using OpenEBS)
```

## To destroy the cluster,

```shell
vagrant destroy -f
```

> **Note:** Container images are cached and will persist after destroy. See [Image Cache](#image-cache) section below.
# Network graph

```
                  +-------------------+
                  |    External       |
                  |  Network/Internet |
                  +-------------------+
                           |
                           |
             +-------------+--------------+
             |        Host Machine        |
             |     (Internet Connection)  |
             +-------------+--------------+
                           |
                           | NAT
             +-------------+--------------+
             |    K8s-NATNetwork          |
             |    192.168.99.0/24         |
             +-------------+--------------+
                           |
                           |
             +-------------+--------------+
             |     k8s-Switch (Internal)  |
             |       192.168.99.1/24      |
             +-------------+--------------+
                  |        |        |
                  |        |        |
          +-------+--+ +---+----+ +-+-------+
          |  Master  | | Worker | | Worker  |
          |   Node   | | Node 1 | | Node 2  |
          |192.168.99| |192.168.| |192.168. |
          |   .99    | | 99.81  | | 99.82   |
          +----------+ +--------+ +---------+
```

This network graph shows:

1. The host machine connected to the external network/internet.
2. The NAT network (K8s-NATNetwork) providing a bridge between the internal network and the external network.
3. The internal Hyper-V switch (k8s-Switch) connecting all the Kubernetes nodes.
4. The master node and two worker nodes, each with their specific IP addresses, all connected to the internal switch.

---

## Storage Providers

This setup supports **multiple storage providers simultaneously** for comparison and testing. Each enabled provider gets its own storage class and performance report.

### Available Storage Options

| Provider | Type | Performance | Use Case | Node Requirements |
|----------|------|-------------|----------|-------------------|
| **Longhorn v1** | Distributed Block Storage (iSCSI) | Good | Development, Testing, Production | Runs on worker nodes (no extra nodes) |
| **Longhorn v2** | High-Performance Block Storage (SPDK/NVMe-oF) | Excellent (2-3x v1) | Performance-critical Production | Worker nodes + 2GB HugePages, Kernel 5.19+ |
| **OpenEBS Mayastor** | Replicated NVMe-oF Storage | Excellent | High-Performance Production | 3 dedicated storage nodes + 2GB HugePages |
| **OpenEBS LocalPV** | Local Node Storage (Hostpath/LVM/ZFS) | Fastest (no network) | Databases with replication | Runs on worker nodes |
| **None** | No Storage | N/A | Testing without persistence | None |

### Key Features

- ✅ **Install Multiple Providers**: Run Longhorn and Mayastor side-by-side for comparison
- ✅ **Separate Test Reports**: Each provider gets its own PDF performance report
- ✅ **One Default Class**: Choose which storage class is default
- ✅ **Flexible Configuration**: Easy enable/disable per provider
- ✅ **Automatic Testing**: All enabled providers are tested automatically

### Configure Storage in settings.yaml

**Example 1: Both Longhorn and Mayastor (for comparison)**
```yaml
# Global VirtualBox optimizations (applies to ALL VMs)
virtualbox:
  optimize: true              # Enable I/O APIC and KVM paravirtualization
  storage_controller: "virtio-scsi"  # Use VirtIO-SCSI for Mayastor storage disks (20-30% faster)

nodes:
  workers:
    count: 3          # Regular compute nodes
    cpu: 2
    memory: 4096

  # Dedicated storage nodes (only created when mayastor is enabled)
  mayastor:
    count: 3          # Minimum 3 required for 3-way replication
    cpu: 4            # io-engine needs 2 full CPUs
    memory: 6144      # 2GB HugePages + ~3.5GB for pods
    disk: 50          # OS disk
    storage_disk: 100 # Mayastor pool disk (separate)
    taint: true       # Dedicate for storage only

software:
  storage:
    # Longhorn - Runs on worker nodes
    longhorn:
      enabled: true
      version: 1.10.0
      set_default: false  # Not default

    # OpenEBS - Network-replicated and local storage options
    openebs:
      version: 4.3.3    # OpenEBS Helm chart version (used by all components)

      networkpv:          # Network-replicated storage (HA across nodes)
        mayastor:
          enabled: true
          set_default: true   # Set as default storage class
          replicas: 3         # 3-way replication

      localpv:            # Optional local storage
        enabled: false

    # Run performance tests for all enabled providers
    run_tests: true
```

**Example 2: Longhorn Only (saves resources)**
```yaml
# Global VirtualBox optimizations
virtualbox:
  optimize: true

nodes:
  workers:
    count: 3
    cpu: 2
    memory: 4096

  # mayastor section can be omitted or set count: 0

software:
  storage:
    longhorn:
      enabled: true
      version: 1.10.0
      set_default: true

    openebs:
      version: 4.3.3
      networkpv:
        mayastor:
          enabled: false      # No storage nodes created

    run_tests: true
```

**Example 3: Mayastor Only**
```yaml
# Global VirtualBox optimizations
virtualbox:
  optimize: true
  storage_controller: "virtio-scsi"  # Faster storage for Mayastor

nodes:
  workers:
    count: 3
  mayastor:
    count: 3              # Storage nodes created

software:
  storage:
    longhorn:
      enabled: false      # Skip Longhorn

    openebs:
      version: 4.3.3      # OpenEBS Helm chart version
      networkpv:
        mayastor:
          enabled: true
          set_default: true
          replicas: 3

    run_tests: true
```

### Longhorn Storage (Recommended for Most Users)

**Features:**
- Web UI for management
- Backup and restore
- Snapshots and clones
- Lower resource requirements

**Access Longhorn UI:**
```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Open: http://localhost:8080
```

**Requirements:**
```yaml
workers:
  cpu: 1      # Minimum
  memory: 2048  # Minimum
```

---

### Longhorn (Distributed Block Storage with v1/v2 Engine Options)

**Features:**
- Cloud-native distributed block storage for Kubernetes
- Simple, lightweight, runs on worker nodes (no dedicated storage nodes needed)
- Choice between v1 (stable) or v2 (high-performance SPDK/NVMe-oF) engines
- Built-in backup, snapshot, and disaster recovery features
- User-friendly web UI for management

**Engine Comparison:**

| Feature | v1 Engine (iSCSI) | v2 Engine (SPDK/NVMe-oF) |
|---------|-------------------|--------------------------|
| **Status** | Production GA | Beta |
| **Protocol** | iSCSI | NVMe-over-TCP |
| **Performance** | Good | Excellent (2-3x IOPS) |
| **CPU Usage** | Normal | Lower (kernel bypass) |
| **Kernel Required** | Any | 5.19+ (6.7+ recommended) |
| **Memory** | Standard | 2GB HugePages per node |
| **Snapshots** | ✅ Supported | ❌ Not yet |
| **Backups** | ✅ Supported | ❌ Not yet |
| **Best For** | General production | Performance-critical workloads |

**v1 Engine Configuration (Production-Ready):**
```yaml
storage:
  longhorn:
    enabled: true
    version: 1.10.0
    set_default: true
    engine: v1              # Stable, production-ready

nodes:
  workers:
    count: 3
    cpu: 2
    memory: 4096
    hugepages_gb: 0         # Not needed for v1
```

**v2 Engine Configuration (High-Performance, Beta):**
```yaml
storage:
  longhorn:
    enabled: true
    version: 1.10.0
    set_default: true
    engine: v2              # High-performance SPDK/NVMe-oF
    v2_spdk_driver: uio_pci_generic  # or "vfio_pci" for production

nodes:
  workers:
    count: 3
    cpu: 2
    memory: 6144            # Need 2GB HugePages + 4GB for pods
    hugepages_gb: 2         # REQUIRED: 2GB HugePages for SPDK
```

**⚠️  Longhorn v2 Engine Requirements:**

**Kernel Version (CRITICAL):**
- **Minimum: 5.19** - Linux kernel 5.19 or later is **REQUIRED** for NVMe over TCP support
  - ❌ Kernel 5.15-5.18: May cause **unexpected reboots** on volume I/O errors
  - ⚠️ Kernel 5.19-6.6: Works but has known issues
- **Recommended: 6.7+** - Kernel 6.7 or later is **STRONGLY RECOMMENDED** for production
  - ✅ Prevents **memory corruption** during I/O timeouts
  - See [SPDK Issue #3116](https://github.com/spdk/spdk/issues/3116#issuecomment-1890984674) for details
- **Ubuntu 24.04**: Ships with kernel 6.8 ✅ Fully compatible and recommended

**System Requirements:**
- **HugePages**: 2GB per node - **REQUIRED**
  - Configure in `settings.yaml`: `nodes.workers.hugepages_gb: 2`
  - Uses 2MB page size (1GB = 512 pages)
  - Increase worker memory to 6144MB (2GB HugePages + 4GB for pods)
- **Kernel Modules**: `nvme-tcp`, `nvmet`, `nvmet-tcp`, `vfio_pci` or `uio_pci_generic`
- **Packages**: `nvme-cli`, `linux-modules-extra-$(uname -r)`
- **CPU**: x86_64 with SSE4.2 support (all modern CPUs)
- **Network**: Low-latency network for NVMe-oF traffic between replicas

**Performance Benefits (vs v1):**
- **2-3x better IOPS** using SPDK for zero-copy I/O
- **Lower CPU usage** through kernel bypass via SPDK
- **Better NVMe SSD performance** optimized for NVMe hardware
- **NVMe-oF protocol** for replica communication (vs iSCSI in v1)

**Limitations:**
- **Beta status** - Use with caution in production environments
- **No snapshot/backup support** yet (coming in future releases)
- **No live migration** from v1 to v2 (requires creating new volumes)
- **Cannot mix v1 and v2 volumes** in the same cluster
- **No kernel < 5.19 support** (will fail prerequisite check)

**Verify Longhorn v2 Prerequisites:**
```bash
# Check kernel version (need 5.19+, 6.7+ recommended)
vagrant ssh node01 -c "uname -r"

# Check HugePages configured
vagrant ssh node01 -c "cat /proc/meminfo | grep HugePages"

# Check NVMe-oF modules loaded
vagrant ssh node01 -c "lsmod | grep nvme"
```

**Verify Installation:**
```bash
# Check Longhorn pods
kubectl get pods -n longhorn-system

# Check storage class
kubectl get sc longhorn

# Check engine version
kubectl get settings.longhorn.io v2-data-engine -n longhorn-system -o yaml
```

**Access Longhorn UI:**
```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Open: http://localhost:8080
```

**SPDK Driver Selection (v2 Engine Only):**

Longhorn v2 uses SPDK (Storage Performance Development Kit) for user-space I/O, bypassing the kernel for better performance. You must choose a driver:

**Option 1: `uio_pci_generic` (Recommended for VirtualBox/Development)**
- ✅ Simple, works out-of-the-box in most Linux distributions
- ✅ No IOMMU required (works in VirtualBox without extra configuration)
- ✅ Easier setup for development and testing
- ⚠️ Less secure (allows any user-space process to access devices)
- **Use for:** VirtualBox VMs, development, testing, non-production environments

**Option 2: `vfio_pci` (Recommended for Bare-Metal Production)**
- ✅ More secure (uses IOMMU for device isolation)
- ✅ Prevents rogue processes from accessing hardware
- ✅ Better for production deployments
- ⚠️ Requires IOMMU support in BIOS/kernel (`intel_iommu=on` or `amd_iommu=on`)
- ⚠️ May not work in VirtualBox (needs nested virtualization + IOMMU passthrough)
- **Use for:** Bare-metal servers with IOMMU support, production environments

**TL;DR:** Use `uio_pci_generic` unless you have bare-metal servers with IOMMU support.

**Which Engine Should I Use?**

Choose **v1** if you:
- Need production stability and maturity
- Require snapshot/backup features
- Want maximum compatibility (any kernel version)
- Don't need extreme performance

Choose **v2** if you:
- Need 2-3x better IOPS than v1
- Have kernel 6.7+ (Ubuntu 24.04 recommended)
- Can allocate 2GB HugePages per node (set `workers.hugepages_gb: 2`)
- Don't need snapshots yet (coming soon)
- Are comfortable with beta software
- Using VirtualBox (set `v2_spdk_driver: uio_pci_generic`)

---

### OpenEBS Mayastor (High Performance with Dedicated Storage Nodes)

**Features:**
- NVMe-over-TCP protocol
- Replicated storage (3-way replication by default)
- High availability
- Production-grade performance
- **Dedicated storage nodes** separate from compute workloads

**Architecture:**
This setup uses **dedicated storage nodes** (best practice for production):

```
Cluster Layout:
├── 1 control plane (controlplane) - Manages cluster
├── 3 workers (node01-03) - Run application pods (2 CPU, 4GB RAM)
└── 3 storage nodes (storage01-03) - Run Mayastor io-engine (4 CPU, 6GB RAM)
```

**Benefits:**
- Clear separation between compute and storage
- Workers don't need high CPU/RAM (saves resources)
- Storage nodes can be optimized for I/O performance
- Optional taints prevent application pods from scheduling on storage nodes

**Requirements:**

**Storage Nodes (dedicated Mayastor nodes):**
```yaml
mayastor:
  count: 3          # Minimum 3 required for 3-way replication
  cpu: 4            # io-engine needs 2 full CPUs
  memory: 6144      # 2GB HugePages + ~3.5GB for pods (can use 4096 minimum)
  disk: 50          # OS disk
  storage_disk: 100 # Mayastor pool disk (separate from OS disk)
  taint: true       # Optional: Dedicate nodes for storage only
```

**Regular Worker Nodes (compute only):**
```yaml
workers:
  count: 3    # Or more for additional compute capacity
  cpu: 2      # No special requirements
  memory: 4096
```

**Memory Allocation Breakdown (Storage Nodes with 6GB RAM):**
- **Total RAM**: 6144 MB
- **HugePages**: 2048 MB (2GB, required by io-engine for SPDK)
- **Available for pods**: ~3500 MB
- **System overhead**: ~600 MB (OS, kernel)

**Why HugePages?**
Mayastor io-engine requires 2GB of HugePages for high-performance direct memory access (SPDK). This memory is pre-allocated and **only configured on storage nodes** (not regular workers). The taint ensures that only storage-related pods run on these nodes.

**Check HugePages allocation (storage nodes only):**
```bash
vagrant ssh storage01 -c "grep HugePages /proc/meminfo"
kubectl describe node storage01 | grep hugepages-2Mi
```

**Verify Installation:**
```bash
kubectl get pods -n openebs
kubectl get diskpool -n openebs  # Should show 3 pools (storage01-03), all "Online"
kubectl get sc | grep mayastor
kubectl get nodes --show-labels | grep storage  # See storage node labels and taints
```

**Disk Pool Configuration:**
- Automatically creates disk pools on **dedicated storage nodes only** (storage01, storage02, storage03)
- Additional VDI disks are created **only on storage nodes when OpenEBS is selected**
- Default storage disk size: 100GB (configurable via `nodes.mayastor.storage_disk`)
- Each storage node gets its own pool: `pool-storage01`, `pool-storage02`, `pool-storage03`
- Pools must be in "Online" state before volumes can be provisioned
- **Control plane and workers do NOT get additional disks** (only storage nodes)

**Node Taints (Optional but Recommended):**
When `nodes.mayastor.taint: true` is set:
- Storage nodes are tainted with `storage=mayastor:NoSchedule`
- Only storage pods (io-engine, CSI) can schedule on storage nodes
- Application pods run exclusively on regular worker nodes
- Set to `false` if you want storage nodes to accept application workloads

**Prerequisites (automatically configured):**
- **Storage nodes only:**
  - HugePages: 2GB (1024 pages)
  - Additional 100GB raw disk attached as `/dev/sdb`
  - Node labels: `openebs.io/engine=mayastor`
  - Optional taint: `storage=mayastor:NoSchedule`
- **All nodes:**
  - Kernel modules: `nvme_tcp`, `iscsi_tcp`
  - nvme-cli tools

### OpenEBS Mayastor Best Practices (Multi-Node Clusters)

#### Do You Need io-engine on All Nodes?

**Short Answer: No.** You only need io-engine on nodes that will host storage pools (data nodes).

#### Architecture Options

**Option 1: Dedicated Storage Nodes (Recommended for Production)**
```
10-node cluster example:
├── 1 control plane
├── 3 dedicated storage nodes (with io-engine + disk pools + 4 CPUs + 6GB RAM)
└── 6 compute-only nodes (no io-engine, 2 CPUs + 4GB RAM)
```

**Benefits:**
- Clear separation: storage vs compute workloads
- Easier capacity planning and troubleshooting
- Better performance (storage I/O doesn't compete with apps)
- Lower resource requirements (only storage nodes need 4 CPUs + HugePages)
- **Cost savings**: Compute nodes need less resources

**Option 2: Hyper-Converged (All Workers Run Storage)**
```
10-node cluster example:
├── 1 control plane
└── 9 workers (all with io-engine + disk pools + 4 CPUs + 6GB RAM)
```

**Benefits:**
- More total storage capacity
- Better data locality (apps can use storage on same node)
- More replica placement flexibility

**Drawbacks:**
- **Expensive**: All 9 nodes need 4 CPUs + 2GB HugePages
- Storage I/O competes with application workloads
- More complex resource management

#### Replication Strategy

**Default: 3-way replication**
- Data written to **3 different nodes** simultaneously
- **Minimum 3 storage nodes** required for 3-way replication
- More than 3 nodes provides **placement flexibility** and **high availability**, not more replicas per volume

**Example Storage Class:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mayastor-3-replica
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: io.openebs.csi-mayastor
parameters:
  repl: "3"           # 3-way replication across different nodes
  protocol: nvmf
  ioTimeout: "60"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

**Replica Placement Example:**
```
Volume with repl: 3
├── Replica 1 → node01 (pool-node01)
├── Replica 2 → node05 (pool-node05)
└── Replica 3 → node08 (pool-node08)
```

#### When to Use More Than 3 Storage Nodes

- **Capacity needs**: Need more total storage space than 3 nodes can provide
- **High availability**: Want to survive multiple node failures (with 5 nodes, can lose 2 and still maintain 3-way replication)
- **Performance**: Distribute I/O load across more nodes
- **Growth**: Planning to scale storage capacity over time

#### Resource Comparison (10-Node Cluster)

**Dedicated Storage Approach (3 storage + 7 compute):**
- Storage nodes: 3 × (4 CPU + 6GB RAM) = 12 CPUs, 18 GB RAM
- Compute nodes: 7 × (2 CPU + 4GB RAM) = 14 CPUs, 28 GB RAM
- **Total**: 26 CPUs, 46 GB RAM

**Hyper-Converged Approach (10 storage):**
- All workers: 10 × (4 CPU + 6GB RAM) = 40 CPUs, 60 GB RAM
- **Total**: 40 CPUs, 60 GB RAM

**Savings with dedicated approach: 14 CPUs, 14 GB RAM** 💰

#### Node Labeling for Dedicated Storage

```bash
# Label 3 nodes as dedicated storage nodes
kubectl label node node01 node-role.kubernetes.io/storage=true openebs.io/engine=mayastor
kubectl label node node02 node-role.kubernetes.io/storage=true openebs.io/engine=mayastor
kubectl label node node03 node-role.kubernetes.io/storage=true openebs.io/engine=mayastor

# Label remaining nodes as compute-only (io-engine won't schedule here)
kubectl label node node04 node-role.kubernetes.io/compute=true
kubectl label node node05 node-role.kubernetes.io/compute=true
# ... and so on for remaining nodes
```

#### Recommendations

| Cluster Size | Storage Nodes | Compute Nodes | Rationale |
|--------------|---------------|---------------|-----------|
| 3 workers    | 3 (all)       | 0             | Minimum for 3-way replication |
| 5-7 workers  | 3             | 2-4           | Balance cost and availability |
| 8-10 workers | 3-5           | 5-7           | Dedicated storage, most compute capacity |
| 10+ workers  | 5-7           | Remaining     | HA storage, maximum compute flexibility |

**Best Practice Summary:**
1. **Minimum 3 storage nodes** for production (3-way replication)
2. **Use dedicated storage nodes** for clusters > 5 nodes
3. **Label nodes clearly** to control io-engine placement
4. **Scale storage capacity** by adding more storage nodes, not increasing replicas
5. **Monitor disk pool capacity** across storage nodes

#### Performance Expectations in VirtualBox

⚠️ **Important:** Mayastor performance in VirtualBox/Vagrant environments is **NOT representative of bare-metal performance**.

**Why Mayastor May Perform Worse Than Longhorn in VMs:**

| Factor | Impact | Explanation |
|--------|--------|-------------|
| **Virtual Disk I/O** | 🔴 Critical | Mayastor is designed for fast NVMe SSDs. VirtualBox virtual disks (VDI) are much slower than real NVMe drives, bottlenecking Mayastor's capabilities |
| **Network Overhead** | 🔴 Critical | NVMe-over-TCP adds network latency. In VMs, network stack overhead is higher than bare metal, nullifying NVMe-oF benefits |
| **Memory Pressure** | 🔴 Critical | 4GB RAM for storage nodes causes swapping (needs 6GB). Swapping = extreme latency spikes and poor performance |
| **CPU Contention** | 🟡 Significant | io-engine needs 2 dedicated CPUs. VirtualBox can't guarantee CPU isolation, causing starvation during I/O |
| **Replication Overhead** | 🟡 Significant | 3-way replication = 3× write operations. In VMs with slow disks, this compounds latency issues |
| **SPDK in VMs** | 🟡 Moderate | Mayastor uses SPDK (userspace I/O) which has less benefit in VMs vs bare metal |

**Observed Symptoms:**
- Tests taking 122s instead of 60s (2× slower)
- Extreme latency spikes during mixed read/write workloads
- High memory usage (swapping to disk)
- Poor 70/30 mixed workload performance

**When Mayastor Performs WORSE than Longhorn:**

✅ **Longhorn advantages in VMs:**
- Designed for regular disks (not specifically NVMe)
- Lower memory footprint (no HugePages required)
- Simpler architecture = less VM overhead
- Better suited to VirtualBox's I/O characteristics

❌ **Mayastor disadvantages in VMs:**
- Designed for bare metal with fast NVMe drives
- High memory requirements (6GB minimum per storage node)
- NVMe-over-TCP overhead negates benefits with virtual networking
- SPDK advantages don't translate to virtual disks

**When to Use Each in VirtualBox:**

| Storage Provider | Best For | Performance |
|------------------|----------|-------------|
| **Longhorn** | Testing, learning, dev environments | Good (optimized for VMs) |
| **Mayastor** | Learning Mayastor architecture/features | Poor (bottlenecked by VMs) |
| **LocalPV** | Single-node testing, high-speed tests | Excellent (no replication overhead) |

**Production Bare-Metal Performance (Typical):**

On real hardware with NVMe SSDs:
- **Mayastor**: 100,000+ IOPS, sub-millisecond latency
- **Longhorn**: 10,000-30,000 IOPS, higher latency
- **Mayastor is 3-10× faster** on bare metal

**Recommendations:**

1. **For this Vagrant environment:**
   - Use **Longhorn** for replicated storage testing
   - Use **LocalPV** for single-node performance testing
   - Use **Mayastor** only to learn its features/architecture, not for performance testing

2. **To properly test Mayastor performance:**
   - Deploy on bare-metal Kubernetes
   - Use real NVMe SSDs (not HDDs or SATA SSDs)
   - Allocate 6GB+ RAM per storage node
   - Use 10GbE+ networking
   - Disable swap completely

3. **Improve Mayastor performance in VMs (slightly):**
   - Increase storage node RAM to 6GB (currently 4GB)
   - Reduce replicas to 2 or 1
   - Use host-only networking for faster VM-to-VM communication
   - Increase CPU cores to 6 per storage node

```yaml
# Better Mayastor config for VirtualBox (still not production-grade)
mayastor:
  count: 3
  cpu: 6            # Up from 4
  memory: 6144      # Up from 4096 (critical!)
  storage_disk: 100
  replicas: 2       # Down from 3 (reduce write amplification)
```

#### VirtualBox-Specific Optimizations (Included in This Project)

This Vagrant setup includes **automatic VirtualBox storage optimizations** to improve Mayastor performance in VMs.

**Available Optimizations:**

**1. VirtIO-SCSI Storage Controller** (20-30% faster than SATA)

VirtIO-SCSI is a paravirtualized storage controller that provides better performance than SATA:
- Lower CPU overhead
- Better queue depth support
- Native Linux virtio drivers (faster than SATA emulation)
- Reduced latency for I/O operations

```yaml
mayastor:
  storage_controller: "virtio-scsi"  # Options: "sata" (default) or "virtio-scsi"
```

**2. Advanced VirtualBox I/O Optimizations**

Enable additional optimizations for better interrupt handling and disk I/O:

```yaml
mayastor:
  vbox_optimize: true  # Enable all optimizations below
```

When enabled, applies:
- **I/O APIC**: Better interrupt handling for multi-core VMs
- **KVM Paravirtualization**: Faster virtualization interface
- **Non-rotational flag**: Marks disk as SSD for better Linux I/O scheduling
- **TRIM/Discard support**: Improves long-term performance

**3. Recommended Combined Configuration**

For best Mayastor performance in VirtualBox:

```yaml
nodes:
  mayastor:
    count: 3
    cpu: 6                              # Increased from 4
    memory: 6144                        # Increased from 4096 (critical!)
    storage_disk: 100
    storage_controller: "virtio-scsi"   # Use VirtIO-SCSI instead of SATA
    vbox_optimize: true                 # Enable all VBox optimizations

software:
  storage:
    openebs:
      networkpv:
        mayastor:
          enabled: true
          replicas: 2                     # Reduced from 3 for VM testing
```

**Expected Performance Improvements:**

| Optimization | IOPS Gain | Latency Reduction | Notes |
|--------------|-----------|-------------------|-------|
| VirtIO-SCSI | +20-30% | -15-25% | Best single optimization |
| I/O APIC + KVM | +10-15% | -10-15% | Helps with CPU overhead |
| 6GB RAM (vs 4GB) | +50-100% | -50-70% | Eliminates swapping (critical!) |
| Replicas 2 (vs 3) | +30-40% | -25-35% | Less write amplification |
| **Combined** | **+80-120%** | **-60-80%** | All optimizations together |

**Note:** Even with all optimizations, Mayastor in VMs will still be slower than bare metal. These improve performance within VM constraints.

**How to Apply:**

**Option 1: New Cluster (Recommended)**

1. Edit `settings.yaml` with the recommended configuration
2. Create/recreate cluster:
```bash
vagrant destroy -f
vagrant up
```

The Vagrantfile automatically detects and applies your settings.

**Option 2: Convert Existing VMs (Experimental)**

If you have an existing cluster and want to convert OS disks from SATA to VirtIO-SCSI without recreating:

⚠️ **WARNING: Experimental! VMs might fail to boot after conversion.**

```powershell
# Windows only - PowerShell script
.\convert-to-virtio.ps1

# Dry run to see what would be converted
.\convert-to-virtio.ps1 -DryRun
```

**What the script does:**
1. Finds all kubeadm-kubernetes VMs
2. Stops running VMs (tracks which ones were running)
3. Converts OS disk controller from SATA to VirtIO-SCSI
4. Restarts VMs that were running before conversion

**Notes:**
- Only converts OS disks (not storage disks)
- VMs must be created by Vagrant first
- Automatically restarts VMs that were running
- If VMs fail to boot, run: `vagrant destroy -f && vagrant up`

**Verify Optimizations:**

Check VirtIO-SCSI controller:
```bash
vagrant ssh storage01 -c "lsblk -d -o NAME,TRAN"
# Should show: sdb  (VirtIO-SCSI device)
```

Check I/O scheduler (should be mq-deadline for SSDs):
```bash
vagrant ssh storage01 -c "cat /sys/block/sdb/queue/scheduler"
# Should show: [mq-deadline] none
```

Check HugePages:
```bash
vagrant ssh storage01 -c "grep HugePages /proc/meminfo"
# HugePages_Total should be 1024 (2GB with 2MB pages)
```

💡 **Bottom Line:** In VirtualBox, **Longhorn will outperform Mayastor** due to VM limitations. This is expected and normal. Mayastor's true performance benefits only appear on bare-metal infrastructure with fast NVMe drives.

However, with these optimizations enabled, you can improve Mayastor performance by **80-120%** in VirtualBox, making it more usable for learning and testing purposes.

---

### OpenEBS LocalPV (Local Storage Engines)

OpenEBS LocalPV provides **three independent local storage backends** that run on worker nodes (no dedicated storage nodes needed). Each backend has different features and use cases.

#### Available LocalPV Backends

| Backend | Type | Performance | Data Protection | Use Case | Prerequisites |
|---------|------|-------------|-----------------|----------|---------------|
| **Hostpath** | Directory | Good | None | Development, Testing | None (always available) |
| **LVM** | LVM Volumes | Excellent (2-5x faster than ZFS) | Requires dm-integrity | Production (high performance) | lvm2 utils, dm-snapshot module |
| **ZFS** | ZFS Volumes | Good | Built-in checksumming (bitrot protection) | Production (data integrity) | ZFS kernel module + utils |

#### Configuration

**Enable All Three Backends:**
```yaml
software:
  storage:
    openebs:
      localpv:
        enabled: true                  # Master switch (required)

        hostpath_enabled: true         # Simple directory storage
        hostpath_set_default: false    # Not default

        lvm_enabled: true              # LVM-based storage
        lvm_set_default: false         # Not default

        zfs_enabled: true              # ZFS-based storage
        zfs_set_default: true          # Set as default (only one can be default)
```

**Hostpath Only (Default, No Dependencies):**
```yaml
software:
  storage:
    openebs:
      localpv:
        enabled: true                  # Master switch ON

        hostpath_enabled: true         # Enable hostpath
        hostpath_set_default: true     # Set as default

        lvm_enabled: false             # Disable LVM
        lvm_set_default: false

        zfs_enabled: false             # Disable ZFS
        zfs_set_default: false
```

**ZFS Only (Advanced Features):**
```yaml
software:
  storage:
    openebs:
      localpv:
        enabled: true                  # Master switch ON

        hostpath_enabled: false        # Disable hostpath
        hostpath_set_default: false

        lvm_enabled: false             # Disable LVM
        lvm_set_default: false

        zfs_enabled: true              # Enable ZFS only
        zfs_set_default: true          # Set as default
```

**Disable All LocalPV:**
```yaml
software:
  storage:
    openebs:
      localpv:
        enabled: false           # Master switch OFF (all backends disabled)
```

#### Important Notes

⚠️ **Master Switch:** When `localpv.enabled: false`, **ALL backends are disabled** regardless of individual settings.

✅ **Default Behavior:** When `localpv.enabled: true` and `hostpath_enabled` is not specified, hostpath defaults to `true` (no dependencies).

✅ **Multiple Backends:** You can enable multiple backends simultaneously. Each gets its own storage class.

#### Backend Comparison

**1. Hostpath (Simplest)**
- **How it works:** Uses local directories on each node (`/var/openebs/local`)
- **Pros:** No dependencies, easy setup, good for development
- **Cons:** No data protection, no snapshots, no compression
- **Storage Class:** `openebs-hostpath`
- **Best for:** Development, testing, non-critical workloads

**2. LVM (Fastest)**
- **How it works:** Uses LVM2 logical volumes on each node
- **Pros:**
  - **2-5x faster** than ZFS on write operations
  - Very stable and mature (kernel native since 2005)
  - Efficient thin provisioning
  - Supports snapshots and clones
- **Cons:**
  - Requires additional configuration for bitrot protection (dm-integrity)
  - Less feature-rich than ZFS
- **Prerequisites:**
  ```bash
  # Install lvm2 utils
  sudo apt-get install -y lvm2

  # Load dm-snapshot kernel module
  sudo modprobe dm-snapshot
  ```
- **Storage Class:** `openebs-lvm`
- **Best for:** High-performance production workloads

**3. ZFS (Most Features)**
- **How it works:** Uses ZFS filesystem on each node
- **Pros:**
  - **Built-in checksumming** prevents data corruption (bitrot)
  - Compression, deduplication, encryption built-in
  - Advanced snapshots, clones, thin provisioning
  - Self-healing with data scrubbing
- **Cons:**
  - Slower writes than LVM (higher CPU overhead)
  - Higher memory usage (ARC cache)
- **Prerequisites:**
  ```bash
  # Install ZFS utils and kernel module (Ubuntu 24.04)
  sudo apt-get install -y zfsutils-linux

  # Load ZFS kernel module
  sudo modprobe zfs
  ```
- **Storage Class:** `openebs-zfs`
- **Best for:** Production workloads requiring data integrity

#### Storage Classes Created

When enabled, each backend creates its own storage class:

```bash
kubectl get sc

NAME                          PROVISIONER
openebs-hostpath              openebs.io/local
openebs-lvm                   local.csi.openebs.io
openebs-zfs                   zfs.csi.openebs.io
```

#### Use Cases

**Development/Testing:**
```yaml
localpv:
  enabled: true
  hostpath_enabled: true    # Fast, simple, no setup
  lvm_enabled: false
  zfs_enabled: false
```

**Production (Performance Priority):**
```yaml
localpv:
  enabled: true
  hostpath_enabled: false
  lvm_enabled: true         # Fastest local storage
  zfs_enabled: false
```

**Production (Data Integrity Priority):**
```yaml
localpv:
  enabled: true
  hostpath_enabled: false
  lvm_enabled: false
  zfs_enabled: true         # Bitrot protection, compression
```

**Comparison Testing:**
```yaml
localpv:
  enabled: true
  hostpath_enabled: true
  lvm_enabled: true         # Enable all three
  zfs_enabled: true         # Compare performance with storage tests
```

#### Verify Installation

```bash
# Check LocalPV pods
kubectl get pods -n openebs | grep local

# Check storage classes
kubectl get sc | grep openebs

# Test volume creation (example with hostpath)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-localpv
spec:
  storageClassName: openebs-hostpath
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC status
kubectl get pvc test-localpv
```

#### Limitations

⚠️ **Not Replicated:** LocalPV volumes are **local to one node**. If the node fails, data is unavailable until the node recovers.

⚠️ **No Migration:** Pods using LocalPV volumes are tied to specific nodes (cannot move to other nodes).

⚠️ **Use Case:** Best for stateful workloads that handle replication at the application level (e.g., Cassandra, MongoDB, Kafka) or non-critical data.

💡 **For replicated storage**, use **Longhorn** or **OpenEBS Mayastor** instead.

---

### Disable Storage

To run cluster without persistent storage:

```yaml
storage:
  longhorn:
    enabled: false
  openebs:
    networkpv:
      mayastor:
        enabled: false
    localpv:
      enabled: false
```

---

## Understanding Volume Binding Modes

Kubernetes storage classes use different **volume binding modes** that control when a PersistentVolume (PV) is created and bound to a PersistentVolumeClaim (PVC). Understanding this is critical for using storage correctly.

### Volume Binding Modes

| Binding Mode | When PV is Created | Best For | Examples |
|--------------|-------------------|----------|----------|
| **Immediate** | As soon as PVC is created | Network storage accessible from any node | Longhorn, OpenEBS Mayastor, NFS, AWS EBS |
| **WaitForFirstConsumer** | When a Pod using the PVC is scheduled | Local storage tied to specific nodes | OpenEBS LocalPV (Hostpath, LVM, ZFS) |

### How WaitForFirstConsumer Works

Local storage providers (OpenEBS Hostpath, LVM, ZFS) use `WaitForFirstConsumer` binding mode because the storage is tied to a specific node.

**Why this matters:**
- PVC stays in `Pending` state until a Pod is created
- Kubernetes schedules the Pod first, then creates the PV on that specific node
- Prevents volume/pod affinity conflicts (volume on node01, pod on node02)

**Correct workflow:**

```bash
# Step 1: Create PVC (will stay Pending)
kubectl apply -f pvc.yaml

# Step 2: Create Pod immediately (don't wait for PVC!)
kubectl apply -f pod.yaml

# Step 3: Wait for Pod to be ready (PVC binds automatically)
kubectl wait --for=condition=Ready pod/my-pod --timeout=60s
```

**Example:**

```bash
# Create PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  storageClassName: openebs-hostpath
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Check status - will be Pending (THIS IS NORMAL!)
kubectl get pvc
# NAME          STATUS    VOLUME   CAPACITY   STORAGECLASS
# my-app-data   Pending   -        -          openebs-hostpath

# Create Pod using the PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-app-data
EOF

# Now both PVC and Pod are ready!
kubectl get pvc
# NAME          STATUS   VOLUME              CAPACITY   STORAGECLASS
# my-app-data   Bound    pvc-abc123...       5Gi        openebs-hostpath

kubectl get pod
# NAME     READY   STATUS    RESTARTS   AGE
# my-app   1/1     Running   0          10s
```

### Common Mistakes to Avoid

❌ **Wrong: Waiting for PVC before creating Pod**
```bash
kubectl apply -f pvc.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/my-pvc --timeout=60s  # HANGS FOREVER!
kubectl apply -f pod.yaml
```

✅ **Correct: Create PVC and Pod together**
```bash
kubectl apply -f pvc.yaml
kubectl apply -f pod.yaml  # Create immediately, don't wait!
kubectl wait --for=condition=Ready pod/my-pod --timeout=60s
```

### Storage Class Binding Modes Summary

Check the binding mode of your storage classes:

```bash
kubectl get sc -o custom-columns=NAME:.metadata.name,BINDING:.volumeBindingMode

# Output:
# NAME                 BINDING
# longhorn             Immediate                 ← Wait for PVC first
# openebs-mayastor     Immediate                 ← Wait for PVC first
# openebs-hostpath     WaitForFirstConsumer      ← Create Pod immediately!
# openebs-lvm          WaitForFirstConsumer      ← Create Pod immediately!
# openebs-zfs          WaitForFirstConsumer      ← Create Pod immediately!
```

**Key Takeaway:** For `WaitForFirstConsumer` storage classes, create the Pod immediately after the PVC - don't wait for the PVC to be bound first!

---

## Storage High Availability & Data Persistence - FAQ

Understanding how different storage types handle node failures is critical for production workloads. This section answers common questions about data persistence and high availability.

### Q: What happens when a node dies with local storage (OpenEBS LocalPV)?

**Scenario:** You have a Pod using `openebs-hostpath` storage running on `node01`. The node dies or is powered off.

**What happens:**

1. **Pod gets evicted** - Kubernetes detects the node is down and marks the Pod for rescheduling
2. **Kubernetes tries to reschedule** - Scheduler picks a healthy node (e.g., `node02`)
3. **Mount fails** - The PVC is still bound to storage on the dead `node01`
4. **Pod stays Pending** - Cannot start because the volume is inaccessible
5. **Data is stranded** - Data remains on `node01`'s disk until the node comes back

**Key Point:** OpenEBS LocalPV does **NOT** automatically migrate or replicate data to other nodes. The data is tied to that specific node's disk.

**Recovery options:**
- **If node comes back online:** Pod can reschedule back to `node01` and access the data
- **If node is permanently dead:** Data is lost (unless you have backups)
- **Manual recovery:** Restore from backups to a new PVC on a healthy node

### Q: What happens when a node dies with network storage (Longhorn/Mayastor)?

**Scenario:** You have a Pod using `longhorn` storage running on `node01`. The node dies.

**What happens:**

1. **Pod gets evicted** - Kubernetes detects the node is down
2. **Kubernetes reschedules Pod** - Picks a healthy node (e.g., `node02`)
3. **Storage system provides access** - Longhorn/Mayastor has replicas on other nodes
4. **Pod mounts successfully** - Attaches to a replica on `node02` or `node03`
5. **Pod continues running** - Data is fully accessible, no data loss

**Key Point:** Network storage systems replicate data across multiple nodes. If one node dies, replicas on other nodes keep your data safe and accessible.

**Why this works:**
- **3-way replication:** Data exists on 3 different nodes simultaneously
- **Automatic failover:** Storage system automatically switches to healthy replicas
- **Transparent to Pod:** Pod doesn't know or care which replica it's using

### Q: When should I use local storage vs network storage?

| Use Case | Recommended Storage | Why |
|----------|-------------------|-----|
| **Databases with built-in replication** (PostgreSQL HA, MongoDB ReplicaSet, Cassandra) | Local Storage (openebs-lvm, openebs-zfs) | Database handles HA; local storage gives better performance |
| **Single-instance databases** (MySQL, PostgreSQL single node) | Network Storage (Longhorn, Mayastor) | No app-level HA; storage must provide resilience |
| **Stateless applications** (Web servers, APIs) | No persistent storage needed | Use ephemeral storage or ConfigMaps |
| **Shared data** (multiple Pods reading same data) | Network Storage (Longhorn, Mayastor with ReadWriteMany) | Local storage is node-specific |
| **Development/Testing** | Local Storage (openebs-hostpath) | Fast, simple, data loss acceptable |
| **Production critical data** | Network Storage (Longhorn, Mayastor) | HA requirement; can't afford data loss |
| **High-performance workloads** (Analytics, ML training) | Local Storage (openebs-lvm with LVM thin provisioning) | Maximum I/O performance; use app-level replication |

### Q: Can I manually migrate local storage to another node?

**Short answer:** Yes, but it requires manual steps and downtime.

**Manual migration process:**

```bash
# 1. Stop the Pod
kubectl delete pod my-app

# 2. Create a backup of the data (from the original node)
# SSH to the node and tar/copy the data directory

# 3. Create a new PVC on the target node
# Requires node affinity to force scheduling on specific node

# 4. Restore data to new PVC
# Copy backup data to new volume

# 5. Start Pod with new PVC
kubectl apply -f pod-with-new-pvc.yaml
```

**Reality:** This is complex and error-prone. If you need migration, use network storage instead.

### Q: What about StatefulSets with local storage?

**StatefulSets with local storage work differently:**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-cluster
spec:
  replicas: 3
  serviceName: postgres
  template:
    spec:
      affinity:
        podAntiAffinity:  # Each replica on different node
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: postgres
            topologyKey: kubernetes.io/hostname
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      storageClassName: openebs-lvm
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

**How it works:**
- Each Pod gets its own PVC tied to a specific node
- If `postgres-cluster-0` runs on `node01`, it's pinned there
- If `node01` dies, `postgres-cluster-0` waits for that node to come back
- Meanwhile, `postgres-cluster-1` and `postgres-cluster-2` continue serving traffic

**Best for:**
- Distributed databases (Cassandra, CockroachDB, PostgreSQL with streaming replication)
- Applications with built-in clustering and data replication
- Workloads where each instance manages its own data copy

### Q: How do I choose replica count for network storage?

**Replica count affects availability and storage usage:**

| Replicas | Availability | Storage Overhead | Use Case |
|----------|--------------|------------------|----------|
| **1 replica** | No HA (single point of failure) | 1x (no overhead) | Development only |
| **2 replicas** | Survives 1 node failure | 2x (100% overhead) | Cost-sensitive production |
| **3 replicas** | Survives 2 node failures | 3x (200% overhead) | **Recommended for production** |
| **4+ replicas** | Survives 3+ node failures | 4x+ (300%+ overhead) | Mission-critical workloads |

**Example storage calculation:**

```yaml
# 3-way replication with 50GB PVC
# Actual disk usage = 50GB × 3 = 150GB total across cluster
```

**Recommendation:** Use 3 replicas for production. It's the sweet spot between availability and storage cost.

### Q: What happens to data when I run `vagrant destroy`?

**Local storage (openebs-hostpath, lvm, zfs):**
- ✅ **Data survives** if using LVM/ZFS (volume groups persist)
- ❌ **Data is deleted** if using Hostpath (stored in VM directories)
- Recovery requires recreating VMs with same volume groups

**Network storage (Longhorn, Mayastor):**
- ❌ **Data is deleted** - Storage pools are on the VM disks
- All replicas are destroyed when VMs are destroyed
- Always backup critical data before `vagrant destroy`

**Best practice:** Use `vagrant halt` (stop VMs) instead of `vagrant destroy` to preserve data during testing.

### Q: Can I mix local and network storage in the same cluster?

**Yes!** This is a powerful pattern:

```yaml
# High-performance tier: Local storage for databases with replication
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  storageClassName: openebs-lvm  # Local, fast
  accessModes: [ ReadWriteOnce ]
  resources:
    requests:
      storage: 50Gi

---
# Resilient tier: Network storage for application data
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-uploads
spec:
  storageClassName: longhorn  # Replicated, resilient
  accessModes: [ ReadWriteMany ]
  resources:
    requests:
      storage: 100Gi
```

**Strategy:**
- Use **local storage** for performance-critical workloads with app-level HA
- Use **network storage** for shared data and critical single-instance apps
- Enable multiple storage providers in `settings.yaml` to support both patterns

### Summary: Local vs Network Storage

| Aspect | Local Storage | Network Storage |
|--------|--------------|-----------------|
| **Performance** | ⚡ Fastest (direct disk access) | 🐌 Slower (network overhead) |
| **High Availability** | ❌ No (data tied to node) | ✅ Yes (replicated across nodes) |
| **Node failure handling** | ⚠️ Data stranded until node recovers | ✅ Automatic failover to replicas |
| **Storage overhead** | 1x (no replication) | 3x (typical 3-way replication) |
| **Best for** | Databases with built-in replication, dev/test | Single-instance apps, shared data, production |
| **Data migration** | ❌ Manual only | ✅ Automatic |
| **Use case** | PostgreSQL cluster, MongoDB ReplicaSet | WordPress, GitLab, critical data |

**Rule of thumb:**
- 🏎️ **Need speed? Have app-level HA?** → Use local storage
- 🛡️ **Need resilience? Single instance?** → Use network storage

---

## Storage Performance Testing

Automated performance testing using **fio (Flexible I/O Tester)** is available for all enabled storage providers. **Each provider gets its own separate test report** for easy comparison.

### Test Configuration

| Test | Block Size | Jobs | I/O Depth | Duration |
|------|------------|------|-----------|----------|
| Random Read IOPS | 4KB | 2 | 32 | 60s |
| Random Write IOPS | 4KB | 2 | 32 | 60s |
| Random R/W Mix (70/30) | 4KB | 2 | 32 | 60s |
| Sequential Read | 1MB | 1 | 16 | 60s |
| Sequential Write | 1MB | 1 | 16 | 60s |
| Random Read Latency | 4KB | 1 | 1 | 60s |
| Random Write Latency | 4KB | 1 | 1 | 60s |

**Duration per provider:** ~7-8 minutes
**Multiple providers:** Tests run sequentially for each enabled provider

### Enable/Disable Tests

In `settings.yaml`:
```yaml
storage:
  run_tests: true   # Automatically test ALL enabled providers after installation
  run_tests: false  # Skip all tests
```

**Automatic Testing:**
When `run_tests: true`, the installation script automatically tests **all enabled providers**:
- If both Longhorn and Mayastor are enabled, you get 2 separate reports
- Each test uses the correct storage class for that provider
- Total time: ~8 minutes per enabled provider

### Run Tests Manually

You can run storage tests at any time after `vagrant up` completes:

**Option 1: From your host machine (recommended)**
```bash
# Test Longhorn (works for both v1 and v2 engines)
vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh longhorn"

# Test OpenEBS Mayastor
vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh openebs-mayastor"

# Test both (if both enabled)
vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh longhorn"
vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh openebs-mayastor"
```

**Option 2: From inside the VM**
```bash
# SSH into the last worker node (node03)
vagrant ssh node03

# Run test for each enabled provider
sudo bash /vagrant/scripts/storage-test.sh longhorn
sudo bash /vagrant/scripts/storage-test.sh openebs-mayastor

# Exit the SSH session
exit
```

**Note:** The script must run on **node03** (the last worker) or **storage03** (if using Mayastor only) because these nodes have kubectl access configured by the provisioning scripts.

### Test Reports

Reports are automatically generated in `storage-reports/` directory with timestamps:

**Example with both providers enabled:**
```
storage-reports/
├── report-longhorn-20251031_143045.pdf          # Longhorn PDF report
├── report-longhorn-20251031_143045.txt          # Longhorn text version
├── report-openebs-mayastor-20251031_150022.pdf  # Mayastor PDF report
└── report-openebs-mayastor-20251031_150022.txt  # Mayastor text version
```

**Report Contents:**
- Storage provider and storage class name
- System information (node, kernel, memory)
- All 7 test results with IOPS, bandwidth, and latency
- Formatted tables and charts (PDF version)

**Comparing Performance:**
Open both PDF reports side-by-side to compare:
- Random read/write IOPS
- Sequential throughput
- Latency differences
- Resource usage during tests

---

## Image Cache (Persistent Across vagrant destroy)

To avoid re-downloading container images on every `vagrant up`, this setup uses a persistent image cache.

### How It Works

Container images are stored in disk image files (`.img`) located in the `containerd-cache/` directory:

```
containerd-cache/
├── controlplane/
│   └── crio-cache.img    # 50GB disk image
├── node01/
│   └── crio-cache.img
├── node02/
│   └── crio-cache.img
└── node03/
    └── crio-cache.img
```

### Benefits

✅ **Persistent Storage:** Images survive `vagrant destroy`
✅ **Faster Rebuilds:** No re-downloading images (saves time & bandwidth)
✅ **Separate Per Node:** Each node has its own cache
✅ **Automatic:** No configuration needed

### Cache Size

- Initial size: Minimal (sparse files)
- Grows as needed up to 50GB per node
- Stores all Kubernetes images (Calico, CoreDNS, storage providers, etc.)

### Clear Cache

If you need to start fresh:

**Windows PowerShell:**
```powershell
Remove-Item -Recurse -Force .\containerd-cache\
```

**Linux/Mac:**
```bash
rm -rf containerd-cache/
```

Next `vagrant up` will rebuild the cache.

---

## Accessing Cluster from Host Machine

### Windows PowerShell

**One-time setup:**
```powershell
.\copy-kubeconfig.ps1
```

This copies the kubeconfig from the cluster to `%USERPROFILE%\.kube\config`.

**Use kubectl:**
```powershell
kubectl get nodes
kubectl get pods -A
kubectl get pvc
```

**Install kubectl (if needed):**
```powershell
choco install kubernetes-cli
# or download from: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
```

### WSL (Windows Subsystem for Linux)

**One-time setup:**
```bash
bash copy-kubeconfig-wsl.sh
```

This copies the kubeconfig to `~/.kube/config` in WSL.

**Use kubectl:**
```bash
kubectl get nodes
kubectl get pods -A
```

**Install kubectl (if needed):**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

---

## Resource Requirements

### Minimum Configuration (Longhorn)

```yaml
nodes:
  control:
    cpu: 2
    memory: 4096
    disk: 50          # Disk size in GB
  workers:
    count: 2
    cpu: 1
    memory: 2048
    disk: 50          # Disk size in GB
```

**Host Requirements:**
- CPU: 4 cores
- RAM: 8 GB
- Disk: 150 GB (50GB base + 2x50GB for workers)

### Recommended Configuration (OpenEBS Mayastor with Dedicated Storage Nodes)

```yaml
nodes:
  control:
    cpu: 2
    memory: 4096
    disk: 50          # OS disk size in GB
  workers:
    count: 3          # Regular compute nodes
    cpu: 2            # No special requirements
    memory: 4096
    disk: 50          # OS disk size in GB
  mayastor:           # Dedicated storage nodes (only created when storage_provider: openebs)
    count: 3          # Minimum 3 for 3-way replication
    cpu: 4            # REQUIRED - io-engine needs 2 full CPUs
    memory: 6144      # RECOMMENDED - 2GB HugePages + 3.5GB for pods
    # memory: 4096    # MINIMUM - works but tight (2GB HugePages + 1.7GB for pods)
    disk: 50          # OS disk size in GB
    storage_disk: 100 # Mayastor pool disk (separate from OS disk)
    taint: true       # Dedicate nodes for storage only (recommended)

software:
  storage_provider: openebs
  openebs:
    version: 4.3.3
```

**Important Notes:**
- `nodes.*.disk`: OS disk size for all VMs
- `nodes.mayastor.storage_disk`: **Separate** 100GB disk for Mayastor pools (only on storage nodes)
- Storage nodes are **only created when** `storage_provider: openebs`
- With Longhorn or no storage provider, mayastor nodes are NOT created (saves resources)
- **Memory**: 2GB reserved for HugePages **on storage nodes only**, not on regular workers
- **Taints**: When `taint: true`, storage nodes only run storage pods (recommended)

**Host Requirements (with dedicated storage nodes):**
- CPU: 20 cores (2 control + 3×2 workers + 3×4 storage)
- RAM: 28 GB (4GB control + 3×4GB workers + 3×6GB storage)
- Disk:
  - OS disks: 350 GB (50GB control + 3×50GB workers + 3×50GB storage)
  - Mayastor pool disks: 300 GB (3×100GB storage nodes only)
  - **Total**: 650 GB

**Cost Comparison vs Hyper-Converged (3 storage + 3 workers):**
- **This setup (dedicated)**: 20 CPUs, 28 GB RAM
- **Hyper-converged (all 6 as storage)**: 26 CPUs, 40 GB RAM (6×4 CPU, 6×6GB RAM)
- **Savings**: 6 CPUs, 12 GB RAM by using dedicated storage nodes

---

## Troubleshooting

### Docker Hub Rate Limits

**Error:** "toomanyrequests: You have reached your pull rate limit"

**Solution:**
- Wait 6 hours (rate limit resets)
- Already using Calico 3.29.1 to avoid this

### OpenEBS Pods Not Starting

**Check nvme_tcp module (on storage nodes):**
```bash
vagrant ssh storage01
lsmod | grep nvme_tcp
```

**Should show:** `nvme_tcp`

If not loaded, it's automatically configured in `common.sh` but you can manually load:
```bash
sudo modprobe nvme_tcp
```

### OpenEBS Disk Pools Not Available

**Error:** "Not enough suitable pools available, 0/1"

**Check disk pool status:**
```bash
kubectl get diskpool -n openebs
```

**Expected output:**
```
NAME             NODE       STATE    POOL_STATUS   CAPACITY      USED   AVAILABLE
pool-storage01   storage01  Online   Online        107374182400  0      107374182400
pool-storage02   storage02  Online   Online        107374182400  0      107374182400
pool-storage03   storage03  Online   Online        107374182400  0      107374182400
```

**If pools show "Unknown" or "Error" state:**

1. Verify the additional disk exists (on storage nodes):
```bash
vagrant ssh storage01
lsblk
# Should show /dev/sdb with the configured disk size (100GB default)
```

2. Ensure the disk is raw (no partitions/filesystems):
```bash
sudo wipefs -a /dev/sdb  # Clear any existing filesystem signatures
```

3. Check Mayastor io-engine pod logs:
```bash
kubectl logs -n openebs -l app=io-engine --tail=50
```

4. Verify storage node labels and taints:
```bash
kubectl get nodes storage01 --show-labels
kubectl describe node storage01 | grep Taints
```

5. Recreate the disk pool if necessary:
```bash
kubectl delete diskpool pool-storage01 -n openebs
# Then recreate (note: use persistent device path):
DEVICE_ID=$(vagrant ssh storage01 -c "ls -la /dev/disk/by-id/ | grep 'ata-VBOX_HARDDISK' | grep 'sdb$' | awk '{print \$9}' | head -1")
cat <<EOF | kubectl apply -f -
apiVersion: openebs.io/v1beta3
kind: DiskPool
metadata:
  name: pool-storage01
  namespace: openebs
spec:
  node: storage01
  disks:
    - /dev/disk/by-id/${DEVICE_ID}
EOF
```

### Storage Class Not Default

**For Longhorn:**
```bash
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**For OpenEBS:**
```bash
kubectl patch storageclass openebs-mayastor -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Insufficient Storage for Volume Creation

**Error:** `longhorn.io/volume-scheduling-error: precheck new replica failed: insufficient storage`

**Or:** Longhorn/OpenEBS volumes stuck in "Pending" or "Attaching" state with storage errors

**Cause:** Storage providers with replication (Longhorn, OpenEBS Mayastor) need space for ALL replicas across nodes.

**Understanding Storage Requirements:**

For **Longhorn** (default 3 replicas):
- A 30GB PVC requires: **30GB × 3 replicas = 90GB total** across all worker nodes
- Example: 3 worker nodes with 50GB disks = ~23GB free per node after OS = **69GB total available**
- Result: ❌ **Not enough space** for 30GB PVC with 3 replicas

For **OpenEBS Mayastor** (configurable replicas):
- A 50GB PVC with 3 replicas requires: **50GB × 3 = 150GB total** across storage nodes
- Storage nodes use dedicated disks (default 100GB), so more space available

**Solutions:**

**Option 1: Reduce PVC size** (quickest, no rebuild needed)
```bash
# For storage tests, edit scripts/storage-test.sh
# Change: storage: 30Gi
# To:     storage: 20Gi  # 20GB × 3 = 60GB total (fits in 69GB available)
```

**Option 2: Reduce replica count** (good for testing/dev)

For **Longhorn**, create custom storage class:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-2replica
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"        # 2 replicas instead of 3
  staleReplicaTimeout: "30"
```

For **OpenEBS Mayastor**, edit `settings.yaml`:
```yaml
openebs:
  networkpv:
    mayastor:
      replicas: 2  # Change from 3 to 2
```

**Option 3: Increase worker node disk size** (requires rebuild)

Edit `settings.yaml`:
```yaml
nodes:
  workers:
    disk: 80  # Increase from 50GB to 80GB
```

Then recreate cluster:
```bash
vagrant destroy -f
vagrant up
```

**Check Available Disk Space:**

```bash
# Check disk usage on each worker node
for i in 1 2 3; do
  echo "=== node0$i ==="
  vagrant ssh node0$i -c "df -h / | grep -v Filesystem"
done

# Calculate total available space
# Multiply free space per node × number of nodes
# Compare to: PVC_SIZE × REPLICA_COUNT
```

**Recommended Disk Sizes:**

| Use Case | Worker Disk Size | Max PVC (3 replicas) | Max PVC (2 replicas) |
|----------|------------------|----------------------|----------------------|
| Testing/Dev | 50GB | 20GB | 30GB |
| Light Production | 80GB | 40GB | 60GB |
| Production | 100GB+ | 50GB+ | 75GB+ |

💡 **Tip:** For production, use dedicated storage nodes (OpenEBS Mayastor) with large dedicated disks instead of worker node storage.

### OpenEBS CSI Controller CrashLoopBackOff

**Error:** `openebs-csi-controller` pod shows `CrashLoopBackOff` status with errors like:
- `exec container process '/bin/tini': Input/output error`
- `Still connecting to unix:///var/lib/csi/sockets/pluginproxy/csi.sock`
- PVCs stuck in `Pending` state with message: `Waiting for a volume to be created by the external provisioner 'io.openebs.csi-mayastor'`

**Cause:** The CSI controller pod containers fail to start due to node I/O issues or corrupted container state.

**Solution:** Delete the CSI controller pod to force Kubernetes to recreate it:

```bash
# Check CSI controller status
kubectl get pods -n openebs | grep csi-controller

# Delete the crashed pod
kubectl delete pod -n openebs <openebs-csi-controller-pod-name>

# Wait for new pod to be created and verify it's running
kubectl get pods -n openebs | grep csi-controller
# Should show: openebs-csi-controller-xxxxx  6/6  Running
```

**Verify fix:**
```bash
# Create a test PVC to verify provisioning works
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-mayastor-volume
spec:
  storageClassName: openebs-mayastor
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC status (should become Bound)
kubectl get pvc test-mayastor-volume

# Clean up test PVC
kubectl delete pvc test-mayastor-volume
```

**Prevention:** This issue can occur when:
- Node experiences I/O pressure or disk errors
- Container runtime encounters issues during pod startup
- After node reboots or kubelet restarts

If the issue persists after recreating the pod, check the node's health:
```bash
# Check node status
kubectl get nodes

# Check node conditions
kubectl describe node <node-name> | grep -A 10 Conditions

# Check kubelet logs on the affected node
vagrant ssh <node-name> -c "sudo journalctl -u kubelet --no-pager -n 100"
```

### Check Container Runtime

```bash
vagrant ssh controlplane
sudo systemctl status crio
sudo crictl images
```

### Check Logs

**CRI-O Logs:**
```bash
vagrant ssh controlplane -c "sudo journalctl -u crio -f"
```

**Kubelet Logs:**
```bash
vagrant ssh controlplane -c "sudo journalctl -u kubelet -f"
```

**Pod Logs:**
```bash
kubectl logs -n <namespace> <pod-name>
kubectl describe pod -n <namespace> <pod-name>
```

---

## Common Commands

```bash
# Cluster Management
vagrant up                    # Start cluster
vagrant halt                  # Stop cluster (preserves state)
vagrant destroy -f            # Delete cluster (cache persists)
vagrant reload                # Restart VMs
vagrant status                # Check VM status

# Node Access
vagrant ssh controlplane      # SSH to control plane
vagrant ssh node01            # SSH to worker 1
vagrant ssh node02            # SSH to worker 2
vagrant ssh node03            # SSH to worker 3
vagrant ssh storage01         # SSH to storage node 1 (OpenEBS only)
vagrant ssh storage02         # SSH to storage node 2 (OpenEBS only)
vagrant ssh storage03         # SSH to storage node 3 (OpenEBS only)

# Kubernetes
kubectl get nodes             # List nodes
kubectl get pods -A           # List all pods
kubectl get pvc               # List persistent volume claims
kubectl get sc                # List storage classes
kubectl top nodes             # Node resource usage (requires metrics-server)
kubectl top pods -A           # Pod resource usage

# Storage
kubectl get pv                # List persistent volumes
kubectl get pvc -A            # List all PVCs
kubectl get diskpool -n openebs   # OpenEBS disk pools
kubectl get pods -n longhorn-system  # Longhorn pods

# Logs & Debug
kubectl describe node <node-name>
kubectl logs -n <namespace> <pod-name>
kubectl exec -it <pod-name> -- /bin/bash
```

---

## Version Information

| Component | Version | Compatibility |
|-----------|---------|---------------|
| Kubernetes | 1.33.5 | Current |
| Calico CNI | 3.29.1 | K8s 1.28+ |
| CRI-O Runtime | Latest | K8s 1.33 |
| Longhorn | 1.10.0 | K8s 1.21+ |
| OpenEBS Mayastor | 4.3.3 | K8s 1.23+ |
| Kubernetes Dashboard | 2.7.0 | K8s 1.21+ |
| Ubuntu | 24.04 LTS | Bento Box |

---

## Project Structure

```
vagrant-kubeadm-kubernetes/
├── Vagrantfile                 # VM definitions and provisioning
├── settings.yaml               # Cluster configuration
├── README.md                   # This documentation
├── .gitignore                  # Git ignore rules
├── .gitattributes              # Line ending configuration
│
├── scripts/
│   ├── common.sh               # Common setup for all nodes
│   ├── master.sh               # Control plane initialization
│   ├── node.sh                 # Worker node setup
│   ├── dashboard.sh            # Kubernetes Dashboard installation
│   ├── storage.sh              # Storage provider installation
│   └── storage-test.sh         # Performance testing with fio
│
├── copy-kubeconfig.ps1         # Windows PowerShell kubeconfig setup
├── copy-kubeconfig-wsl.sh      # WSL kubeconfig setup
│
├── configs/                    # Generated kubeconfig (gitignored)
│   ├── config                  # Kubernetes admin config
│   ├── join.sh                 # Worker join command
│   └── token                   # Dashboard token
│
├── containerd-cache/           # Container image cache (gitignored)
│   ├── controlplane/
│   ├── node01/
│   ├── node02/
│   └── node03/
│
└── storage-reports/            # Performance test reports (gitignored)
    ├── report-longhorn-*.pdf
    └── report-openebs-*.pdf
```

---

## Advanced Configuration

### Custom Network Configuration

Edit `settings.yaml`:

```yaml
network:
  control_ip: 10.0.0.10         # Control plane IP
  dns_servers:
    - 8.8.8.8                   # Google DNS
    - 1.1.1.1                   # Cloudflare DNS
  pod_cidr: 172.16.1.0/16       # Pod network CIDR
  service_cidr: 172.17.1.0/18   # Service network CIDR
```

### Scale Workers

Add or remove workers:

```yaml
workers:
  count: 5  # Increase/decrease
```

Then run:
```bash
vagrant up  # Creates new nodes only
```

### Custom Storage Test Parameters

Edit `scripts/storage-test.sh` to customize:
- Test duration (`--runtime=60`)
- Block sizes (`--bs=4k`, `--bs=1m`)
- I/O depth (`--iodepth=32`)
- Number of jobs (`--numjobs=2`)

---

## FAQ

**Q: Can I use both Longhorn and OpenEBS simultaneously?**
A: **Yes!** You can enable multiple storage providers for comparison. Set `enabled: true` for each provider in `software.storage` section. Each gets its own storage class and performance report.

**Q: Do images persist after `vagrant destroy`?**
A: Yes, images are cached in `containerd-cache/` folder.

**Q: Can I run this on a laptop?**
A: Yes, with minimum 8GB RAM for Longhorn setup.

**Q: How do I upgrade Kubernetes version?**
A: Update `kubernetes` version in `settings.yaml` and run `vagrant destroy -f && vagrant up`.

**Q: Why is OpenEBS Mayastor io-engine pod not starting?**
A: Ensure **storage nodes** (not workers) have **4 CPU minimum** (io-engine needs 2 full CPUs) and 4-6GB RAM. Check HugePages: `vagrant ssh storage01 -c "grep HugePages /proc/meminfo"` and kernel module: `lsmod | grep nvme_tcp`. Verify node labels: `kubectl get nodes storage01 --show-labels | grep mayastor`.

**Q: Why do my storage nodes only show ~1.7GB available memory when I configured 4GB?**
A: OpenEBS Mayastor reserves 2GB for HugePages (required for SPDK high-performance I/O) **on storage nodes only**, leaving ~1.7GB for pods and ~300MB for the OS. This is normal. For more available memory, increase storage nodes to 6GB RAM (2GB HugePages + ~3.5GB for pods). Regular worker nodes do NOT have HugePages configured and get full RAM.

**Q: What's the difference between worker nodes and storage nodes?**
A: **Worker nodes** run application pods (2 CPU, 4GB RAM, no HugePages, no extra disk). **Storage nodes** run Mayastor io-engine for storage (4 CPU, 6GB RAM, 2GB HugePages, 100GB extra disk). This separation follows production best practices and saves resources.

**Q: Storage tests didn't run automatically during `vagrant up`. How do I run them?**
A: Set `storage.run_tests: true` in settings.yaml, or run manually: `vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh longhorn"` and `vagrant ssh node03 -c "sudo bash /vagrant/scripts/storage-test.sh openebs-mayastor"`. Reports will be in `storage-reports/` directory.

**Q: Can I test different replica counts for Mayastor?**
A: Yes! Change `openebs.mayastor.replicas: 1/2/3` in settings.yaml, run `vagrant reload`, and re-run tests. Compare the PDF reports to see performance differences between 1-way, 2-way, and 3-way replication.

**Q: Which storage class is used as default?**
A: The provider with `set_default: true` in settings.yaml becomes the default storage class. Only one provider can be default at a time.

**Q: How do I access Longhorn UI?**
A: Run `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80` and open `http://localhost:8080`.

---

## Credits & References

- **Kubernetes**: https://kubernetes.io
- **Longhorn**: https://longhorn.io
- **OpenEBS**: https://openebs.io
- **Calico**: https://www.tigera.io/project-calico/
- **CRI-O**: https://cri-o.io
- **fio**: https://github.com/axboe/fio


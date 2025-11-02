#!/bin/bash
#
# Storage performance testing with fio after storage provider is ready

set -euxo pipefail

STORAGE_PROVIDER=$1

# Cleanup function to ensure resources are deleted even on error
cleanup() {
  echo ""
  echo "Cleaning up test resources..."
  sudo -i -u vagrant kubectl delete pod fio-test-${STORAGE_PROVIDER} --force --grace-period=0 2>/dev/null || true
  sudo -i -u vagrant kubectl delete pvc fio-test-pvc-${STORAGE_PROVIDER} 2>/dev/null || true
}

# Set trap to call cleanup on EXIT (success or failure)
trap cleanup EXIT

# Map provider name to storage class name
case "${STORAGE_PROVIDER}" in
  longhorn)
    STORAGE_CLASS="longhorn"
    ;;
  openebs-mayastor)
    # Get the mayastor storage class name (e.g., openebs-mayastor-3replica)
    STORAGE_CLASS=$(sudo -i -u vagrant kubectl get sc --no-headers | grep "openebs-mayastor.*replica" | awk '{print $1}' | head -1)
    if [ -z "$STORAGE_CLASS" ]; then
      echo "ERROR: Could not find OpenEBS Mayastor storage class"
      exit 1
    fi
    ;;
  openebs-hostpath)
    STORAGE_CLASS="openebs-hostpath"
    ;;
  openebs-lvm)
    STORAGE_CLASS="openebs-lvm"
    ;;
  openebs-zfs)
    STORAGE_CLASS="openebs-zfs"
    ;;
  openebs)
    # Legacy compatibility: try to find mayastor storage class
    STORAGE_CLASS=$(sudo -i -u vagrant kubectl get sc --no-headers | grep "openebs.*replica" | awk '{print $1}' | head -1)
    if [ -z "$STORAGE_CLASS" ]; then
      echo "ERROR: Could not find OpenEBS storage class"
      exit 1
    fi
    ;;
  *)
    echo "ERROR: Unknown storage provider: ${STORAGE_PROVIDER}"
    echo "Supported providers: longhorn, openebs-mayastor, openebs-hostpath, openebs-lvm, openebs-zfs"
    exit 1
    ;;
esac

echo "Testing storage provider: ${STORAGE_PROVIDER}"
echo "Using storage class: ${STORAGE_CLASS}"

REPORT_DIR="/vagrant/storage-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/report-${STORAGE_PROVIDER}-${TIMESTAMP}.txt"
REPORT_PDF="${REPORT_DIR}/report-${STORAGE_PROVIDER}-${TIMESTAMP}.pdf"

# Create reports directory
mkdir -p "${REPORT_DIR}"

echo "========================================" | tee "${REPORT_FILE}"
echo "Storage Performance Test Report" | tee -a "${REPORT_FILE}"
echo "Provider: ${STORAGE_PROVIDER}" | tee -a "${REPORT_FILE}"
echo "Storage Class: ${STORAGE_CLASS}" | tee -a "${REPORT_FILE}"
echo "Date: $(date)" | tee -a "${REPORT_FILE}"
echo "Test Tool: fio v3.6+" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Install fio if not present
if ! command -v fio &> /dev/null; then
    echo "Installing fio..." | tee -a "${REPORT_FILE}"
    sudo apt-get update
    sudo apt-get install -y fio
fi

# Install wkhtmltopdf for PDF generation
if ! command -v wkhtmltopdf &> /dev/null; then
    echo "Installing wkhtmltopdf for PDF generation..." | tee -a "${REPORT_FILE}"
    sudo apt-get install -y wkhtmltopdf
fi

# Wait for storage provider to be fully ready
echo "Waiting for storage provider to be fully operational..." | tee -a "${REPORT_FILE}"
sleep 30

# Create a test PVC
cat <<EOF | sudo -i -u vagrant kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fio-test-pvc-${STORAGE_PROVIDER}
spec:
  storageClassName: ${STORAGE_CLASS}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF

# Wait for PVC to be bound (skip for WaitForFirstConsumer storage classes)
case ${STORAGE_PROVIDER} in
  openebs-hostpath|openebs-lvm|openebs-zfs)
    echo "PVC created (will bind when Pod is scheduled - WaitForFirstConsumer mode)" | tee -a "${REPORT_FILE}"
    ;;
  *)
    echo "Waiting for PVC to be bound..." | tee -a "${REPORT_FILE}"
    sudo -i -u vagrant kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/fio-test-pvc-${STORAGE_PROVIDER} --timeout=300s
    ;;
esac

# Create fio test pod
cat <<EOF | sudo -i -u vagrant kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: fio-test-${STORAGE_PROVIDER}
spec:
  containers:
  - name: fio
    image: ljishen/fio
    command: ["sleep", "3600"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "2000m"
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: fio-test-pvc-${STORAGE_PROVIDER}
EOF

# Wait for pod to be ready
echo "Waiting for test pod to be ready..." | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl wait --for=condition=ready pod/fio-test-${STORAGE_PROVIDER} --timeout=300s

sleep 10

echo "" | tee -a "${REPORT_FILE}"
echo "Starting storage performance tests..." | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 1: Random Read IOPS (4KB blocks, 2 jobs, depth 32)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 1: Random Read IOPS (4KB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 2 jobs, I/O depth 32, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=randread \
  --ioengine=libaio \
  --iodepth=32 \
  --rw=randread \
  --bs=4k \
  --direct=1 \
  --size=2G \
  --numjobs=2 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test1 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 2: Random Write IOPS (4KB blocks, 2 jobs, depth 32)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 2: Random Write IOPS (4KB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 2 jobs, I/O depth 32, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=randwrite \
  --ioengine=libaio \
  --iodepth=32 \
  --rw=randwrite \
  --bs=4k \
  --direct=1 \
  --size=2G \
  --numjobs=2 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test2 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 3: Random Read/Write Mix 70/30 (4KB blocks, 2 jobs, depth 32)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 3: Random Read/Write Mix 70/30 (4KB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 2 jobs, I/O depth 32, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=randrw \
  --ioengine=libaio \
  --iodepth=32 \
  --rw=randrw \
  --rwmixread=70 \
  --bs=4k \
  --direct=1 \
  --size=2G \
  --numjobs=2 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test3 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 4: Sequential Read (1MB blocks, 1 job, depth 16)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 4: Sequential Read Throughput (1MB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 1 job, I/O depth 16, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=seqread \
  --ioengine=libaio \
  --iodepth=16 \
  --rw=read \
  --bs=1m \
  --direct=1 \
  --size=4G \
  --numjobs=1 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test4 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 5: Sequential Write (1MB blocks, 1 job, depth 16)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 5: Sequential Write Throughput (1MB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 1 job, I/O depth 16, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=seqwrite \
  --ioengine=libaio \
  --iodepth=16 \
  --rw=write \
  --bs=1m \
  --direct=1 \
  --size=4G \
  --numjobs=1 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test5 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 6: Random Read Latency (4KB blocks, 1 job, depth 1)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 6: Random Read Latency (4KB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 1 job, I/O depth 1, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=latency-read \
  --ioengine=libaio \
  --iodepth=1 \
  --rw=randread \
  --bs=4k \
  --direct=1 \
  --size=1G \
  --numjobs=1 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test6 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Test 7: Random Write Latency (4KB blocks, 1 job, depth 1)
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Test 7: Random Write Latency (4KB)" | tee -a "${REPORT_FILE}"
echo "Configuration: 1 job, I/O depth 1, 60s" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
sudo -i -u vagrant kubectl exec fio-test-${STORAGE_PROVIDER} -- fio \
  --name=latency-write \
  --ioengine=libaio \
  --iodepth=1 \
  --rw=randwrite \
  --bs=4k \
  --direct=1 \
  --size=1G \
  --numjobs=1 \
  --runtime=60 \
  --time_based \
  --group_reporting \
  --filename=/data/test7 | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

echo "========================================" | tee -a "${REPORT_FILE}"
echo "All tests completed!" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"

# Generate HTML for PDF conversion
HTML_FILE="${REPORT_DIR}/report-${STORAGE_PROVIDER}-${TIMESTAMP}.html"
cat > "${HTML_FILE}" <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: 'Courier New', monospace;
            margin: 40px;
            font-size: 10px;
            line-height: 1.4;
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #333;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            border-bottom: 1px solid #ccc;
            padding-bottom: 5px;
        }
        pre {
            background-color: #f5f5f5;
            padding: 10px;
            border-left: 3px solid #333;
            overflow-x: auto;
            font-size: 9px;
        }
        .header {
            background-color: #e9e9e9;
            padding: 20px;
            margin-bottom: 30px;
            border-radius: 5px;
        }
        .footer {
            margin-top: 50px;
            padding-top: 20px;
            border-top: 1px solid #ccc;
            text-align: center;
            color: #666;
        }
    </style>
</head>
<body>
<pre>
HTMLEOF

cat "${REPORT_FILE}" >> "${HTML_FILE}"

cat >> "${HTML_FILE}" <<'HTMLEOF'
</pre>
</body>
</html>
HTMLEOF

# Convert HTML to PDF
echo "Generating PDF report..." | tee -a "${REPORT_FILE}"
wkhtmltopdf --enable-local-file-access --page-size A4 --margin-top 10mm --margin-bottom 10mm --margin-left 10mm --margin-right 10mm "${HTML_FILE}" "${REPORT_PDF}"

# Clean up HTML file
rm -f "${HTML_FILE}"

echo "" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"
echo "Report saved to: ${REPORT_PDF}" | tee -a "${REPORT_FILE}"
echo "Text version: ${REPORT_FILE}" | tee -a "${REPORT_FILE}"
echo "========================================" | tee -a "${REPORT_FILE}"

# Display summary location
echo ""
echo "Storage performance test completed!"
echo "PDF Report: storage-reports/report-${STORAGE_PROVIDER}-${TIMESTAMP}.pdf"
echo "Text Report: storage-reports/report-${STORAGE_PROVIDER}-${TIMESTAMP}.txt"

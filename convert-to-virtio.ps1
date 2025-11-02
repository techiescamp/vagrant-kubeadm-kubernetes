# Convert VirtualBox VM OS disks from SATA to VirtIO-SCSI
# This script must be run AFTER 'vagrant up' completes successfully
#
# Usage:
#   .\convert-to-virtio.ps1
#
# WARNING: This is experimental! VMs might fail to boot after conversion.
# Always test with snapshots first.

param(
    [switch]$DryRun = $false,
    [switch]$Force = $false,
    [switch]$NoRestart = $false
)

# Check if VBoxManage is available
try {
    $null = Get-Command VBoxManage -ErrorAction Stop
} catch {
    Write-Error "VBoxManage not found in PATH. Please add VirtualBox to your PATH."
    Write-Host "Run: `$env:Path += ';C:\Program Files\Oracle\VirtualBox'" -ForegroundColor Yellow
    exit 1
}

# Get all VMs in the Kubernetes Cluster
Write-Host "`n=== Finding VirtualBox VMs ===" -ForegroundColor Cyan
$vms = VBoxManage list vms | Where-Object { $_ -match "kubeadm-kubernetes" } | ForEach-Object {
    if ($_ -match '"([^"]+)"') {
        $matches[1]
    }
}

if ($vms.Count -eq 0) {
    Write-Error "No VMs found. Please run 'vagrant up' first."
    exit 1
}

Write-Host "Found $($vms.Count) VMs to process:" -ForegroundColor Green
$vms | ForEach-Object { Write-Host "  - $_" }

# Track which VMs were running before we stopped them
$runningVMs = @()

# Confirm before proceeding
if (-not $Force -and -not $DryRun) {
    Write-Host "`n WARNING: This will stop all VMs and convert OS disks to VirtIO-SCSI" -ForegroundColor Yellow
    Write-Host "   VMs might fail to boot if conversion fails!" -ForegroundColor Yellow
    $confirm = Read-Host "`nContinue? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Aborted." -ForegroundColor Red
        exit 0
    }
}

Write-Host "`n=== Stopping all VMs ===" -ForegroundColor Cyan
foreach ($vm in $vms) {
    $state = VBoxManage showvminfo $vm --machinereadable | Select-String 'VMState=' | ForEach-Object { $_.ToString().Split('=')[1].Trim('"') }

    if ($state -eq "running") {
        Write-Host "Stopping $vm..." -ForegroundColor Yellow
        $runningVMs += $vm
        if (-not $DryRun) {
            VBoxManage controlvm $vm poweroff 2>&1 | Out-Null
            Start-Sleep -Seconds 3
        }
    } else {
        Write-Host "$vm is already stopped ($state)" -ForegroundColor Gray
    }
}

Write-Host "`n=== Converting OS disks to VirtIO-SCSI ===" -ForegroundColor Cyan
$converted = 0
$skipped = 0
$failed = 0

foreach ($vm in $vms) {
    Write-Host "`nProcessing: $vm" -ForegroundColor White

    # Get storage controller info
    $vmInfo = VBoxManage showvminfo $vm --machinereadable

    # Debug: Show all storage controllers
    Write-Host "  Storage controllers found:" -ForegroundColor Cyan
    $vmInfo | Select-String 'storagecontrollername' | ForEach-Object { 
        Write-Host "    $_" -ForegroundColor Gray
    }

    # Check if SATA Controller exists (check first controller name)
    $sataController = $vmInfo | Select-String 'storagecontrollername0=' | ForEach-Object { $_.ToString().Split('=')[1].Trim('"') }
    
    Write-Host "  Primary controller name: '$sataController'" -ForegroundColor Cyan

    if (-not $sataController -or $sataController -eq "") {
        Write-Host "  No storage controller found, skipping..." -ForegroundColor Yellow
        $skipped++
        continue
    }

    # Check if VirtIO-SCSI controller already exists
    $hasVirtIO = $vmInfo | Select-String 'storagecontrollername.*virtio' -CaseSensitive:$false
    if ($hasVirtIO) {
        Write-Host "  VirtIO-SCSI already configured, skipping..." -ForegroundColor Green
        $skipped++
        continue
    }

    # Get OS disk path from primary controller port 0
    $diskKey = "$sataController-0-0"
    Write-Host "  Looking for disk at: $diskKey" -ForegroundColor Cyan
    $osDiskLine = $vmInfo | Select-String "`"$diskKey`"=" 
    
    if (-not $osDiskLine) {
        Write-Host "  No OS disk found on port 0, skipping..." -ForegroundColor Yellow
        $skipped++
        continue
    }

    $osDisk = $osDiskLine.ToString().Split('=', 2)[1].Trim('"')
    Write-Host "  OS Disk: $osDisk" -ForegroundColor Gray

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would convert to VirtIO-SCSI" -ForegroundColor Cyan
        $converted++
        continue
    }

    # Perform conversion
    try {
        Write-Host "  Creating VirtIO-SCSI controller..." -ForegroundColor Yellow
        VBoxManage storagectl $vm --name "VirtIO SCSI OS" --add virtio-scsi --portcount 2 --bootable on 2>&1 | Out-Null

        Write-Host "  Detaching OS disk from $sataController..." -ForegroundColor Yellow
        VBoxManage storageattach $vm --storagectl $sataController --port 0 --medium none 2>&1 | Out-Null

        Write-Host "  Attaching OS disk to VirtIO-SCSI..." -ForegroundColor Yellow
        VBoxManage storageattach $vm --storagectl "VirtIO SCSI OS" --port 0 --type hdd --medium $osDisk 2>&1 | Out-Null

        Write-Host "  Successfully converted to VirtIO-SCSI!" -ForegroundColor Green
        $converted++
    } catch {
        Write-Host "  Failed: $_" -ForegroundColor Red
        $failed++
    }
}

# Summary
Write-Host "`n=== Conversion Summary ===" -ForegroundColor Cyan
Write-Host "  Converted: $converted" -ForegroundColor Green
Write-Host "  Skipped:   $skipped" -ForegroundColor Yellow
Write-Host "  Failed:    $failed" -ForegroundColor Red

# Restart VMs that were running before
if ($runningVMs.Count -gt 0 -and -not $DryRun -and -not $NoRestart) {
    Write-Host "`n=== Restarting VMs ===" -ForegroundColor Cyan
    Write-Host "The following VMs were running before and will be restarted:" -ForegroundColor Yellow
    $runningVMs | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
    Write-Host "`nRecommendation: Use 'vagrant up' instead for proper cluster startup order." -ForegroundColor Yellow
    
    $restart = Read-Host "`nRestart VMs now? (yes/no/vagrant)"
    
    if ($restart -eq "yes") {
        foreach ($vm in $runningVMs) {
            Write-Host "Starting $vm..." -ForegroundColor Yellow
            VBoxManage startvm $vm --type headless 2>&1 | Out-Null
        }
        Write-Host "VMs started. Check logs with: vagrant ssh <vm-name>" -ForegroundColor Green
    } elseif ($restart -eq "vagrant") {
        Write-Host "`nTo restart the cluster properly, run:" -ForegroundColor Cyan
        Write-Host "  vagrant up" -ForegroundColor White
    } else {
        Write-Host "VMs left stopped. Start with: vagrant up" -ForegroundColor Gray
    }
}

if ($converted -gt 0 -and -not $DryRun) {
    Write-Host "`nConversion complete!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Start VMs: vagrant up" -ForegroundColor White
    Write-Host "  2. Verify boot: vagrant ssh controlplane" -ForegroundColor White
    Write-Host "  3. Check storage controllers with: VBoxManage showvminfo <vm-name>" -ForegroundColor White
    Write-Host "`nIf VMs fail to boot, restore from snapshot or run:" -ForegroundColor Yellow
    Write-Host "  vagrant destroy -f && vagrant up" -ForegroundColor Yellow
}

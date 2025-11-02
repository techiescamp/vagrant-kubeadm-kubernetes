# PowerShell script to copy Kubernetes config from Vagrant to Windows host
# Run this from the project root directory on Windows (PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Copying Kubernetes Config to Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if configs directory exists
$configPath = ".\configs\config"
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Config file not found at $configPath" -ForegroundColor Red
    Write-Host "Make sure your Vagrant cluster is running and provisioned." -ForegroundColor Yellow
    exit 1
}

# Create .kube directory in user home if it doesn't exist
$kubeDir = "$env:USERPROFILE\.kube"
if (-not (Test-Path $kubeDir)) {
    Write-Host "Creating directory: $kubeDir" -ForegroundColor Green
    New-Item -ItemType Directory -Path $kubeDir -Force | Out-Null
}

# Backup existing config if it exists
$destPath = "$kubeDir\config"
if (Test-Path $destPath) {
    $backupPath = "$kubeDir\config.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Backing up existing config to: $backupPath" -ForegroundColor Yellow
    Copy-Item $destPath $backupPath
}

# Copy the config file
Write-Host "Copying config to: $destPath" -ForegroundColor Green
Copy-Item $configPath $destPath -Force

# Update the server address in the config
Write-Host "Updating server address in config..." -ForegroundColor Green
$configContent = Get-Content $destPath -Raw
$configContent = $configContent -replace 'https://[0-9.]+:6443', 'https://10.0.0.10:6443'
Set-Content -Path $destPath -Value $configContent -NoNewline

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "SUCCESS! Kubeconfig copied successfully" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Location: $destPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now use kubectl from PowerShell:" -ForegroundColor Yellow
Write-Host "  kubectl get nodes" -ForegroundColor White
Write-Host "  kubectl get pods -A" -ForegroundColor White
Write-Host ""
Write-Host "Make sure kubectl is installed. Install with:" -ForegroundColor Yellow
Write-Host "  choco install kubernetes-cli" -ForegroundColor White
Write-Host "  or download from: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/" -ForegroundColor White
Write-Host ""

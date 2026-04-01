<#
    Script : Proxmox Cluster Maintenance and VM Deployment
    Author : Philippe VELLY
    Version : 1.2
    Date : 03/31/2026
    Description :
        This script automates VM creation on a Proxmox cluster using industry best practices.

    Prerequisites :
        - PowerShell 7 or higher #https://learn.microsoft.com/en-us/powershell/scripting/install/install-debian?view=powershell-7.5
        - Proxmox API enabled
        - Proxmox 9.1 or higher
        - HA Resources configured https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_pvecm

    Usage : TokenID
        ./Add_VM_PVE.ps1 -FQDN jn1223.jn-hebergement.com -TokenID "root@pam!autoupdate" -Secret "uuid-secret-here"
    Usage : User / Password
        ./Add_VM_PVE.ps1 -FQDN jn1223.jn-hebergement.com -Username root@pam -Password YourPassword
    Docs :
        - https://pve.proxmox.com/pve-docs/api-viewer/index.html
#>
param (
    [Parameter(Mandatory = $true)] [string]$FQDN,
    [string]$TokenID,  # Optional if using User/Pass
    [string]$Secret,   # Optional if using User/Pass
    [string]$Username, # Optional if using Token
    [string]$Password  # Optional if using Token
)

$ProxmoxServer = "https://" + $FQDN + ":8006"
$headers = @{}

# --- Connection Logic ---

if ($TokenID -and $Secret) {
    # MODE 1 : API TOKEN
    Write-Host "🔑 Authenticating via API Token..." -ForegroundColor Cyan
    $headers = @{ "Authorization" = "PVEAPIToken $TokenID=$Secret" }
}
elseif ($Username -and $Password) {
    # MODE 2 : USER / PASSWORD (Ticket)
    Write-Host "👤 Authenticating via User Account..." -ForegroundColor Cyan
    try {
        $body = @{ username = $Username; password = $Password }
        $authResponse = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/access/ticket" -Method POST -Body $body -SkipCertificateCheck

        # The Ticket acts as a session Cookie
        # CSRFPreventionToken is mandatory for write requests (POST/PUT)
        $headers = @{
            "Cookie" = "PVEAuthCookie=$($authResponse.data.ticket)"
            "CSRFPreventionToken" = $authResponse.data.CSRFPreventionToken
        }
        Write-Host "✅ Ticket retrieved successfully." -ForegroundColor Gray
    }
    catch {
        Write-Host "❌ Authentication failed: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "❌ Error: You must provide either a Token (-TokenID/-Secret) or an Account (-Username/-Password)." -ForegroundColor Red
    exit 1
}

# --- Initial Connection Test & Version Validation ---

try {
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "❌ PowerShell 7 or higher is required. Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
        exit 1
    }

    $response = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/version" -Headers $headers -Method GET -SkipCertificateCheck
    $PveVersion = [decimal]$response.data.release
    
    Write-Host "`n✅ Connected to Proxmox successfully!" -ForegroundColor Green
    Write-Host "ℹ️ Source Node: $FQDN"
    Write-Host "ℹ️ PVE Version: $($response.data.version) (Release: $PveVersion)" -ForegroundColor Cyan

    if ($PveVersion -lt 9.0) {
        Write-Host "❌ Proxmox VE $PveVersion detected. Version 9.1 or higher required." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "❌ API access error. Check account permissions or Token validity." -ForegroundColor Red
    exit 1
}

# --- Cluster Node Selection (HA LRM Check) ---

$nodesResponse = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes" -Headers $headers -Method Get -SkipCertificateCheck
$NodeTarget = $null

foreach ($nodeEntry in $nodesResponse.data) {
    $NodeToCheck = $nodeEntry.node
    Write-Host "Checking node: $NodeToCheck" -ForegroundColor Cyan

    # Check current HA status
    $haStatus = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/ha/status/current" -Headers $headers -Method GET -SkipCertificateCheck
    $lrmStatus = $haStatus.data | Where-Object { $_.type -eq "lrm" -and $_.node -eq $NodeToCheck }

    if ($lrmStatus.status -like "*active*") {
        Write-Host "✅ Node $NodeToCheck is active, selected for deployment." -ForegroundColor Green
        $NodeTarget = $NodeToCheck
        break
    }
}

if (-not $NodeTarget) {
    Write-Host "❌ No active nodes found in the cluster!" -ForegroundColor Red
    exit 1
}

# --- Resource Discovery ---

# 1. Storage List
try {
    $storageResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/storage" -Headers $headers -Method GET -SkipCertificateCheck
    $storageData = $storageResp.data | ForEach-Object {
        [PSCustomObject]@{ Name = $_.storage; Type = $_.type; Content = $_.content; Shared = if ($_.shared -eq 1) { "Yes" } else { "No" } }
    }
    Write-Host "`n--- Available Storage ---" -ForegroundColor Yellow
    $storageData | Format-Table -AutoSize
}
catch { Write-Host "❌ Storage Retrieval Error" -ForegroundColor Red; exit 1 }

# 2. Network Interfaces (Bridges and SDN Vnets)
Write-Host "--- Available Networks ---" -ForegroundColor Yellow
$networks = @()

# Fetch physical Bridges
try {
    $bridgeResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/network?type=bridge" -Headers $headers -Method GET -SkipCertificateCheck
    $bridgeResp.data | ForEach-Object { $networks += [PSCustomObject]@{ Type = "Bridge"; Name = $_.iface; Info = $_.comment } }
}
catch { Write-Host "⚠️ Bridge Retrieval Error" -ForegroundColor Gray }

# Fetch SDN Vnets
try {
    $vnetResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/sdn/vnets" -Headers $headers -Method GET -SkipCertificateCheck
    $vnetResp.data | ForEach-Object { $networks += [PSCustomObject]@{ Type = "SDN-Vnet"; Name = $_.vnet; Info = "Zone: $($_.zone) / Tag: $($_.tag)" } }
}
catch { Write-Host "⚠️ SDN Vnet Retrieval Error" -ForegroundColor Gray }

$networks | Format-Table -AutoSize

# 3. Resource Pools
try {
    $poolResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/pools" -Headers $headers -Method GET -SkipCertificateCheck
    Write-Host "--- Available Pools ---" -ForegroundColor Cyan
    if ($poolResp.data) {
        $poolResp.data | Select-Object @{N="ID";E={$_.poolid}}, @{N="Comment";E={$_.comment}} | Format-Table -AutoSize
    } else {
        Write-Host "ℹ️ No pools found. VM will be created without a pool." -ForegroundColor Gray
    }
}
catch { Write-Host "❌ Pool Retrieval Error" -ForegroundColor Red }

# --- Physical CPU Capabilities Analysis ---

$NodeStatus = (Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/status" -Headers $headers -Method GET -SkipCertificateCheck).data
$PhysSockets = [int]$NodeStatus.cpuinfo.sockets
$PhysCpus    = [int]$NodeStatus.cpuinfo.cpus 
$CoresPerSock = $PhysCpus / $PhysSockets     
$CPUFlags = $NodeStatus.cpuinfo.flags

Write-Host "`n--- Node Physical Capabilities ($NodeTarget) ---" -ForegroundColor Yellow
Write-Host "🔲 Physical Sockets: $PhysSockets"
Write-Host "🧠 Threads per Socket: $CoresPerSock"
Write-Host "🚀 Total Threads available: $PhysCpus"

# --- User Input ---

$VMName         = Read-Host "VM Name"
$TargetPool     = Read-Host "Resource Pool (Leave empty for none)"
$OSTypeInput    = Read-Host "OS Type (W for Windows 11 / L for Linux)"
$TargetStorage  = Read-Host "Storage Name (from Name column)"
$SizeGB         = Read-Host "Disk Size (in GB)"
$RAM_GB         = Read-Host "RAM Amount (in GB)"
$VMCoresInput   = Read-Host "Number of CPU Cores"
$HotplugEnable  = Read-Host "Enable Hotplug CPU/RAM/Disk? (Y/N)"
$NetworkBridge  = Read-Host "Network Bridge to use"

# --- Topology & Logic Processing ---

$VMCores = [int]$VMCoresInput
$RAM_MB = [int]$RAM_GB * 1024
$ActualOSType = if ($OSTypeInput -eq "W") { "win11" } else { "l26" }

# Automated Topology Logic
if ($VMCores -gt $CoresPerSock) {
    $VMSockets = 2
    $VMCoresPerSocket = [Math]::Ceiling($VMCores / 2)
    $ActivateNuma = 1
    Write-Host "ℹ️ Topology: Spreading across 2 virtual sockets (Large VM)." -ForegroundColor Cyan
} else {
    $VMSockets = 1
    $VMCoresPerSocket = $VMCores
    $ActivateNuma = 0
}

# Hotplug & NUMA Enforcement
if ($HotplugEnable -eq "Y" -or $HotplugEnable -eq "O") {
    $ActivateNuma = 1
    $HotplugValue = "network,disk,cpu,memory"
} else {
    $HotplugValue = "network,disk,usb"
}

# Disk Optimization String
$DiskOptions = if ($OSTypeInput -eq "W") { ",cache=writeback,discard=on,ssd=1" } else { ",ssd=1" }

# Optimized CPU Model selection
$BestCPUType = "x86-64-v1"
if ($CPUFlags -match "popcnt" -and $CPUFlags -match "sse4_2") { $BestCPUType = "x86-64-v2" }
if ($CPUFlags -match "avx2" -and $CPUFlags -match "bmi2" -and $CPUFlags -match "fma") { $BestCPUType = "x86-64-v3" }
if ($CPUFlags -match "avx512f" -and $CPUFlags -match "avx512vl" -and $CPUFlags -match "avx512bw") { $BestCPUType = "x86-64-v4" }

Write-Host "📡 API Analysis complete. Best physical CPU match: $BestCPUType" -ForegroundColor Green

# --- VM Provisioning ---

$VMID = (Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/nextid" -Headers $headers -Method GET -SkipCertificateCheck).data
Write-Host "`n🚀 Configuring $ActualOSType profile for $VMName (ID: $VMID)..." -ForegroundColor Cyan

$VMParams = @{
    vmid    = $VMID
    name    = $VMName
    node    = $NodeTarget
    ostype  = $ActualOSType
    memory  = $RAM_MB
    numa    = $ActivateNuma
    cores   = $VMCoresPerSocket
    sockets = $VMSockets
    cpu     = $BestCPUType
    hotplug = $HotplugValue
    machine = "q35"
    bios    = "ovmf"
    agent   = 1
    vga     = "type=virtio,memory=128"
    scsihw  = "virtio-scsi-single"
    net0    = "virtio,bridge=" + $NetworkBridge
    scsi0   = $TargetStorage + ":" + $SizeGB + ",format=qcow2" + $DiskOptions + ",iothread=1"
    scsi1   = "none,media=cdrom"
    rng0    = "source=/dev/urandom"
}

# Dynamic Pool Assignment
if (-not [string]::IsNullOrWhiteSpace($TargetPool)) {
    Write-Host "🏷️ Assigning to pool: $TargetPool" -ForegroundColor Gray
    $VMParams.Add("pool", $TargetPool)
}

Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/qemu" -Headers $headers -Method POST -Body $VMParams -SkipCertificateCheck

# 5. Security (TPM v2.0 + UEFI Secure Boot)
Write-Host "🛡️ Hardening (TPM v2.0 + UEFI Secure Boot)..." -ForegroundColor Yellow
$ConfParams = @{
    efidisk0  = $TargetStorage + ":4,efitype=4m,pre-enrolled-keys=1,ms-cert=2023,format=qcow2"
    tpmstate0 = $TargetStorage + ":4,version=v2.0,format=qcow2"
}
Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/qemu/$VMID/config" -Headers $headers -Method POST -Body $ConfParams -SkipCertificateCheck

# 6. HA Enrollment (PVE 9 Rules Mode)
Write-Host "🔄 Enrolling in High Availability..." -ForegroundColor Magenta
$HAParams = @{ sid = "vm:$VMID"; state = "started"; comment = "Auto Provisioned" }
Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/ha/resources" -Headers $headers -Method POST -Body $HAParams -SkipCertificateCheck

# 7. Final Verification
try {
    $vmConfig = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/qemu/$VMID/config" -Headers $headers -Method GET -SkipCertificateCheck
    $VM_MAC = if ($vmConfig.data.net0 -match "([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})") { $matches[0] } else { "Not generated" }
}
catch { $VM_MAC = "Read error" }

Write-Host "`n✅ VM $VMID ($VMName) created successfully!" -ForegroundColor Green
Write-Host "ℹ️ RAM: $RAM_MB MB | Disk: $SizeGB GB (qcow2) | Profile: $ActualOSType" -ForegroundColor White
Write-Host "🌐 MAC Address: $VM_MAC" -ForegroundColor Cyan
Write-Host "📡 Network: $NetworkBridge" -ForegroundColor White

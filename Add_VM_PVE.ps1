<#
    # Proxmox 9.1 Modern VM Provisioner (PowerShell)

    Ce script PowerShell permet d'automatiser la création de machines virtuelles sur **Proxmox VE 9.1+** en respectant les standards de sécurité modernes (Windows 11 Ready) et les nouvelles fonctionnalités du cluster (SDN & HA Rules).

    ## ✨ Fonctionnalités

    * **Authentification Hybride** : Supporte les Tokens API et les comptes utilisateurs (Ticket + CSRF).
    * **Compatibilité Proxmox 9.1** : Utilise les nouveaux endpoints pour la Haute Disponibilité (HA Rules).
    * **Support SDN & Bridge** : Détection automatique des Vnets (SDN) et des Bridges classiques.
    * **Sécurité Windows 11 Ready** :
        * BIOS UEFI (OVMF).
        * TPM v2.0 au format qcow2.
        * Secure Boot avec certificats **Microsoft 2023**.
    * **Optimisé pour les Snapshots** : Tous les disques (incluant EFI et TPM) sont forcés au format **qcow2**.
    * **Intelligence de Cluster** : Sélection automatique du premier nœud actif via le statut LRM (HA).

    ## 🚀 Utilisation

        Usage : TokenID
        ./Add_VM_PVE.ps1 -FQDN pve.mon-domaine.com -TokenID "root@pam!mon-token" -Secret "fa57313e-878d-4c49-9dd1-7faab4837c55"

    Usage : User / Password
        ./Add_VM_PVE.ps1 -FQDN pve.mon-domaine.com -Username root@pam -Password PromoxpasswordRootLocal
        
    Docs :
        - https://pve.proxmox.com/pve-docs/api-viewer/index.html

    ### Prérequis
    - PowerShell 7+ installé. https://learn.microsoft.com/en-us/powershell/scripting/install/install-debian?view=powershell-7.5
    - Un cluster Proxmox VE 9.1. https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_pvecm
    - Un pool nommé `CUST` (modifiable dans le script).        

#>
param (
    [Parameter(Mandatory = $true)] [string]$FQDN,
    [string]$TokenID,  # Optionnel si on utilise User/Pass
    [string]$Secret,   # Optionnel si on utilise User/Pass
    [string]$Username, # Optionnel si on utilise le Token
    [string]$Password  # Optionnel si on utilise le Token
)

$ProxmoxServer = "https://" + $FQDN + ":8006"
$headers = @{}

# --- Logique de Connexion ---

if ($TokenID -and $Secret) {
    # MODE 1 : API TOKEN
    Write-Host "🔑 Authentification par Token API..." -ForegroundColor Cyan
    $headers = @{ "Authorization" = "PVEAPIToken $TokenID=$Secret" }
}
elseif ($Username -and $Password) {
    # MODE 2 : USER / PASSWORD (Ticket)
    Write-Host "👤 Authentification par Compte Utilisateur..." -ForegroundColor Cyan
    try {
        $body = @{ username = $Username; password = $Password }
        $authResponse = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/access/ticket" -Method POST -Body $body -SkipCertificateCheck
        
        # Le Ticket sert de Cookie de session
        # Le CSRFPreventionToken est obligatoire pour les requêtes d'écriture (POST/PUT)
        $headers = @{
            "Cookie" = "PVEAuthCookie=$($authResponse.data.ticket)"
            "CSRFPreventionToken" = $authResponse.data.CSRFPreventionToken
        }
        Write-Host "✅ Ticket récupéré avec succès." -ForegroundColor Gray
    }
    catch {
        Write-Host "❌ Échec de l'authentification : $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "❌ Erreur : Vous devez fournir soit un Token (-TokenID/-Secret) soit un Compte (-Username/-Password)." -ForegroundColor Red
    exit 1
}

# --- Test de connexion final (Identique pour les deux modes) ---

try {
    $response = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/version" -Headers $headers -Method GET -SkipCertificateCheck
    Write-Host "`n✅ Connexion à Proxmox réussie !" -ForegroundColor Green
    Write-Host "ℹ️ Nœud source : $FQDN"
    Write-Host "ℹ️ Version PVE : $($response.data.version) (Release: $($response.data.release))" -ForegroundColor Cyan
}
catch {
    Write-Host "❌ Erreur d'accès à l'API. Vérifiez les permissions du compte ou du Token." -ForegroundColor Red
    exit 1
}

############################################


# Test de connexion à l'API Proxmox
try {
    $response = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/version" -Headers $headers -Method GET -SkipCertificateCheck
    Write-Host "✅ Connexion à Proxmox réussie ! Version : $($response.data.release)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Impossible de se connecter à Proxmox. Vérifiez vos paramètres." -ForegroundColor Red
    exit 1
}


# Vérifier la version de PowerShell
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "❌ PowerShell 7 ou supérieur est requis. Version actuelle: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1  # Quitter le script si la version est insuffisante
}


$ProxmoxVersionMin = 9.0

# Récupérer la version actuelle de Proxmox
$response = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/version" -Headers $headers -Method GET -SkipCertificateCheck
$PveVersion = [decimal]$response.data.release  # Extraire uniquement la version majeure

if ($PveVersion -lt $ProxmoxVersionMin) {
    Write-Host "❌ Proxmox VE $PveVersion détecté. Version 8.0 ou supérieure requise." -ForegroundColor Red
    exit 1 # Quitter le script si la version de PVE n'est pas bonne
}
else {
    Write-Host "✅ Proxmox VE $PveVersion est compatible !" -ForegroundColor Green
}

Write-Host "✅ Prérequis validés : PowerShell version 7+, Proxmox VE 9.1 !!" -ForegroundColor Green


# Liste des nœuds du cluster
$response = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes" -Headers $headers -Method Get -SkipCertificateCheck

# On initialise la variable à vide
$NodeTarget = $null

# Utilisation d'une boucle foreach classique pour pouvoir utiliser 'break'
foreach ($nodeEntry in $response.data) {
    $NodeToCheck = $nodeEntry.node 
    Write-Host "Vérification du nœud: $NodeToCheck" -ForegroundColor Cyan
    
    # Vérifier l'état actuel de la HA
    $responsestatus = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/ha/status/current" -Headers $headers -Method GET -SkipCertificateCheck
    $nodeStatus = $responsestatus.data | Where-Object { $_.type -eq "lrm" } | Where-Object { $_.node -eq $NodeToCheck }
    
    if ($nodeStatus.status -like "*active*") {
        Write-Host "✅ Le nœud $NodeToCheck est bien actif, sélectionné pour la création." -ForegroundColor Green
        $NodeTarget = $NodeToCheck
        # On casse la boucle ici
        break 
    }
}

# Vérification de sécurité
if (-not $NodeTarget) {
    Write-Host "❌ Aucun nœud actif trouvé dans le cluster !" -ForegroundColor Red
    exit
}


# 1. Liste des Stockages (Ta méthode validée)
try {
    $storageResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/storage" -Headers $headers -Method GET -SkipCertificateCheck
    $storageData = $storageResp.data | ForEach-Object {
        [PSCustomObject]@{ Nom = $_.storage; Type = $_.type; Contenu = $_.content; Partagé = if ($_.shared -eq 1) { "Oui" } else { "Non" } }
    }
    Write-Host "`n--- Stockages disponibles ---" -ForegroundColor Yellow
    $storageData | Format-Table -AutoSize
}
catch { Write-Host "❌ Erreur Stockage" -ForegroundColor Red; exit }

# 2. Liste des interfaces Réseau (Bridges et Vnets SDN)
Write-Host "--- Réseaux disponibles ---" -ForegroundColor Yellow
$networks = @()

# Récupération des Bridges physiques
try {
    $bridgeResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/network?type=bridge" -Headers $headers -Method GET -SkipCertificateCheck
    $bridgeResp.data | ForEach-Object { $networks += [PSCustomObject]@{ Type = "Bridge"; Nom = $_.iface; Info = $_.comment } }
}
catch { Write-Host "⚠️ Erreur Bridges" -ForegroundColor Gray }

# Récupération des Vnets SDN
try {
    $vnetResp = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/sdn/vnets" -Headers $headers -Method GET -SkipCertificateCheck
    $vnetResp.data | ForEach-Object { $networks += [PSCustomObject]@{ Type = "SDN-Vnet"; Nom = $_.vnet; Info = "Zone: $($_.zone) / Tag: $($_.tag)" } }
}
catch { Write-Host "⚠️ Erreur SDN Vnets" -ForegroundColor Gray }

$networks | Format-Table -AutoSize

# --- Saisies Utilisateur ---
$VMName = Read-Host "Nom de la VM"
$OSTypeInput = Read-Host "Type d'OS (W pour Windows 11 / L pour Linux)"
$TargetStorage = Read-Host "Nom du stockage (colonne Nom)"
$SizeGB = Read-Host "Taille du disque (en Go)"
$RAM_GB = Read-Host "Quantité de RAM (en Go)"
$VMCores = Read-Host "Nombre de coeurs (CPU)"
$NetworkBridge = Read-Host "Bridge réseau à utiliser"

# Traitement des variables
$RAM_MB = [int]$RAM_GB * 1024
$ActualOSType = if ($OSTypeInput -eq "W") { "win11" } else { "l26" }

# 3. Récupération VMID
$VMID = (Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/nextid" -Headers $headers -Method GET -SkipCertificateCheck).data

Write-Host "`n🚀 Configuration du profil $ActualOSType pour $VMName..." -ForegroundColor Cyan

# 4. Création de la VM (Base + RNG + RAM convertie)
$VMParams = @{
    vmid    = $VMID
    name    = $VMName
    pool    = "CUST"
    node    = $NodeTarget
    ostype  = $ActualOSType
    memory  = $RAM_MB
    cores   = $VMCores
    sockets = 1
    cpu     = "host"
    machine = "q35"
    bios    = "ovmf"
    agent   = 1
    cdrom   = "none"
    scsihw  = "virtio-scsi-pci"
    net0    = "virtio,bridge=" + $NetworkBridge
    virtio0 = $TargetStorage + ":" + $SizeGB + ",format=qcow2"
    rng0    = "source=/dev/urandom"
}

Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/qemu" -Headers $headers -Method POST -Body $VMParams -SkipCertificateCheck

# 5. Ajout EFI/TPM (Format qcow2 forcé pour Snapshots)
Write-Host "🛡️ Sécurisation (TPM v2.0 + UEFI Secure Boot)..." -ForegroundColor Yellow
$ConfParams = @{
    efidisk0  = $TargetStorage + ":4,efitype=4m,pre-enrolled-keys=1,ms-cert=2023,format=qcow2"
    tpmstate0 = $TargetStorage + ":4,version=v2.0,format=qcow2"
}
Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/qemu/$VMID/config" -Headers $headers -Method POST -Body $ConfParams -SkipCertificateCheck

# 6. Activation HA (Mode Rules PVE 9)
Write-Host "🔄 Enrôlement Haute Disponibilité..." -ForegroundColor Magenta
$HAParams = @{ sid = "vm:$VMID"; state = "started"; comment = "Provisioning Auto" }
Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/cluster/ha/resources" -Headers $headers -Method POST -Body $HAParams -SkipCertificateCheck

# 7. Récupération de l'adresse MAC pour affichage
try {
    $vmConfig = Invoke-RestMethod -Uri "$ProxmoxServer/api2/json/nodes/$NodeTarget/qemu/$VMID/config" -Headers $headers -Method GET -SkipCertificateCheck
    # On cherche la MAC dans la chaîne net0 (ex: virtio=XX:XX:XX:XX:XX:XX,bridge=...)
    if ($vmConfig.data.net0 -match "([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})") {
        $VM_MAC = $matches[0]
    }
    else {
        $VM_MAC = "Non générée"
    }
}
catch {
    $VM_MAC = "Erreur de lecture"
}

Write-Host "`n✅ VM $VMID ($VMName) créée avec succès !" -ForegroundColor Green
Write-Host "ℹ️ RAM: $RAM_MB Mo | Disque: $SizeGB Go (qcow2) | Profil: $ActualOSType" -ForegroundColor White
Write-Host "🌐 MAC: $VM_MAC" -ForegroundColor Cyan
Write-Host "📡 Réseau: $NetworkBridge" -ForegroundColor White

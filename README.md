# 🚀 Proxmox 9.1 Modern VM Provisioner (PowerShell 7.X)

This PowerShell script automates Virtual Machine creation on **Proxmox VE 9.1**, adhering to modern performance and security standards (Windows 11 Ready, SDN, and High Availability).

## ✨ Key Features

* **Hybrid Authentication**: Supports both API Tokens (Recommended) and User Accounts (Ticket + CSRF).
* **Smart CPU & Topology Logic (New)**:
    * **Hardware Analysis**: Dynamically retrieves node capabilities (cores/sockets) to optimize VM placement.
    * **Auto-Adaptive Topology**: Automatically aligns virtual sockets with physical architecture to prevent cache latency.
    * **NUMA Awareness**: Intelligent NUMA activation for "Large VMs" or when Hotplug is enabled.
* **Dynamic Hotplug**: Optional support for on-the-fly **CPU, RAM, Disk, and Network** resizing without reboot.
* **Windows 11 Ready**:
    * **UEFI (OVMF)** BIOS with Secure Boot (Microsoft 2023 Certificates).
    * Emulated **TPM v2.0**.
* **Production Optimized**:
    * **VirtIO SCSI Single** controller for superior IO performance.
    * All disks (including EFI/TPM) forced to **qcow2** format to ensure full Snapshot support.
    * CD-ROM drive mapped to the **SCSI bus** (replacing legacy IDE) for better driver management.
* **Cluster Intelligence**: Automatic node selection based on **LRM (Local Resource Manager)** High Availability status.

## 🚀 Getting Started

### Prerequisites
- **PowerShell 7+** (Required for modern REST API handling).
- A **Proxmox VE 9.1** cluster with API access enabled.

### Option 1: Run via API Token (Recommended)
```powershell
./Add_VM_PVE.ps1 -FQDN "pve.mon-domaine.com" -TokenID "root@pam!mon-token" -Secret "ton-secret-uuid"

```
### Option 2: Run via User Account
🔐 Authentication Examples by Account Type
* Linux System Account (PAM): For standard Linux users on the host.
    ```powershell
    ./Add_VM_PVE.ps1 -FQDN "pve.domaine.com" -Username "root@pam" -Password "MonMotDePasse"
    ```
* **Proxmox Internal Account (PVE): For users created directly within the Proxmox interface.
    ```powershell
    ./Add_VM_PVE.ps1 -FQDN "pve.domaine.com" -Username "admin@pve" -Password "MonMotDePasse"
    ```
* Active Directory / LDAP Account: For users authenticated via a Microsoft Domain or external LDAP.
    ```powershell
    ./Add_VM_PVE.ps1 -FQDN "pve.domaine.com" -Username "admin@domaine.com" -Password "MonMotDePasse"
    ```

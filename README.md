# Proxmox 9.1 Modern VM Provisioner (PowerShell 7.X)

Ce script PowerShell permet d'automatiser la création de machines virtuelles sur Proxmox VE 9.1 en respectant les standards de sécurité modernes (Windows 11 Ready) et les nouvelles fonctionnalités du cluster (SDN & HA Rules).

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

### Prérequis
- PowerShell 7+ installé.
- Un cluster Proxmox VE 9.1.

### Via Token API (Recommandé)
```powershell
./Add_VM_PVE.ps1 -FQDN "pve.mon-domaine.com" -TokenID "root@pam!mon-token" -Secret "ton-secret-uuid"

```
### Exemples d'authentification par compte

* Compte Système Linux (PAM).
    ```powershell
    ./Add_VM_PVE.ps1 -FQDN "pve.domaine.com" -Username "root@pam" -Password "MonMotDePasse"
    ```
* **Compte Interne Proxmox (PVE)** : Pour les utilisateurs créés directement dans l'interface Proxmox.
    ```powershell
    ./Add_VM_PVE.ps1 -FQDN "pve.domaine.com" -Username "admin@pve" -Password "MonMotDePasse"
    ```
* Compte de domaine (ad) : Pour les utilisateurs d'un domaine Microsoft.
    ```powershell
    ./Add_VM_PVE.ps1 -FQDN "pve.domaine.com" -Username "admin@domaine.com" -Password "MonMotDePasse"
    ```

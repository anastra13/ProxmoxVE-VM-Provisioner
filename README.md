# 🚀 Proxmox 9.1 Modern VM Provisioner (PowerShell 7.X)

Ce script PowerShell automatise la création de machines virtuelles sur **Proxmox VE 9.1** en respectant les standards de performance et de sécurité actuels (Windows 11 Ready, SDN, et HA).

## ✨ Fonctionnalités

* **Authentification Hybride** : Supporte les Tokens API (recommandé) et les comptes utilisateurs (Ticket + CSRF).
* **Intelligence CPU & Topologie (Nouveau)** :
    * **Analyse Physique** : Récupère les capacités réelles du nœud (cœurs/sockets) pour optimiser le placement.
    * **Topologie Auto-Adaptive** : Aligne automatiquement le nombre de sockets virtuels sur l'architecture physique pour éviter les latences de cache.
    * **Gestion du NUMA** : Activation intelligente du NUMA pour les "Large VMs" ou lors de l'activation du Hotplug.
* **Hotplug Dynamique** : Option pour activer l'ajout à chaud de **CPU, RAM, Disque et Réseau**.
* **Sécurité Windows 11 Ready** :
    * BIOS **UEFI (OVMF)** avec Secure Boot (Certificats Microsoft 2023).
    * **TPM v2.0** émulé.
* **Optimisé pour la Production** :
    * Contrôleur **VirtIO SCSI Single** (meilleures perfs IO).
    * Disques forcés au format **qcow2** pour garantir le support des Snapshots.
    * Lecteur CD-ROM sur bus **SCSI** pour éviter les limitations de l'IDE.
* **Intelligence de Cluster** : Sélection automatique du nœud via le statut **LRM (Haute Disponibilité)**.


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

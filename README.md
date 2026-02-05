# Azure Infrastructure Security: Cloud Architecture Study
[![Secure Landing Zone Pipeline](https://github.com/supakan0409/Azure-secure-landing-zone/actions/workflows/security-scan.yml/badge.svg)](https://github.com/supakan0409/Azure-secure-landing-zone/actions/workflows/security-scan.yml)

This repository represents a **Proof of Concept (PoC)** for designing a secure cloud infrastructure. The primary goal is to gain hands-on experience with **Infrastructure as Code (IaC)** using **Azure Bicep**, while understanding the fundamental components of a secure and scalable cloud environment.

It serves as a study on how to harden a basic landing zone against common attack vectors.

---

## 🛡️ Key Features
### 1. Infrastructure as Code (Bicep)
* **Modular Design:** Resources are defined in Azure Bicep for repeatability and consistency.
* **Visibility First:** Deploys **Azure Log Analytics Workspace** as the foundation for centralized logging.
* **Network Security:** Implements **Virtual Network (VNet)** segmentation and **Network Security Groups (NSG)** with enabled diagnostic logs.

### 2. Identity & Zero Trust
* **Credential-less Compute:** Utilizes **User Assigned Managed Identity** for Virtual Machines to eliminate hardcoded credentials in the codebase.
* **Private Access:** VMs are deployed without Public IPs to reduce the attack surface.

### 3. Automated Security
* **CI/CD Pipeline:** Powered by **GitHub Actions.**
* **Static Analysis (SAST):** Integrates **Checkov** to automatically scan Bicep files for security violations (e.g., unencrypted disks, open ports) on every push.

## 🧩 Architecture & Security Boundaries

```mermaid
graph LR
    subgraph Untrusted ["External / Untrusted Zone"]
        Attacker[("External Actor")]
    end

    subgraph Azure ["Azure Trusted Zone"]
        style Azure fill:#f9f9f9,stroke:#333,stroke-width:2px
        
        subgraph Monitoring ["Detection Plane"]
            LAW[("Log Analytics Workspace")]
        end

        subgraph Network ["Virtual Network"]
            style Network fill:#e6f2ff,stroke:#0072C6
            
            subgraph Backend ["Isolated Backend Subnet"]
                style Backend fill:#fff,stroke:#bf0000,stroke-width:2px,stroke-dasharray: 5 5
                
                VM[("Compute Resource<br/>(No Public IP)")]
                Identity[["Managed Identity"]]
                
                VM -.-> Identity
            end
        end
    end

    %% Connections
    Attacker -- "Blocked" --> VM
    VM -- "Audit Logs" --> LAW
    Identity -- "Auth" --> VM

    %% Pulling the layout wide
    Monitoring ~~~ Network
```
> [!IMPORTANT]
> **Key Posture:** This architecture enforces a "Deny-by-Default" stance. The Backend Subnet is completely isolated from direct internet ingress.

## 🛠️ Tech Stack & Tools Used
| Category | Technology | Usage |
| :--- | :--- | :--- |
| **Cloud Provider** | Microsoft Azure | Target Infrastructure |
| **IaC** |  Azure Bicep | Infrastructure Definition |
| **CI/CD** | GitHub Actions | Automation Pipeline |
| **Security Scanning** | Checkov | Static Code Analysis (IaC Security) |
| **Scripting** | Azure CLI | Deployment Commands |

## 💻 How to Deploy
### Prerequisites

* Azure Subscription (Free Tier / Student)
* Azure CLI installed
* GitHub Account

### Deployment Steps
**1. Clone Repository:**
```bash
git clone https://github.com/supakan0409/Azure-secure-landing-zone.git
cd Azure-secure-landing-zone
```
**2. Login to Azure:**
```bash
az login
```
**3. Deploy via CLI (Manual Test):**
```bash
az group create --name RG-Security-Lab --location koreacentral
az deployment group create --resource-group RG-Security-Lab --template-file main.bicep
```

### ⚠️ Disclaimer
This project is for **educational and research purposes.** While it implements security best practices, a production environment would require additional controls.

---
**Developed by Supakan | © 2026 Academic Research Project | All Rights Reserved.**

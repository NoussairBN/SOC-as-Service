# SOC-as-Code — Projet de Fin d'Études (PFS)
### Déploiement Automatisé d'un Security Operations Center sur AWS

[![Shift-Left Security](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/security-scan.yml/badge.svg)](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/security-scan.yml)
[![Deploy](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/deploy.yml/badge.svg)](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/deploy.yml)

---

## Table des Matières

1. [Vue d'Ensemble du Projet](#1-vue-densemble-du-projet)
2. [Architecture](#2-architecture)
3. [Stack Technologique](#3-stack-technologique)
4. [Structure du Projet](#4-structure-du-projet)
5. [Déploiement Rapide](#5-déploiement-rapide)
6. [Guides Détaillés (Write-Up Alice)](#6-guides-détaillés-write-up-alice)
7. [Démonstrations Vidéo](#7-démonstrations-vidéo)
8. [Scénarios d'Attaque Simulés](#8-scénarios-dattaque-simulés)
9. [Coût & Destruction de l'Infrastructure](#9-coût--destruction-de-linfrastructure)

---

## 1. Vue d'Ensemble du Projet

Ce projet implémente un **SOC (Security Operations Center) entièrement automatisé** sur AWS en suivant une approche **DevSecOps** moderne. L'objectif est de démontrer comment déployer, configurer et valider une infrastructure de détection d'intrusions en utilisant exclusivement de l'Infrastructure as Code (IaC) et du Configuration Management.

**Ce que le projet réalise :**
- Provisionnement automatique d'un réseau AWS segmenté (deux VPCs isolés + VPC Peering)
- Déploiement du SIEM **Wazuh** (Manager + Indexer + Dashboard) en mode All-in-One
- Déploiement d'une application web vulnérable (**DVWA**) et d'un serveur cible (**Metasploitable**) pour les tests
- Détection en temps réel d'attaques web (SQLi, XSS, LFI, CMDi) et réseau (Brute-Force SSH)
- **Réponse Active automatisée** : bannissement IP de l'attaquant sans intervention humaine
- Pipeline CI/CD sécurisé avec scan Shift-Left (Checkov + tfsec) à chaque commit

---

## 2. Architecture

```
Internet
    │
    ├─── Admin/Analyste ──────────────────────────────────> Dashboard Wazuh (HTTPS/443)
    │
    └─── Admin (SSH/22) ──> Bastion Host (IP Publique)
                                    │
                    ┌───────────────┼───────────────────────────────────────┐
                    │               │                                       │
          ┌─────────▼──────────┐    │ VPC Peering (Privé)   ┌──────────────▼────────────┐
          │  VPC Client        │    │                        │  VPC SOC                  │
          │  (10.0.0.0/16)     │    │                        │  (10.1.0.0/16)            │
          │                    │    │                        │                           │
          │ ┌──────────────┐   │    │                        │ ┌─────────────────────┐   │
          │ │ Subnet Public│   │    │                        │ │ Subnet Public       │   │
          │ │ Bastion+NAT  │   │    │                        │ │ Wazuh Server        │   │
          │ └──────────────┘   │    │                        │ │ (Manager+Indexer    │   │
          │                    │<───┼────────────────────────│ │  +Dashboard)        │   │
          │ ┌──────────────┐   │    │ Logs Wazuh (1514/1515) │ └─────────────────────┘   │
          │ │Subnet Privé  │   │    │                        │                           │
          │ │ DVWA+Agent   │───┼────┘                        └───────────────────────────┘
          │ │ Metasploit   │   │
          │ └──────────────┘   │
          └────────────────────┘
```

---

## 3. Stack Technologique

| Couche | Technologie | Rôle |
|---|---|---|
| **Infrastructure** | Terraform >= 1.7 | Provisionnement AWS (VPC, EC2, Security Groups) |
| **Configuration** | Ansible >= 2.14 | Installation Wazuh, DVWA, agents |
| **CI/CD** | GitHub Actions | Pipeline automatisé + Scan Shift-Left |
| **SIEM / XDR** | Wazuh 4.11 | Détection, corrélation, réponse active |
| **Cible Web** | DVWA (Docker) | Application vulnérable pour tests web |
| **Cible Réseau** | Metasploitable | Services vulnérables pour tests SSH/FTP |
| **Backend IaC** | AWS S3 + DynamoDB | État Terraform distant et verrouillé |
| **Cloud** | AWS (us-east-1) | Hébergement de toute l'infrastructure |

---

## 4. Structure du Projet

```
SOC-as-Service/
│
├── .github/
│   └── workflows/
│       ├── security-scan.yml   # Scan Shift-Left (Checkov + tfsec) à chaque commit
│       ├── deploy.yml          # Pipeline principal : Terraform → Ansible
│       └── ansible.yml         # Workflow manuel : reconfiguration Ansible seule
│
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Point d'entrée : assemble les modules
│   ├── variables.tf            # Paramètres configurables
│   ├── outputs.tf              # IPs et URLs exportées après déploiement
│   ├── backend.tf              # Backend distant (S3 + DynamoDB)
│   ├── terraform.tfvars.example # Modèle de configuration (à copier)
│   └── modules/
│       ├── networking/         # VPCs, Subnets, Internet GW, NAT GW, Peering, SGs
│       ├── compute-client/     # Bastion Host, DVWA, Metasploitable
│       └── compute-soc/        # Serveur Wazuh (All-in-One)
│
├── ansible/                    # Configuration Management
│   ├── ansible.cfg             # Configuration globale Ansible (SSH, timeouts)
│   ├── site.yml                # Playbook principal (ordre : Wazuh → DVWA → Agents)
│   └── inventory/
│       ├── hosts.yml           # Inventaire statique (IPs, ProxyJump via Bastion)
│       └── aws_ec2.yml         # Inventaire dynamique (API AWS EC2)
│   └── roles/
│       ├── wazuh-server/       # Installation Wazuh + règles custom + Active Response
│       ├── wazuh-agent/        # Installation agents + enregistrement + ossec.conf (Jinja2)
│       ├── dvwa/               # Docker DVWA + service dvwa-log-forwarder (systemd)
│       └── metasploitable/     # Configuration services vulnérables (FTP, SSH faible)
│
├── docs/                       # Documentation complète
│   ├── architecture.drawio     # Diagramme réseau (Draw.io)
│   ├── tutorial_alice.md       # Vue d'ensemble du write-up
│   ├── guide_phase_1.md        # Prérequis & Configuration Environnement
│   ├── guide_phase_2.md        # Bootstrap & Infrastructure Terraform
│   ├── guide_phase_3.md        # Configuration Management Ansible
│   ├── guide_phase_4.md        # CI/CD GitHub Actions
│   ├── guide_phase_5.md        # Simulation d'Attaques & Validation SOC
│   └── demo/
│       ├── README_DEMO.md      # Description des vidéos de démonstration
│       ├── demo_wazuh_dashboard.mp4     # [Local uniquement — > 100MB]
│       └── demo_attack_detection.mp4   # [Local uniquement — > 100MB]
│
├── scripts/                    # Scripts de maintenance et de test
│   ├── test_rules.sh           # Test de règles Wazuh via wazuh-logtest
│   ├── test_exec_rule.sh       # Test de la règle Command Injection (100043)
│   ├── fix_docker_logs.sh      # Correctif log-forwarder Docker
│   └── check_users.sh          # Vérification des agents Wazuh connectés
│
├── bootstrap.ps1               # Initialisation backend Terraform (S3 + DynamoDB + SSH Key)
└── .gitignore                  # Exclusions : tfstate, clés SSH, vidéos MP4
```

---

## 5. Déploiement Rapide

### Prérequis
- Compte AWS avec un utilisateur IAM `pfs-soc-deployer` (droits AdminAccess)
- AWS CLI v2 configuré : `aws configure --profile pfs-soc`
- Terraform >= 1.7 installé
- Ansible >= 2.14 installé (Linux/WSL2)
- Dépôt GitHub avec les 4 Secrets configurés (voir ci-dessous)

### Secrets GitHub requis

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | Clé d'accès IAM |
| `AWS_SECRET_ACCESS_KEY` | Clé secrète IAM |
| `SSH_PUBLIC_KEY` | Contenu de `~/.ssh/pfs-soc-key.pub` |
| `EC2_PRIVATE_KEY` | Contenu de `~/.ssh/pfs-soc-key` |

### Option A — Déploiement Automatisé (Recommandé)

```bash
# Étape 0 : Initialiser le backend Terraform et générer la clé SSH
.\bootstrap.ps1 -Profile "pfs-soc" -Region "us-east-1"

# Étape 1 : Ajouter les 4 Secrets dans GitHub
# Settings → Secrets and variables → Actions → New repository secret

# Étape 2 : Déclencher le déploiement
git push origin main
# Ou manuellement : GitHub → Actions → Deploy SOC Infrastructure → Run workflow (apply)
```

### Option B — Déploiement Manuel (Local)

```bash
# 1. Initialiser le backend
.\bootstrap.ps1

# 2. Déployer l'infrastructure
cd terraform
terraform init
terraform plan -var="my_public_ip=$(curl -s https://ifconfig.me)/32" -out=tfplan
terraform apply tfplan

# 3. Configurer les serveurs
cd ../ansible
ansible-playbook site.yml -i inventory/hosts.yml
```

### Accès après déploiement

```
Dashboard Wazuh : https://<WAZUH_PUBLIC_IP>     Login : admin / <voir logs pipeline>
SSH Bastion     : ssh -i ~/.ssh/pfs-soc-key ubuntu@<BASTION_PUBLIC_IP>
```

---

## 6. Guides Détaillés (Write-Up Alice)

Le projet est accompagné d'un **write-up pédagogique complet** structuré en 5 phases, conçu pour qu'une nouvelle personne puisse reconstruire le projet de A à Z en comprenant chaque décision technique.

| Phase | Guide | Contenu |
|---|---|---|
| **1** | [Prérequis & Environnement](docs/guide_phase_1.md) | IAM AWS, install outils, Git, structure projet |
| **2** | [Bootstrap & Terraform](docs/guide_phase_2.md) | Backend S3/DynamoDB, VPC, Peering, NAT Gateway, Security Groups |
| **3** | [Configuration Ansible](docs/guide_phase_3.md) | ProxyJump, Wazuh, DVWA + log-forwarder, Agents, Jinja2, idempotence |
| **4** | [CI/CD GitHub Actions](docs/guide_phase_4.md) | Shift-Left, Secrets, pipeline Terraform→Ansible, outputs inter-jobs |
| **5** | [Simulation & Validation](docs/guide_phase_5.md) | Brute-Force SSH, SQLi, XSS, LFI, CMDi, Active Response, checklist |

> Le diagramme réseau au format Draw.io est disponible ici : [docs/architecture.drawio](docs/architecture.drawio)

---

## 7. Démonstrations Vidéo

### Demo SOC Complet — Attaque, Détection & Réponse Active

https://github.com/NoussairBN/SOC-as-Service/blob/main/docs/demo/demo_soc_complet.mp4

> La vidéo est disponible directement dans le dépôt : [`docs/demo/demo_soc_complet.mp4`](docs/demo/demo_soc_complet.mp4)

**Ce que montre la vidéo :**

| Étape | Contenu |
|---|---|
| **Dashboard Wazuh** | Interface après déploiement — 2 agents actifs, règles personnalisées |
| **Attaque Brute-Force SSH** | Hydra depuis le Bastion sur Metasploitable |
| **Détection temps réel** | Alerte Règle 100010 (niveau 10) sur le Dashboard |
| **Active Response** | IP de l'attaquant bannîe automatiquement en < 30s |
| **Attaque Web (SQLi)** | Injection SQL sur DVWA → Alerte Règle 100001 |
| **Attaque Web (XSS)** | Cross-Site Scripting → Alerte Règle 100003 |

> Les enregistrements d'écran originaux (292 MB et 124 MB) sont décrits dans [`docs/demo/README_DEMO.md`](docs/demo/README_DEMO.md)

---

## 8. Scénarios d'Attaque Simulés

| # | Attaque | Outil | Cible | Règle Wazuh | Niveau | Active Response |
|---|---|---|---|---|---|---|
| 1 | Brute-Force SSH | Hydra | Metasploitable | 100010 | 10 | ✅ Ban IP (iptables) |
| 2 | SQL Injection | curl | DVWA | 100001 | 12 | ❌ |
| 3 | Cross-Site Scripting (XSS) | curl | DVWA | 100003 | 11 | ❌ |
| 4 | Local File Inclusion (LFI) | curl | DVWA | 100004 | 11 | ❌ |
| 5 | OS Command Injection | curl | DVWA | 100043 | 12 | ✅ Ban IP (iptables) |
| 6 | Privilege Escalation | sudo | DVWA/Meta | 100020 | 11 | ❌ |
| 7 | File Integrity Monitoring | touch /etc/ | DVWA/Meta | syscheck | 7 | ❌ |

---

## 9. Coût & Destruction de l'Infrastructure

### Coût estimé

| Durée | Coût estimé |
|---|---|
| 3 jours (démo complète) | ~$8 |
| 1 semaine | ~$19 |

### Détruire l'infrastructure

```bash
# Via GitHub Actions (recommandé) :
# GitHub → Actions → Deploy SOC Infrastructure → Run workflow → action: destroy

# Ou localement :
cd terraform && terraform destroy -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/pfs-soc-key.pub)" \
  -var="my_public_ip=$(curl -s https://ifconfig.me)/32"
```

> [!CAUTION]
> Le Bucket S3 et la table DynamoDB du backend ne sont **pas** détruits par `terraform destroy`. Les supprimer manuellement depuis la console AWS si le projet est définitivement terminé.

---

*Projet réalisé dans le cadre du PFS (Projet de Fin d'Études) — DevSecOps — 2026*

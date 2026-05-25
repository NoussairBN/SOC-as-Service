# SOC-as-Code — PFS (Projet de Fin d'Études)

## Déploiement Automatisé d'un SOC sur AWS

[![Shift-Left Security](https://github.com/<TON_USERNAME>/SOC-as-Service/actions/workflows/security-scan.yml/badge.svg)](https://github.com/<TON_USERNAME>/SOC-as-Service/actions/workflows/security-scan.yml)
[![Deploy](https://github.com/<TON_USERNAME>/SOC-as-Service/actions/workflows/deploy.yml/badge.svg)](https://github.com/<TON_USERNAME>/SOC-as-Service/actions/workflows/deploy.yml)

## Architecture

| Composant | Technologie | Instance |
|---|---|---|
| Infrastructure as Code | Terraform | — |
| Configuration Management | Ansible | — |
| CI/CD | GitHub Actions | — |
| SIEM / XDR | Wazuh | `c7i-flex.large` |
| VPC Client (cibles) | EC2 | `t3.micro` ×3 |

## Structure du Projet

```
SOC-as-Service/
├── .github/workflows/    # Pipelines CI/CD
├── terraform/            # Infrastructure as Code
│   └── modules/
│       ├── networking/   # VPCs, Subnets, Peering
│       ├── compute-client/ # Bastion, DVWA, Metasploitable
│       └── compute-soc/  # Wazuh Server
├── ansible/              # Configuration Management
│   ├── inventory/        # Inventaire dynamique AWS EC2
│   └── roles/            # Rôles : wazuh-server, wazuh-agent, dvwa
└── docs/                 # Documentation et captures démo
```

## Prérequis

- Terraform >= 1.7
- AWS CLI v2 configuré avec le profil `pfs-soc`
- Ansible >= 2.14 (via WSL2 ou Linux)
- GitHub Secrets : `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `EC2_PRIVATE_KEY`

## Déploiement

Le déploiement est **entièrement automatisé** via GitHub Actions.

```bash
# Déclencher le déploiement
git push origin main

# Ou via workflow_dispatch (apply / destroy)
# GitHub → Actions → Deploy SOC Infrastructure → Run workflow
```

## Coût Estimé

~$8 pour 3 jours de run complet.

## Destruction de l'Infrastructure

```bash
# Via GitHub Actions (workflow_dispatch → action: destroy)
# Ou localement :
cd terraform && terraform destroy -auto-approve
```

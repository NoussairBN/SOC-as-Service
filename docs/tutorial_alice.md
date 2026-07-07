# Tutoriel : Construction pas-à-pas du projet SOC-as-Code (Guide pour Alice)

Ce guide est conçu pour accompagner Alice dans la création, le déploiement et la maîtrise du projet **SOC-as-Code** à partir de zéro. Il détaille chaque phase du projet, du provisionnement de l'infrastructure sur AWS à la simulation d'attaques et la détection sur le SIEM Wazuh.

---

## Sommaire
1. [Phase 1 : Prérequis & Configuration de l'Environnement](#phase-1--prérequis--configuration-de-lenvironnement)
2. [Phase 2 : Bootstrap & Infrastructure avec Terraform](#phase-2--bootstrap--infrastructure-avec-terraform)
3. [Phase 3 : Configuration Management avec Ansible](#phase-3--configuration-management-avec-ansible)
4. [Phase 4 : Automatisation CI/CD avec GitHub Actions](#phase-4--automatisation-cicd-avec-github-actions)
5. [Phase 5 : Simulation d'Attaques & Validation du SOC](#phase-5--simulation-dattaques--validation-du-soc)

---

## Phase 1 : Prérequis & Configuration de l'Environnement

Alice doit commencer par préparer sa machine locale pour pouvoir communiquer avec AWS et exécuter les scripts de déploiement.

### 1. Outils à installer sur la machine d'Alice
*   **Git** : Pour versionner son projet et l'envoyer sur son dépôt GitHub.
*   **AWS CLI v2** : Pour configurer ses accès au cloud AWS.
*   **Terraform (>= 1.7)** : Pour créer l'infrastructure réseau et les serveurs.
*   **Ansible (>= 2.14)** : Pour configurer automatiquement les serveurs (requis sous Linux ou WSL2 si Alice est sur Windows).

### 2. Configuration du profil AWS
Alice doit créer un utilisateur IAM sur sa console AWS avec les droits nécessaires (AdministratorAccess de préférence pour un projet de fin d'études) et configurer son CLI local :
```bash
aws configure --profile pfs-soc
```
Alice doit saisir :
*   Son **AWS Access Key ID**
*   Son **AWS Secret Access Key**
*   La région par défaut : `us-east-1` (ou `eu-west-3`)

---

## Phase 2 : Bootstrap & Infrastructure avec Terraform

Cette phase consiste à poser les fondations réseau et à configurer un stockage distant sécurisé pour Terraform.

### 1. Le Bootstrap (Script d'initialisation)
Avant d'écrire l'infrastructure, Alice doit configurer un "Backend" Terraform afin que son équipe puisse collaborer et que l'état de l'infrastructure (le fichier `terraform.tfstate`) soit sauvegardé de manière sécurisée dans le cloud AWS.
*   Alice exécute le script `bootstrap.ps1` (ou équivalent bash) qui va :
    1. Créer un **Bucket S3** privé sur AWS avec chiffrement et versioning activés.
    2. Créer une table **DynamoDB** pour verrouiller l'état et éviter que deux personnes n'appliquent des modifications en même temps.
    3. Générer une clé SSH sécurisée pour les futures connexions aux instances (`~/.ssh/pfs-soc-key`).
    4. Générer le fichier `terraform/backend.tf`.

### 2. Écriture du code Terraform
Alice structure son répertoire `terraform/` avec des modules réutilisables :

#### A. Le module `networking`
Définit le réseau virtuel complet :
*   **VPC Client (10.0.0.0/16)** : Un sous-réseau public (Bastion, NAT Gateway) et un sous-réseau privé (DVWA, Metasploitable).
*   **VPC SOC (10.1.0.0/16)** : Un sous-réseau public hébergeant le serveur Wazuh.
*   **VPC Peering** : Établit une route privée entre les deux VPCs pour éviter que le trafic de sécurité ne passe par internet.
*   **Security Groups** : Des pare-feux stricts (ex: le Bastion n'accepte le SSH que depuis l'IP publique d'Alice).

#### B. Le module `compute-client`
Définit les instances EC2 du VPC Client :
*   **Bastion** (`t3.micro`) : Possède une IP publique. Il installe automatiquement `nmap` et `hydra` pour les tests d'Alice.
*   **DVWA** (`t3.micro`) : Instance privée. Installe Docker au démarrage pour accueillir l'application vulnérable.
*   **Metasploitable** (`t3.micro`) : Instance privée. Expose des configurations de sécurité affaiblies.

#### C. Le module `compute-soc`
*   **Wazuh Server** (`c7i-flex.large`) : Instance puissante hébergeant la suite complète Wazuh.

Alice peut ensuite lancer son premier test en local :
```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

---

## Phase 3 : Configuration Management avec Ansible

Une fois les machines allumées par Terraform, Alice doit les configurer. C'est le rôle d'Ansible.

### 1. Configuration de l'Inventaire (`hosts.yml`)
Alice doit expliquer à Ansible comment se connecter aux machines. Elle définit un inventaire qui utilise le Bastion comme rebond SSH (ProxyJump) pour accéder aux instances privées :
```yaml
ansible_ssh_common_args: "-o ProxyJump=ubuntu@<IP_PUBLIQUE_BASTION>"
```

### 2. Création et application des rôles Ansible
Alice écrit trois rôles Ansible principaux :

*   **Rôle `wazuh-server`** :
    *   Configure un espace d'échange (Swap file) car l'Indexer Wazuh nécessite de la mémoire vive.
    *   Télécharge et exécute le script d'installation All-in-One de Wazuh.
    *   Déploie le fichier de règles personnalisées (`custom_rules.xml`) et la configuration de réponse active.
*   **Rôle `dvwa`** :
    *   Déploie le conteneur Docker `vulnerables/web-dvwa` sur l'instance.
    *   Installe le service systemd `dvwa-log-forwarder` pour copier en temps réel les logs internes de Docker vers le système hôte afin que l'agent de sécurité puisse les analyser.
*   **Rôle `wazuh-agent`** :
    *   Installe l'agent Wazuh sur DVWA et Metasploitable.
    *   Enregistre les agents auprès du Wazuh Manager via l'IP privée du VPC Peering.
    *   Configure l'agent pour lire les logs système et le fichier de logs Apache `/var/log/dvwa-access.log`.

Alice exécute ensuite sa configuration :
```bash
cd ansible
ansible-playbook site.yml -i inventory/hosts.yml
```

---

## Phase 4 : Automatisation CI/CD avec GitHub Actions

Pour ne pas avoir à exécuter ces commandes manuellement, Alice va automatiser tout le cycle de vie du projet.

### 1. Sécuriser le dépôt GitHub
Alice ajoute ses secrets d'accès AWS et ses clés SSH privées/publiques dans les **Secrets de son dépôt GitHub** (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `EC2_PRIVATE_KEY`, `SSH_PUBLIC_KEY`).

### 2. Le pipeline de Scan Sécurité (`security-scan.yml`)
Avant de déployer, Alice utilise des outils de scan statique d'IaC :
*   **Checkov** et **Trivy** analysent son code Terraform pour vérifier qu'elle n'a pas laissé de ports ouverts à tout internet par erreur ou configuré des accès trop permissifs.

### 3. Le pipeline de Déploiement (`deploy.yml`)
Ce workflow se déclenche à chaque `git push` sur `main` :
1.  **Job Terraform** : Initialise Terraform, génère le plan et applique les changements. Il exporte les adresses IP obtenues en tant que variables de sortie (outputs).
2.  **Job Ansible** : Récupère les adresses IP générées, écrit dynamiquement le fichier `hosts.yml` et configure la configuration SSH, attend que les machines soient prêtes, puis exécute le Playbook Ansible pour installer Wazuh et ses agents.

---

## Phase 5 : Simulation d'Attaques & Validation du SOC

C'est l'étape finale où Alice prouve le bon fonctionnement de son SOC.

### 1. Se connecter sur la console de contrôle (Bastion)
Alice se connecte en SSH sur le Bastion Host, qui représente sa machine d'attaque :
```bash
ssh -i ~/.ssh/pfs-soc-key ubuntu@<IP_PUBLIQUE_BASTION>
```

### 2. Simuler une attaque de mot de passe (Brute-Force SSH)
Alice lance une attaque par dictionnaire avec `hydra` sur l'instance Metasploitable (10.0.2.x) :
```bash
hydra -l demouser -P /usr/share/wordlists/fasttrack.txt ssh://10.0.2.x
```

### 3. Simuler une attaque web (Injection SQL / XSS)
Alice effectue une requête web malveillante simulant une tentative d'extraction de données sur DVWA (10.0.2.y) :
```bash
curl "http://10.0.2.y/vulnerabilities/sqli/?id=%27+UNION+SELECT+1%2C2--+&Submit=Submit" -H "Cookie: security=impossible; PHPSESSID=123"
```

### 4. Valider la détection et la réaction
*   Alice ouvre son navigateur sur `https://<WAZUH_PUBLIC_IP>` et se connecte.
*   **Visualisation** : Dans le module "Security Events", Alice voit apparaître les alertes d'injection SQL (Règle 100001) et de brute-force SSH (Règle 100010).
*   **Réponse Active** : En retournant sur le Bastion, Alice constate qu'elle ne peut plus communiquer avec sa cible. Son adresse IP a été automatiquement bannie par le pare-feu de la machine cible suite à l'alerte Wazuh. Le SOC a fonctionné de manière autonome !

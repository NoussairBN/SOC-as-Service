# Guide de Rédaction : Phase 1 — Prérequis et Configuration de l'Environnement

Bienvenue dans la première phase de construction du projet **SOC-as-Code**. Ce guide pédagogique n'est pas une simple liste de commandes à copier/coller. Il explique **pourquoi** nous utilisons chaque outil, **comment** configurer les accès de manière sécurisée, et **comment** structurer le projet depuis une feuille blanche.

---

## 1. Comprendre la pile technologique (Stack)

Avant d'installer quoi que ce soit, Alice doit comprendre le rôle de chaque composant et l'architecture de son poste de travail :

```
+-------------------------------------------------------------+
|                     Poste de Travail (Local)                |
|  +------------------+  +---------------------------------+  |
|  | Windows / macOS  |  |      WSL (Ubuntu / Linux)       |  |
|  |  - Git           |  |  - Ansible (Moteur d'exécution) |  |
|  |  - AWS CLI       |  |  - Terraform (CLI)              |  |
|  |  - VS Code       |  |                                 |  |
|  +------------------+  +---------------------------------+  |
+-------------------------------------------------------------+
                               |
                               | (API AWS via HTTPS / SSH)
                               v
+-------------------------------------------------------------+
|                          AWS Cloud                          |
|  - Provisionnement des réseaux (VPCs) et machines (EC2)     |
+-------------------------------------------------------------+
```

*   **AWS CLI** : L'interface en ligne de commande qui permet de parler aux API d'AWS pour s'authentifier et interroger l'état des ressources.
*   **Terraform** : L'outil d'Infrastructure as Code (IaC). Il lit des fichiers déclaratifs (`.tf`) et traduit cela en appels API AWS pour créer le réseau, les pare-feux et les machines.
*   **Ansible** : L'outil de gestion de configuration. Il se connecte en SSH sur les machines créées par Terraform pour y installer des logiciels, configurer des fichiers de sécurité et démarrer des conteneurs.
    *   *Note importante pour Alice :* Le moteur de contrôle d'Ansible ne fonctionne pas nativement sous Windows. Si Alice utilise Windows, elle devra impérativement l'installer dans **WSL2 (Windows Subsystem for Linux)**.

---

## 2. Configuration d'AWS et gestion des accès (IAM)

Pour que Terraform et le CLI puissent créer des ressources chez AWS, Alice doit créer un utilisateur de confiance appelé **compte de service** ou **utilisateur IAM programmatique**.

### Étape 1 : Création de l'utilisateur sur la console AWS
1. Se connecter à la [Console AWS](https://aws.amazon.com/).
2. Rechercher le service **IAM** (Identity and Access Management).
3. Cliquer sur **Users** (Utilisateurs) $\rightarrow$ **Create user** (Créer un utilisateur).
4. Nommer l'utilisateur : `pfs-soc-deployer`.
5. **Ne pas** lui donner accès à la console de gestion AWS (Console AWS Management). Cet utilisateur ne servira que pour les scripts et les APIs.
6. Cliquer sur **Next**.

### Étape 2 : Attribution des permissions
Pour ce projet académique, Alice a besoin de droits étendus pour configurer le réseau, les pare-feux, les serveurs EC2 et le stockage S3.
1. Choisir **Attach policies directly** (Associer directement des politiques).
2. Rechercher et cocher la politique : `AdministratorAccess` (ou `PowerUserAccess` combiné à des droits IAM spécifiques si elle souhaite être plus restrictive).
3. Cliquer sur **Next** puis sur **Create user**.

### Étape 3 : Génération des clés d'accès (Access Keys)
Une fois l'utilisateur créé :
1. Cliquer sur le nom de l'utilisateur `pfs-soc-deployer`.
2. Aller dans l'onglet **Security credentials** (Identifiants de sécurité).
3. Faire défiler jusqu'à **Access keys** (Clés d'accès) et cliquer sur **Create access key**.
4. Choisir le cas d'usage : **Command Line Interface (CLI)**.
5. Cocher la case de confirmation et cliquer sur **Next**.
6. Cliquer sur **Create access key**.
7. **IMPORTANT** : Récupérer et sauvegarder immédiatement dans un gestionnaire de mots de passe :
    *   Le **Access Key ID** (ex: `AKIAIOSFODNN7EXAMPLE`)
    *   Le **Secret Access Key** (ex: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)
    *   *Attention :* La clé secrète ne sera plus jamais affichée par AWS après la fermeture de cette page.

### Étape 4 : Configuration locale avec les profils nommés
Pour éviter d'utiliser ses accès personnels ou de mélanger ses projets, Alice va configurer un profil AWS dédié nommé `pfs-soc` :
```bash
aws configure --profile pfs-soc
```
Le CLI va demander 4 informations :
1.  `AWS Access Key ID` : Entrer la clé publique récupérée.
2.  `AWS Secret Access Key` : Entrer la clé secrète récupérée.
3.  `Default region name` : Entrer `us-east-1` (Virginie du Nord) ou `eu-west-3` (Paris). Nous utiliserons `us-east-1` dans ce guide car c'est la région standard où la majorité des types d'instances et fonctionnalités AWS sont disponibles au coût le plus bas.
4.  `Default output format` : Saisir `json`.

#### Où sont stockés ces secrets ?
Le CLI AWS crée un dossier caché dans le répertoire utilisateur d'Alice (`~/.aws/` sous Linux/WSL, ou `C:\Users\Alice\.aws\` sous Windows) contenant deux fichiers clés :
*   `credentials` : Contient les jetons d'accès.
*   `config` : Contient la région et le format de sortie par défaut.

Alice peut vérifier que sa connexion fonctionne en interrogeant l'identité actuelle d'AWS :
```bash
aws sts get-caller-identity --profile pfs-soc
```
Si la commande renvoie un JSON contenant le numéro de son compte AWS et l'ARN de l'utilisateur `pfs-soc-deployer`, la configuration est réussie.

---

## 3. Installation des outils de développement

Alice doit installer les outils sur son poste. Si elle est sous Windows, elle doit effectuer ces installations à l'intérieur de sa distribution WSL2 (ex: Ubuntu).

### Étape 1 : Installer Terraform
Sous Linux / WSL (Ubuntu) :
```bash
# 1. Installer les packages requis pour ajouter des dépôts tiers sécurisés
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl

# 2. Ajouter la clé GPG officielle de HashiCorp
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 3. Ajouter le dépôt HashiCorp aux sources apt
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# 4. Mettre à jour et installer
sudo apt-get update && sudo apt-get install terraform
```
Vérifier l'installation :
```bash
terraform -version
```

### Étape 2 : Installer Ansible
Ansible s'installe idéalement via le gestionnaire de paquets Python `pip` pour obtenir une version récente et stable.
```bash
# 1. Mettre à jour apt et installer Python3 et pip
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-virtualenv

# 2. Installer Ansible via pip
pip3 install ansible

# 3. Installer la bibliothèque passlib (requise par Ansible pour chiffrer les mots de passe)
pip3 install passlib
```
Vérifier l'installation :
```bash
ansible --version
```

---

## 4. Initialisation du Projet et structure des fichiers

Alice part d'un dossier vide. Elle doit organiser son code de manière propre et structurée pour séparer l'infrastructure (Terraform) de la configuration applicative (Ansible).

### Étape 1 : Créer les répertoires
Depuis son terminal, Alice crée l'arborescence du projet :
```bash
mkdir -p SOC-as-Service/{terraform/modules/{networking,compute-client,compute-soc},ansible/{inventory,roles},docs,scripts}
cd SOC-as-Service
```

Cette structure garantit :
*   `terraform/` : Regroupe tout le code IaC. Les sous-dossiers dans `modules/` isolent la logique réseau de la logique de calcul.
*   `ansible/` : Contient les scripts de configuration logicielle.
*   `docs/` : Contient la documentation, les rapports d'attaque et les diagrammes.
*   `scripts/` : Contient des petits scripts de test et de maintenance rapide.

### Étape 2 : Configurer le fichier `.gitignore`
Puisqu'Alice va utiliser Git, il est **fondamental** de s'assurer qu'aucun fichier sensible (clés privées SSH, variables contenant des mots de passe, fichiers d'état locaux de Terraform) ne soit envoyé sur GitHub. 

Alice crée un fichier nommé `.gitignore` à la racine de son projet avec le contenu suivant :

```gitignore
# --- Secrets et clés privées ---
*.pem
*.key
*.pub
*.keys
secrets.tfvars
terraform.tfvars

# --- Fichiers d'état Terraform (contiennent des secrets en clair) ---
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
tfplan

# --- Fichiers temporaires et logs d'Ansible ---
*.log
*.retry
ansible/.ansible/
ansible/inventory/hosts.yml # Les adresses IP de production changent et ne doivent pas être versionnées

# --- Fichiers système et IDE ---
.DS_Store
.idea/
.vscode/
```

### Étape 3 : Initialiser le dépôt Git
Alice initialise son projet localement pour commencer à suivre ses modifications :
```bash
git init
git add .gitignore
git commit -m "Initial commit: structure du projet et configuration gitignore"
```

---

## Prochaine Étape
Alice est maintenant prête à passer à la **Phase 2 : Écriture du code d'Infrastructure (Terraform)**, où elle va apprendre à écrire ses premiers fichiers `.tf` pour déclarer son réseau AWS et ses instances.

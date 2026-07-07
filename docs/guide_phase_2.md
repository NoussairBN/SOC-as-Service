# Guide Phase 2 — Bootstrap & Infrastructure avec Terraform

Dans la Phase 1, Alice a préparé son poste de travail, configuré ses accès AWS et initialisé la structure de son projet. Elle est maintenant prête à écrire son infrastructure.

Cette phase couvre deux grandes parties :
1. **Le Bootstrap** : Préparer les ressources AWS nécessaires au bon fonctionnement de Terraform avant d'écrire une seule ligne de code d'infrastructure.
2. **L'Infrastructure as Code** : Écrire les fichiers Terraform qui vont déclarer et créer le réseau, les pare-feux et les serveurs.

---

## Partie A — Le Bootstrap : Préparer le Terrain

### Pourquoi un Bootstrap ?

Lorsque Terraform crée ou modifie des ressources, il enregistre l'état exact de l'infrastructure dans un fichier appelé **`terraform.tfstate`**. Ce fichier est le cerveau de Terraform : il sait ce qui existe déjà sur AWS pour ne pas le recréer à chaque fois.

Par défaut, ce fichier est stocké localement sur la machine d'Alice. Cela pose deux problèmes :

- **Problème de collaboration** : Si une autre personne (ou le pipeline GitHub Actions) veut déployer, il n'a pas accès au fichier local d'Alice.
- **Problème de sécurité** : Le fichier `tfstate` peut contenir des secrets en clair (mots de passe, clés d'accès). Le stocker sur un poste local ou dans Git est risqué.

**La solution** : Configurer un **Backend distant et sécurisé** hébergé sur AWS.

### Les composants du Backend Terraform

Alice a besoin de deux ressources AWS pour cela :

| Composant | Service AWS | Rôle |
|---|---|---|
| Stockage de l'état | **S3 Bucket** | Héberge le fichier `terraform.tfstate` de manière chiffrée et versionnée |
| Verrouillage | **Table DynamoDB** | Empêche deux opérations Terraform de tourner en parallèle sur le même état |

> [!NOTE]
> Le verrouillage DynamoDB est essentiel dans un contexte CI/CD : si deux personnes poussent sur `main` en même temps, sans verrou, les deux pipelines GitHub Actions tourneraient simultanément et corrompraient l'état de l'infrastructure.

### Étape 1 : Créer le Bucket S3 pour l'état Terraform

Alice doit créer un bucket S3 **unique** (les noms sont globaux chez AWS). Elle ajoute un suffixe aléatoire pour garantir l'unicité du nom.

**Concept à comprendre** : Plusieurs paramètres de sécurité sont indispensables sur ce bucket :
- **Versioning** : Conserve un historique des fichiers `tfstate`. Si Alice fait une fausse manœuvre, elle peut restaurer un état antérieur.
- **Chiffrement AES-256** : Chiffre les données au repos car le fichier d'état peut contenir des informations sensibles.
- **Blocage d'accès public** : Interdit absolument tout accès depuis Internet à ce bucket.

Alice peut visualiser la logique ainsi :

```
+-------------------+    tfstate (chiffré)    +---------------------+
| Terraform (Local) |  ──────────────────────> |  S3 Bucket (AWS)    |
| ou GitHub Actions |  <────────────────────── |  - Versioning: ON   |
+-------------------+    lecture / écriture    |  - Public access: OFF|
         |                                     +---------------------+
         | (verrou avant modification)                    |
         v                                               |
+-------------------+                                    |
| DynamoDB Table    | <──────────────────────────────────+
| (LockID)         |      Terraform pose un verrou
+-------------------+      avant de modifier l'état
```

### Étape 2 : Générer la paire de clés SSH

Toutes les connexions SSH vers les instances EC2 utilisent une **authentification par clé asymétrique** (clé publique / clé privée). C'est un mécanisme bien plus sûr qu'un mot de passe car il est impossible à brute-forcer.

Le principe de fonctionnement :
- Alice génère une paire de clés : une **clé privée** (gardée secrète sur sa machine) et une **clé publique** (déposée sur chaque instance EC2 par Terraform).
- Lors d'une connexion SSH, Alice prouve qu'elle possède la clé privée sans jamais la transmettre sur le réseau.

Alice génère une clé de type **Ed25519**, l'algorithme le plus moderne et le plus sécurisé disponible :
```
ssh-keygen -t ed25519 -C "pfs-soc-key" -f ~/.ssh/pfs-soc-key
```
Cela crée deux fichiers :
- `~/.ssh/pfs-soc-key` → **Clé privée** : ne quitte JAMAIS la machine d'Alice, ne va JAMAIS dans Git.
- `~/.ssh/pfs-soc-key.pub` → **Clé publique** : peut être partagée librement, sera déposée sur les instances EC2.

> [!CAUTION]
> La clé privée `~/.ssh/pfs-soc-key` ne doit JAMAIS être versionnée dans Git. Vérifier que le `.gitignore` contient bien `*.key` et `*.pem` avant de faire un `git commit`.

### Étape 3 : Écrire le fichier `backend.tf`

Une fois le bucket S3 créé, Alice doit indiquer à Terraform d'utiliser ce stockage distant. Elle crée le fichier `terraform/backend.tf` :

**Ce que fait chaque ligne :**

```hcl
terraform {
  backend "s3" {
    # Nom du bucket S3 créé lors du bootstrap
    bucket = "pfs-soc-tfstate-xxxxxxxx"

    # Chemin du fichier d'état à l'intérieur du bucket
    # Plusieurs projets peuvent cohabiter dans un même bucket avec des clés différentes
    key = "global/terraform.tfstate"

    # La région où se trouve le bucket (doit correspondre à la région du projet)
    region = "us-east-1"

    # Active le verrou via DynamoDB pour éviter les modifications simultanées
    use_lockfile = true

    # Chiffre le fichier d'état lors de l'envoi (chiffrement en transit)
    encrypt = true
  }
}
```

> [!IMPORTANT]
> Le fichier `backend.tf` **doit** être commité dans Git car il ne contient aucun secret (juste le nom du bucket et la région). Il permet à n'importe quel collaborateur et au pipeline CI/CD de savoir où trouver l'état de l'infrastructure.

---

## Partie B — L'Infrastructure as Code avec Terraform

### L'architecture des fichiers Terraform

Terraform est déclaratif : Alice décrit l'état désiré de son infrastructure et Terraform se charge de l'atteindre. Elle n'écrit pas des procédures ("créer un VPC"), elle déclare des ressources ("il doit exister un VPC avec ces caractéristiques").

Alice organise son code Terraform en **modules** pour séparer les responsabilités :

```
terraform/
├── main.tf           → Point d'entrée : assemble les modules
├── variables.tf      → Déclare les paramètres configurables
├── outputs.tf        → Déclare les valeurs à exporter après déploiement
├── backend.tf        → Configuration du stockage distant de l'état
├── terraform.tfvars  → Valeurs des variables (NE PAS commiter !)
└── modules/
    ├── networking/   → VPCs, Subnets, Peering, Security Groups
    ├── compute-client/ → Bastion, DVWA, Metasploitable
    └── compute-soc/  → Serveur Wazuh
```

**Pourquoi des modules ?** Un module est une boîte noire réutilisable. Le fichier `main.tf` racine ne sait pas comment créer un VPC ; il appelle simplement le module `networking` en lui passant des paramètres. Cela permet de réutiliser le même module dans différents environnements (dev, staging, production) en changeant simplement les valeurs.

---

### Fichier 1 : `variables.tf` — Les paramètres configurables

Ce fichier est la liste de tous les paramètres que Alice veut pouvoir changer sans modifier le code. C'est comme la liste des ingrédients d'une recette.

**Concept clé** : Chaque variable peut avoir :
- un `type` (string, number, bool, list, map)
- une `description` (documentation)
- une `default` (valeur par défaut optionnelle)
- `sensitive = true` pour que Terraform n'affiche jamais sa valeur dans les logs

Exemple commenté de la structure du fichier :

```hcl
# Région AWS où tout sera déployé
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# Nom du projet — utilisé pour nommer et taguer toutes les ressources
# ex: "pfs-soc-vpc-client", "pfs-soc-bastion", etc.
variable "project_name" {
  description = "Project name used for tagging and naming"
  type        = string
  default     = "pfs-soc"
}

# Plage d'adresses IP du réseau Client (contient Bastion, DVWA, Metasploitable)
# /16 = 65 534 adresses disponibles, largement suffisant
variable "vpc_client_cidr" {
  description = "CIDR block for the Client VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Plage d'adresses IP du réseau SOC (contient le serveur Wazuh)
# Doit être différent du vpc_client_cidr pour que le Peering fonctionne
variable "vpc_soc_cidr" {
  description = "CIDR block for the SOC VPC"
  type        = string
  default     = "10.1.0.0/16"
}

# Contenu de la clé publique SSH — marqué "sensitive" pour ne pas apparaître
# dans les logs et les outputs de Terraform
variable "ssh_public_key" {
  description = "SSH public key content for EC2 access"
  type        = string
  sensitive   = true
}

# IP publique d'Alice pour restreindre l'accès SSH au Bastion
# Format CIDR : "x.x.x.x/32" (/32 = une seule adresse IP)
variable "my_public_ip" {
  description = "Your public IP to restrict SSH access to Bastion"
  type        = string
}
```

---

### Fichier 2 : `main.tf` — Le chef d'orchestre

C'est le point d'entrée de l'infrastructure. Ce fichier fait trois choses :

**1. Configurer le provider AWS :**
```hcl
provider "aws" {
  region = var.aws_region

  # Tous les ressources créées auront ces tags automatiquement
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"  # Permet de savoir qu'une ressource est gérée par l'IaC
    }
  }
}
```

**2. Récupérer dynamiquement l'image Ubuntu (AMI) :**

Au lieu de coder en dur un identifiant d'image (AMI ID) qui change selon la région et le temps, Alice utilise un **data source** pour trouver automatiquement la dernière version d'Ubuntu 22.04 LTS disponible :

```hcl
# Un "data source" lit des données existantes chez AWS sans rien créer
data "aws_ami" "ubuntu_22" {
  most_recent = true                    # Toujours prendre la plus récente
  owners      = ["099720109477"]        # Compte officiel Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

**3. Appeler les modules dans le bon ordre :**

```hcl
# Module réseau — doit être créé EN PREMIER car les autres en dépendent
module "networking" {
  source = "./modules/networking"

  project_name               = var.project_name
  vpc_client_cidr            = var.vpc_client_cidr
  vpc_soc_cidr               = var.vpc_soc_cidr
  my_public_ip               = var.my_public_ip
  # ... autres paramètres
}

# Module instances client — dépend du module networking pour les IDs de sous-réseaux
module "compute_client" {
  source = "./modules/compute-client"

  ami_id           = data.aws_ami.ubuntu_22.id
  # Référence à une valeur PRODUITE par le module networking
  public_subnet_id = module.networking.client_public_subnet_id
  sg_bastion_id    = module.networking.sg_bastion_id
  # ... autres paramètres
}

# Module SOC — dépend aussi du module networking
module "compute_soc" {
  source = "./modules/compute-soc"

  ami_id              = data.aws_ami.ubuntu_22.id
  soc_public_subnet_id = module.networking.soc_public_subnet_id
  sg_wazuh_id          = module.networking.sg_wazuh_id
  # Réutilise la clé SSH créée dans compute_client
  key_pair_name        = module.compute_client.key_pair_name
}
```

---

### Module `networking` — Le Cœur du Projet

C'est le module le plus important. Il définit toute la topologie réseau.

#### Concept 1 : Les deux VPCs et pourquoi les séparer

Alice crée deux réseaux virtuels complètement isolés l'un de l'autre par défaut :

```
Internet
    |
+---+--------------------+       +----------------------------+
|   VPC Client           |       |   VPC SOC                  |
|   (10.0.0.0/16)        |       |   (10.1.0.0/16)            |
|                        |  VPC  |                            |
|  Subnet Public         | Peer- |  Subnet Public             |
|  (10.0.1.0/24)         | ing   |  (10.1.1.0/24)             |
|  ┌─────────┐           |<----->|  ┌──────────────────────┐  |
|  │ Bastion │           |       |  │   Wazuh Server       │  |
|  │  +EIP   │           |       |  │   (Manager+Dashboard)│  |
|  └─────────┘           |       |  └──────────────────────┘  |
|  ┌──────────┐          |       +----------------------------+
|  │NAT Gateway│         |
|  └──────────┘          |
|                        |
|  Subnet Privé          |
|  (10.0.2.0/24)         |
|  ┌──────┐ ┌──────────┐ |
|  │ DVWA │ │Metasploit│ |
|  └──────┘ └──────────┘ |
+------------------------+
```

**Pourquoi deux VPCs ?** La séparation garantit que même si un attaquant compromet entièrement le VPC Client (DVWA ou Metasploitable), il ne peut pas accéder directement au réseau SOC hébergeant Wazuh. Le seul canal autorisé entre les deux VPCs est le VPC Peering, et seul le trafic sur les ports Wazuh (1514, 1515) est autorisé.

#### Concept 2 : Le VPC Peering

Le **VPC Peering** est une connexion réseau privée entre deux VPCs AWS. Le trafic entre eux ne passe jamais par Internet ; il reste dans le backbone interne d'AWS.

```hcl
resource "aws_vpc_peering_connection" "client_to_soc" {
  vpc_id      = aws_vpc.client.id      # VPC demandeur
  peer_vpc_id = aws_vpc.soc.id         # VPC accepteur
  auto_accept = true                    # Même compte AWS → acceptation automatique
}
```

Une fois le Peering établi, Alice doit **obligatoirement** ajouter des routes dans les tables de routage des deux VPCs pour que le trafic sache par où passer. Sans route, même avec le Peering créé, les paquets ne savent pas comment atteindre l'autre réseau.

```hcl
# Dans la route table du VPC Client :
# "Pour atteindre 10.1.0.0/16 (VPC SOC), passe par la connexion Peering"
route {
  cidr_block                = var.vpc_soc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.client_to_soc.id
}

# Dans la route table du VPC SOC :
# "Pour atteindre 10.0.0.0/16 (VPC Client), passe par la connexion Peering"
route {
  cidr_block                = var.vpc_client_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.client_to_soc.id
}
```

#### Concept 3 : Le NAT Gateway — Internet pour les instances privées

Les instances du Subnet Privé (DVWA, Metasploitable) n'ont pas d'adresse IP publique. Sans elle, elles ne peuvent pas accéder à Internet pour télécharger des paquets ou des images Docker.

**La solution** : Un **NAT Gateway** (Network Address Translation) placé dans le Subnet Public. Les instances privées envoient leur trafic sortant vers le NAT, qui le transmet vers Internet avec sa propre IP publique (Elastic IP). Internet répond au NAT qui retransmet la réponse à l'instance privée.

```
Instance Privée (10.0.2.20)
    |
    | trafic sortant (ex: apt-get update)
    v
NAT Gateway (Subnet Public, EIP: 1.2.3.4)
    |
    | trafic avec IP source = 1.2.3.4
    v
Internet (serveurs de paquets Ubuntu)
```

> [!NOTE]
> Le trafic est **unidirectionnel**. Internet ne peut pas initier une connexion vers l'instance privée via le NAT Gateway. Il peut seulement répondre à des connexions initiées par l'instance. C'est exactement la protection dont Alice a besoin pour ses cibles vulnérables.

#### Concept 4 : Les Security Groups — Les pare-feux d'instances

Chaque instance EC2 possède un ou plusieurs **Security Groups** qui fonctionnent comme un pare-feu à état (stateful). Une règle entrante (`ingress`) n'a pas besoin d'une règle sortante correspondante car AWS suit l'état des connexions.

Alice crée trois Security Groups dans ce projet :

**SG Bastion** — L'accès SSH est restreint à l'IP publique d'Alice uniquement :
```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.my_public_ip]  # Exemple: "88.120.45.12/32"
  # Tout autre IP sur le port 22 est rejeté silencieusement
}
```

**SG Client Privé (DVWA & Metasploitable)** — Le SSH et HTTP ne sont accessibles que depuis le Bastion :
```hcl
# La source est un autre Security Group (pas une plage IP)
# Cela signifie : "autoriser uniquement le trafic venant des instances qui portent le SG Bastion"
ingress {
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  security_groups = [aws_security_group.bastion.id]
}
```

**SG Wazuh** — Le Dashboard (443), les ports agents (1514/1515) et le SSH via Peering :
```hcl
# Le Dashboard est accessible depuis l'IP d'Alice uniquement
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [var.my_public_ip]
}

# Les agents Wazuh (dans le VPC Client) peuvent envoyer des logs
ingress {
  from_port   = 1514
  to_port     = 1515
  protocol    = "tcp"
  cidr_blocks = [var.vpc_client_cidr]  # "10.0.0.0/16"
}
```

---

### Module `compute-client` — Les Instances du VPC Client

Ce module crée trois instances EC2 et une Elastic IP :

#### L'instance Bastion
- Placée dans le **Subnet Public**
- Possède une **Elastic IP** (IP publique fixe) pour que son adresse ne change pas à chaque redémarrage
- Son script de démarrage automatique (`user_data`) installe des outils d'attaque (`nmap`, `hydra`, `netcat`) pour simuler un attaquant

#### L'instance DVWA
- Placée dans le **Subnet Privé** (pas d'IP publique)
- Son script de démarrage installe Docker Engine pour accueillir le conteneur applicatif DVWA
- La configuration complète (démarrage du conteneur, configuration de sécurité) sera faite par Ansible en Phase 3

#### L'instance Metasploitable
- Placée dans le **Subnet Privé**
- Son script de démarrage installe les services vulnérables de base (`vsftpd` pour FTP, `openssh-server`) et affaiblit la configuration SSH (augmentation du nombre de tentatives autorisées) pour la démonstration de brute-force

#### La Paire de Clés SSH
```hcl
resource "aws_key_pair" "pfs_soc" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key  # Contenu de ~/.ssh/pfs-soc-key.pub
}
```
Terraform dépose la **clé publique** sur AWS, qui la copie dans le fichier `~/.ssh/authorized_keys` de chaque instance lors de sa création.

---

### Module `compute-soc` — Le Serveur Wazuh

Ce module crée l'instance qui héberge toute la suite Wazuh.

**Pourquoi un type d'instance différent (`c7i-flex.large`) ?**

Wazuh est composé de trois services qui tournent sur la même machine :
- **Wazuh Manager** : Reçoit et analyse les logs de tous les agents (~100 MB RAM).
- **Wazuh Indexer** (basé sur OpenSearch) : Indexe et stocke tous les événements de sécurité (~2.5 GB RAM minimum).
- **Wazuh Dashboard** (basé sur Kibana) : Fournit l'interface web de visualisation (~500 MB RAM).

Un `t3.micro` (1 GB RAM) est complètement insuffisant. Le `c7i-flex.large` fournit **2 vCPU et 4 GB de RAM**, le minimum viable. Alice configure aussi :
- Un **disque de 50 GB** (les logs de sécurité s'accumulent rapidement).
- Des optimisations noyau dans le `user_data` pour OpenSearch (`vm.max_map_count=262144`).

---

### Fichier 3 : `outputs.tf` — Exporter les informations importantes

Après que Terraform a créé toutes les ressources, Alice a besoin de connaître les adresses IP pour les étapes suivantes (connexion SSH, configuration Ansible, accès au Dashboard). Le fichier `outputs.tf` déclare quelles valeurs afficher et exporter :

```hcl
# Adresse IP publique du Bastion — pour se connecter en SSH
output "bastion_public_ip" {
  description = "Public IP of the Bastion host"
  value       = module.compute_client.bastion_public_ip
}

# URL directement utilisable pour accéder au Dashboard Wazuh
output "wazuh_dashboard_url" {
  description = "Wazuh Dashboard URL"
  value       = "https://${module.compute_soc.wazuh_public_ip}"
}

# Commande SSH complète générée automatiquement — plus besoin de la retaper
output "ssh_bastion_command" {
  value = "ssh -i ~/.ssh/pfs-soc-key ubuntu@${module.compute_client.bastion_public_ip}"
}

# Adresse IP privée de DVWA — transmise à Ansible en Phase 3
output "dvwa_private_ip" {
  value = module.compute_client.dvwa_private_ip
}
```

**Ces outputs sont aussi utilisés par le pipeline GitHub Actions** : Après l'étape Terraform, les valeurs sont exportées comme variables d'environnement et transmises à l'étape Ansible qui suit automatiquement.

---

### Fichier 4 : `terraform.tfvars` — Les vraies valeurs (à ne PAS commiter)

Ce fichier contient les valeurs concrètes des variables pour l'environnement d'Alice. Il est listé dans `.gitignore` car il contient des données personnelles (IP, clé publique) qui ne doivent pas être partagées publiquement.

Alice crée ce fichier en copiant le modèle fourni (`terraform.tfvars.example`) et en le remplissant avec ses propres valeurs :

```hcl
aws_region   = "us-east-1"
project_name = "pfs-soc"
environment  = "dev"

# Contenu de ~/.ssh/pfs-soc-key.pub (récupérer avec : cat ~/.ssh/pfs-soc-key.pub)
ssh_public_key = "ssh-ed25519 AAAA..."

# Son IP publique (récupérer avec : curl ifconfig.me)
# Le /32 est obligatoire : cela signifie "exactement cette adresse et aucune autre"
my_public_ip = "88.120.45.12/32"
```

---

## Récapitulatif : Le cycle de vie Terraform

À ce stade, Alice comprend le cycle complet d'une modification d'infrastructure :

```
Alice écrit/modifie un fichier .tf
            |
            v
terraform init         → Télécharge les plugins AWS nécessaires
            |
            v
terraform plan         → Compare l'état actuel (dans S3) avec le code désiré
                         Affiche ce qui va être créé / modifié / supprimé
                         SANS rien toucher sur AWS (lecture seule)
            |
  Alice valide le plan
            |
            v
terraform apply        → Pose le verrou sur DynamoDB
                         Crée/modifie/supprime les ressources sur AWS
                         Sauvegarde le nouvel état dans S3
                         Libère le verrou DynamoDB
                         Affiche les outputs
            |
            v
Affichage des IPs → Alice peut maintenant se connecter et passer à Ansible (Phase 3)
```

---

## Prochaine Étape
Alice possède maintenant une infrastructure AWS complète et fonctionnelle. Dans la **Phase 3 (Ansible)**, elle va se connecter à ces serveurs pour y installer et configurer Wazuh, déployer DVWA et enregistrer les agents de sécurité.

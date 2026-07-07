# Guide Phase 4 — Automatisation CI/CD avec GitHub Actions

Dans les phases précédentes, Alice a déployé manuellement son infrastructure (Terraform) puis configuré ses serveurs (Ansible). Ces étapes fonctionnent, mais elles ont un défaut majeur : elles nécessitent une intervention humaine à chaque modification du code.

La Phase 4 résout ce problème en mettant en place un **pipeline CI/CD** (Continuous Integration / Continuous Deployment) qui automatise tout le cycle de vie du projet dès qu'Alice pousse du code sur GitHub.

---

## Partie A — Comprendre le CI/CD dans un contexte DevSecOps

### Qu'est-ce qu'un pipeline CI/CD ?

Un pipeline CI/CD est une suite d'étapes automatisées qui se déclenchent à chaque modification du code. Dans le contexte de ce projet, cela signifie qu'à chaque `git push`, GitHub va :

1. **Analyser** la sécurité du code Terraform avant tout déploiement.
2. **Provisionner** l'infrastructure AWS via Terraform.
3. **Configurer** les serveurs via Ansible.
4. **Publier** un résumé avec les adresses IP et les URLs d'accès.

Sans CI/CD, Alice doit mémoriser l'ordre des opérations et les répéter manuellement à chaque changement. Avec CI/CD, une simple modification et un `git push` suffisent.

### Le concept Shift-Left Security

Dans le développement logiciel classique, les tests de sécurité ont lieu à la fin du projet, juste avant la mise en production. Trop tard : les vulnérabilités sont difficiles et coûteuses à corriger.

**Shift-Left** signifie déplacer ces vérifications de sécurité **plus tôt** dans le cycle de vie, dès l'écriture du code. Dans ce projet, Checkov et tfsec analysent le code Terraform **avant** que la première ressource AWS soit créée.

```
Approche Classique :
Écriture → Développement → Tests → SÉCURITÉ → Production
                                        ↑
                                  Trop tard et coûteux

Approche Shift-Left (ce projet) :
SÉCURITÉ → Écriture → Développement → Tests → Production
    ↑
Intégré dès le commit
```

---

## Partie B — Structure des fichiers GitHub Actions

GitHub Actions lit les fichiers de workflow stockés dans `.github/workflows/`. Alice crée trois fichiers :

```
.github/
└── workflows/
    ├── security-scan.yml  → Scan statique de sécurité du code IaC
    ├── deploy.yml         → Pipeline principal : Terraform + Ansible
    └── ansible.yml        → Workflow manuel pour rejouer uniquement Ansible
```

Chaque fichier est un **workflow** composé de :
- **Triggers** (`on:`) : les événements qui déclenchent le workflow
- **Jobs** : des groupes de tâches qui peuvent s'exécuter en parallèle ou en séquence
- **Steps** : des tâches individuelles à l'intérieur d'un job
- **Runners** : des machines virtuelles éphémères (Ubuntu, Windows, macOS) qui exécutent les jobs

---

## Partie C — Workflow 1 : `security-scan.yml` — Le Scan Shift-Left

Ce workflow est le **gardien** du projet. Il se déclenche à chaque modification du code Terraform (sur une Pull Request ou un push) et vérifie que le code ne contient pas de failles de configuration.

### Comment le déclenchement sélectif fonctionne

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - "terraform/**"   # ← Ne se déclenche QUE si des fichiers Terraform ont changé
  push:
    branches: [main]
    paths:
      - "terraform/**"
```

**L'avantage** : Si Alice modifie uniquement un fichier Ansible, le scan Terraform ne se relance pas inutilement. Cela économise du temps et des ressources (les runners GitHub Actions sont facturés à l'usage).

### Outil 1 : Checkov

**Checkov** est un scanner statique d'IaC développé par Bridgecrew (Prisma Cloud). Il analyse le code Terraform et vérifie des centaines de règles de sécurité prédéfinies sans exécuter le code.

Exemples de règles que Checkov vérifierait sur le code d'Alice :
- Le bucket S3 du backend a-t-il le versioning activé ? ✓
- Les Security Groups ont-ils des règles entrantes trop permissives (`0.0.0.0/0` sur tous les ports) ?
- Les instances EC2 ont-elles la surveillance CloudWatch activée ?
- Le chiffrement des volumes EBS est-il activé ?

```yaml
- name: Run Checkov
  uses: bridgecrewio/checkov-action@master
  with:
    directory: terraform/
    framework: terraform
    soft_fail: true    # ← Le pipeline NE s'arrête PAS sur un échec (mode doux)
                       #   Checkov affiche les problèmes mais laisse le deploy continuer
    output_format: cli
```

> [!NOTE]
> Le paramètre `soft_fail: true` est un choix pédagogique. En production, Alice passerait à `soft_fail: false` pour bloquer le déploiement si des vulnérabilités critiques sont détectées.

### Outil 2 : tfsec

**tfsec** est un autre scanner de sécurité IaC, spécialisé dans Terraform, développé par Aqua Security. Il complète Checkov avec des vérifications différentes, notamment sur les bonnes pratiques AWS spécifiques.

La combinaison des deux outils garantit une meilleure couverture : ce que l'un manque, l'autre peut le trouver.

---

## Partie D — Workflow 2 : `deploy.yml` — Le Pipeline Principal

C'est le cœur de l'automatisation. Ce workflow orchestre l'enchaînement complet en trois jobs dépendants :

```
Trigger (git push sur main)
          │
          ▼
Job 1 : security-scan ──── Analyse Checkov + Trivy
          │ (success requis)
          ▼
Job 2 : terraform ─────── Plan + Apply + Exporter les IPs
          │ (success requis)
          ▼
Job 3 : ansible ────────── Configurer tous les serveurs
          │ (success requis)
          ▼
Résumé final : URLs et commandes SSH affichées dans les logs
```

### Les déclencheurs du workflow

```yaml
on:
  push:
    branches: [main]
    paths:
      - "terraform/**"   # Modification de l'infrastructure
      - "ansible/**"     # Modification des configurations

  workflow_dispatch:     # ← Déclenchement MANUEL depuis l'interface GitHub
    inputs:
      action:
        description: "Action (plan / apply / destroy)"
        required: true
        default: "apply"
        type: choice
        options:
          - plan     # Voir ce qui serait fait, sans rien créer
          - apply    # Créer/modifier l'infrastructure
          - destroy  # Supprimer toute l'infrastructure
```

Le `workflow_dispatch` est essentiel : il permet à Alice de déclencher manuellement le pipeline depuis l'interface GitHub avec un choix d'action. C'est notamment utilisé pour `destroy` — supprimer toute l'infrastructure proprement sans avoir à se connecter localement.

### Job 2 : Terraform dans le Pipeline

Ce job illustre plusieurs concepts importants d'un pipeline professionnel :

#### La gestion des credentials sans exposer les secrets

Les clés AWS ne doivent **jamais** apparaître dans le code. GitHub Actions les lit depuis les **Secrets du dépôt** (variables chiffrées configurées dans `Settings → Secrets and variables → Actions`) et les injecte comme variables d'environnement :

```yaml
- name: Configure AWS credentials
  env:
    AWS_ACCESS_KEY_ID:     ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  run: |
    aws configure set aws_access_key_id     "$AWS_ACCESS_KEY_ID"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    aws configure set region                "$AWS_REGION"
    # Vérification : affiche le compte AWS sans révéler les clés
    aws sts get-caller-identity
```

#### L'installation d'une version épinglée de Terraform

Le runner GitHub Actions est une machine vierge sans Terraform. Alice l'installe à chaque run avec une **version précise** pour garantir la reproductibilité :

```yaml
- name: Install Terraform 1.11.4
  run: |
    curl -fsSL https://releases.hashicorp.com/terraform/1.11.4/terraform_1.11.4_linux_amd64.zip \
      -o /tmp/tf.zip
    unzip -o /tmp/tf.zip -d /tmp/tf_bin
    sudo mv -f /tmp/tf_bin/terraform /usr/local/bin/terraform
```

> [!IMPORTANT]
> Épingler une version (`1.11.4` et non `latest`) est une pratique de sécurité et de stabilité. Si HashiCorp publie une version avec un changement cassant ou une vulnérabilité, le pipeline n'est pas affecté automatiquement.

#### La transmission des IPs entre jobs via `outputs`

C'est l'un des aspects les plus techniques de ce pipeline. Terraform crée les ressources et génère des IPs dynamiques. Ces IPs doivent être transmises au Job Ansible qui vient ensuite. GitHub Actions résout cela avec le mécanisme `outputs` :

```yaml
# Dans le Job terraform :
outputs:
  bastion_ip:    ${{ steps.outputs.outputs.bastion_ip }}
  wazuh_priv_ip: ${{ steps.outputs.outputs.wazuh_priv_ip }}
  dvwa_ip:       ${{ steps.outputs.outputs.dvwa_ip }}

# L'étape qui peuple ces outputs :
- name: Extract IPs from Terraform outputs
  id: outputs
  run: |
    echo "bastion_ip=$(terraform output -raw bastion_public_ip)" >> $GITHUB_OUTPUT
    echo "wazuh_priv_ip=$(terraform output -raw wazuh_private_ip)" >> $GITHUB_OUTPUT
    echo "dvwa_ip=$(terraform output -raw dvwa_private_ip)" >> $GITHUB_OUTPUT
```

```yaml
# Dans le Job ansible (job suivant) :
# Référence les outputs du job terraform via needs.terraform.outputs
- name: Generate SSH config
  run: |
    BASTION="${{ needs.terraform.outputs.bastion_ip }}"
    DVWA="${{ needs.terraform.outputs.dvwa_ip }}"
```

### Job 3 : Ansible dans le Pipeline

Ce job illustre la génération dynamique de la configuration à partir des données du job précédent.

#### Génération du fichier SSH config à la volée

Le runner GitHub Actions n'a pas de fichier `~/.ssh/config`. Alice le génère dynamiquement avec les IPs issues de Terraform :

```yaml
- name: Write SSH private key
  run: |
    mkdir -p ~/.ssh
    # Écrire la clé depuis le Secret GitHub
    echo "${{ secrets.EC2_PRIVATE_KEY }}" > ~/.ssh/pfs-soc-key
    chmod 600 ~/.ssh/pfs-soc-key   # Sécurité : clé privée non lisible par les autres

- name: Generate SSH config
  run: |
    BASTION="${{ needs.terraform.outputs.bastion_ip }}"

    cat > ~/.ssh/config << EOF
    Host bastion
      HostName ${BASTION}
      User ubuntu
      IdentityFile ~/.ssh/pfs-soc-key
      StrictHostKeyChecking no

    # Toutes les IPs 10.0.x.x passent par le bastion
    Host 10.0.*.*
      User ubuntu
      IdentityFile ~/.ssh/pfs-soc-key
      ProxyJump bastion
      StrictHostKeyChecking no

    # Toutes les IPs 10.1.x.x passent par le bastion
    Host 10.1.*.*
      User ubuntu
      IdentityFile ~/.ssh/pfs-soc-key
      ProxyJump bastion
      StrictHostKeyChecking no
    EOF
    chmod 600 ~/.ssh/config
```

#### Attente de disponibilité des serveurs

Les instances EC2 mettent quelques minutes à démarrer après leur création par Terraform. Le pipeline ne peut pas exécuter Ansible si SSH n'est pas encore disponible. Alice code une boucle d'attente avec retries :

```yaml
- name: Wait for all instances SSH (max 8 min)
  run: |
    wait_for_ssh() {
      local HOST=$1
      local LABEL=$2
      for i in $(seq 1 48); do    # 48 tentatives × 10 secondes = 8 minutes max
        if ssh ubuntu@${HOST} 'echo ok' 2>/dev/null; then
          echo "[OK] ${LABEL} accessible"
          return 0
        fi
        echo "[${i}/48] ${LABEL} pas encore prêt..."
        sleep 10
      done
      echo "[WARN] ${LABEL} inaccessible après 8 minutes"
      return 1
    }

    wait_for_ssh "${{ needs.terraform.outputs.wazuh_priv_ip }}" "wazuh-server"
    wait_for_ssh "${{ needs.terraform.outputs.dvwa_ip }}"       "dvwa"
```

#### Résumé final du déploiement

À la fin d'un déploiement réussi, le pipeline affiche un récapitulatif lisible dans les logs GitHub Actions :

```yaml
- name: Deployment summary
  if: success()
  run: |
    echo "============================================================"
    echo "  SOC-as-Service — Déploiement Complet ✓"
    echo "============================================================"
    echo "  Dashboard Wazuh : https://${{ needs.terraform.outputs.wazuh_pub_ip }}"
    echo "  Bastion SSH     : ubuntu@${{ needs.terraform.outputs.bastion_ip }}"
    echo "  Login Wazuh     : admin / (voir wazuh-passwords.txt sur le serveur)"
    echo "============================================================"
```

---

## Partie E — Workflow 3 : `ansible.yml` — Le Workflow Manuel

Ce troisième workflow est déclenché **uniquement manuellement** (`workflow_dispatch`). Son utilité est de permettre de re-jouer uniquement la phase Ansible sans refaire le Terraform — utile quand l'infrastructure existe déjà et qu'Alice veut seulement pousser une mise à jour de configuration (nouvelles règles Wazuh, nouvelle version d'un logiciel).

Ce workflow est plus simple : il n'a pas de job Terraform, il génère directement l'inventaire avec des IPs codées en dur (l'infrastructure est censée exister) et exécute le Playbook Ansible.

---

## Partie F — Les Secrets GitHub : Comment les configurer

Avant qu'Alice puisse utiliser le pipeline, elle doit configurer quatre secrets dans son dépôt GitHub.

**Emplacement** : `Settings du dépôt → Secrets and variables → Actions → New repository secret`

| Nom du Secret | Valeur | Origine |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | Console IAM → Utilisateur `pfs-soc-deployer` → Access Keys |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI...` | Même page, lors de la création des Access Keys |
| `SSH_PUBLIC_KEY` | `ssh-ed25519 AAAA...` | Contenu de `~/.ssh/pfs-soc-key.pub` (`cat ~/.ssh/pfs-soc-key.pub`) |
| `EC2_PRIVATE_KEY` | `-----BEGIN OPENSSH PRIVATE KEY-----...` | Contenu de `~/.ssh/pfs-soc-key` (`cat ~/.ssh/pfs-soc-key`) |

> [!CAUTION]
> La clé privée SSH (`EC2_PRIVATE_KEY`) est extrêmement sensible. GitHub chiffre et masque automatiquement les Secrets dans les logs — ils n'apparaissent jamais en clair dans les sorties du pipeline. Alice ne doit jamais copier-coller cette clé dans le code ou dans un fichier non chiffré.

---

## Récapitulatif : Ce qui se passe à chaque `git push`

```
Alice modifie une règle Wazuh dans ansible/roles/wazuh-server/files/custom_rules.xml
                    │
                    ▼
            git commit && git push origin main
                    │
                    ▼
          GitHub Actions détecte le push
                    │
         ┌──────────┴──────────────────────────┐
         │                                      │
         ▼                                      │
  security-scan.yml                             │
  ├── Checkov analyse terraform/               │
  └── tfsec analyse terraform/                 │
         │ (soft_fail : continue même si alertes)
         ▼
  deploy.yml : Job terraform
  ├── Installer Terraform 1.11.4
  ├── terraform init (récupère l'état depuis S3)
  ├── terraform plan (calcule les changements)
  ├── terraform apply (aucun changement ici car seul Ansible a changé)
  └── Exporter les IPs → outputs du job
         │
         ▼
  deploy.yml : Job ansible
  ├── Installer Ansible
  ├── Écrire la clé SSH depuis les Secrets
  ├── Générer ~/.ssh/config avec ProxyJump
  ├── Générer ansible/inventory/hosts.yml avec les IPs Terraform
  ├── Attendre que SSH soit disponible sur tous les hôtes
  ├── ansible-playbook site.yml (idempotent : ne change que ce qui a changé)
  └── Afficher le résumé : URL Dashboard + commande SSH Bastion
```

---

## Prochaine Étape
Le pipeline est opérationnel. L'infrastructure est déployée et configurée de manière entièrement automatisée. Dans la **Phase 5**, Alice va enfin endosser le rôle de l'attaquant pour tester et valider que son SOC détecte et réagit correctement à chaque menace.

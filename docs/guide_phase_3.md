# Guide Phase 3 — Configuration Management avec Ansible

Dans la Phase 2, Alice a créé toute l'infrastructure AWS : les réseaux, les pare-feux et les serveurs sont allumés. Mais ces serveurs sont encore vides — ce sont des machines Ubuntu fraîchement installées, sans logiciel de sécurité ni application vulnérable.

C'est le rôle d'**Ansible** dans cette phase : se connecter à ces machines et les configurer automatiquement, de manière reproductible et sans intervention humaine.

---

## Partie A — Comprendre Ansible et son fonctionnement

### Qu'est-ce qu'Ansible et en quoi est-il différent de Terraform ?

| Dimension | Terraform | Ansible |
|---|---|---|
| Rôle | Créer / détruire des ressources (infrastructures) | Configurer des systèmes existants |
| Mode | Déclaratif (l'état désiré) | Procédural puis idempotent (des tâches ordonnées) |
| Communication | API AWS (HTTPS) | SSH direct sur les machines |
| Langage | HCL (HashiCorp Configuration Language) | YAML |
| État | Stocke un état (tfstate) | Sans état persistant (sans-agent par défaut) |

**Résumé :** Terraform dit à AWS "construis ces bâtiments". Ansible dit aux machines dans ces bâtiments "installe ces logiciels et applique ces configurations".

### Le modèle Push d'Ansible (sans agent)

Ansible n'a pas besoin d'installer un programme sur les machines cibles. Il se connecte simplement en **SSH** depuis la machine de contrôle (le poste d'Alice ou le runner GitHub Actions) et exécute les commandes à distance. Ce modèle "sans agent" est un avantage énorme : pas de processus supplémentaire à gérer sur les cibles.

```
Machine de Contrôle d'Alice
(ou runner GitHub Actions)
           |
           | SSH (port 22) via ProxyJump Bastion
           |
     +-----+------+   +------------------+   +-------------------+
     | Bastion    |   | Wazuh Server     |   | DVWA / Metasploit |
     | (Pivot SSH)|-->| (VPC SOC)        |   | (Subnet Privé)    |
     +------------+   +------------------+   +-------------------+
                              ^                        ^
                              |                        |
                       SSH via ProxyJump         SSH via ProxyJump
```

### Le problème du ProxyJump (Rebond SSH)

Les machines DVWA, Metasploitable et le serveur Wazuh n'ont pas d'adresse IP publique. Alice ne peut pas s'y connecter directement depuis Internet. Elle doit d'abord passer par le Bastion Host.

Ansible gère ce rebond via la directive `ProxyJump` dans la configuration SSH :
- Alice se connecte au Bastion sur son IP publique.
- Le Bastion ouvre ensuite une connexion vers l'IP privée de la cible.
- Ansible voit cela comme une connexion directe, transparente.

---

## Partie B — La Structure des fichiers Ansible

Alice organise son répertoire Ansible de la manière suivante :

```
ansible/
├── ansible.cfg          → Configuration globale du comportement d'Ansible
├── site.yml             → Le Playbook principal : chef d'orchestre de tout
└── inventory/
│   ├── hosts.yml        → Inventaire des machines et leurs adresses IP
│   └── aws_ec2.yml      → Inventaire dynamique (interroge l'API AWS)
└── roles/
    ├── wazuh-server/    → Installation et config du serveur SIEM Wazuh
    ├── wazuh-agent/     → Installation des agents sur les cibles
    ├── dvwa/            → Déploiement de l'application vulnérable
    └── metasploitable/  → Configuration des services vulnérables
```

---

## Partie C — Fichier 1 : `ansible.cfg` — Configuration Globale

Ce fichier définit le comportement par défaut d'Ansible pour tout le projet. Sans lui, Alice devrait préciser des dizaines de paramètres à chaque commande. C'est l'équivalent d'un fichier `.gitconfig` pour Git.

**Explication des paramètres clés :**

```ini
[defaults]
# L'inventaire à utiliser par défaut si aucun n'est spécifié
inventory = inventory/hosts.yml

# L'utilisateur SSH à utiliser pour toutes les connexions
# Ubuntu 22.04 crée toujours un utilisateur "ubuntu" par défaut
remote_user = ubuntu

# La clé privée SSH générée lors du bootstrap
private_key_file = ~/.ssh/pfs-soc-key

# Désactive la vérification des clés d'hôtes SSH
# Par défaut, SSH demande confirmation la première fois qu'on se connecte à un hôte
# Dans un environnement CI/CD où les IPs changent, c'est bloquant → on désactive
host_key_checking = False

# Timeout SSH élevé (120s) : le serveur DVWA peut être lent à répondre
# après l'installation de Docker (surcharge CPU/RAM)
timeout = 120

# Nombre de machines à configurer en parallèle
forks = 5

[ssh_connection]
# Pipelining : regroupe plusieurs commandes SSH en une seule connexion
# Réduit la latence et accélère significativement l'exécution des tâches
pipelining = True

# Options SSH supplémentaires :
# ServerAliveInterval=30 → Envoie un signal "keepalive" toutes les 30s
#   pour éviter que les connexions longues (ex: install Wazuh ~15min) ne soient coupées
# ConnectTimeout=60 → Délai max pour établir la connexion
# retries = 3 → Réessaie 3 fois en cas d'échec de connexion (hôte temporairement surchargé)
ssh_args = -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ConnectTimeout=60
retries = 3
```

---

## Partie D — Fichier 2 : `hosts.yml` — L'Inventaire des Machines

L'inventaire est la liste de toutes les machines qu'Ansible doit gérer. Il définit aussi comment se connecter à chacune d'elles.

**Structure et concept de groupes :**

Ansible permet de regrouper les machines en **groupes** pour leur appliquer des configurations différentes. Dans ce projet, Alice crée deux groupes principaux :

```yaml
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/pfs-soc-key

  children:
    # ─── Groupe "soc" : Machines dans le VPC SOC ──────────────
    soc:
      vars:
        # Variable disponible pour toutes les machines du groupe "soc"
        # Le rôle wazuh-server l'utilisera pour sa configuration
        wazuh_manager_ip: 10.1.1.133
      hosts:
        wazuh-server:
          ansible_host: 10.1.1.133   # IP privée du serveur Wazuh
          # ProxyJump : pour atteindre cette IP privée, passe par le Bastion
          ansible_ssh_common_args: >-
            -o ProxyJump=ubuntu@54.162.134.225   # IP publique du Bastion

    # ─── Groupe "client" : Machines dans le VPC Client ────────
    client:
      vars:
        # Toutes les machines client savent où envoyer leurs logs Wazuh
        wazuh_manager_ip: 10.1.1.133
      hosts:
        dvwa:
          ansible_host: 10.0.2.98    # IP privée de DVWA (Subnet Privé)
          wazuh_agent_name: dvwa-apache  # Nom personnalisé dans la console Wazuh
          is_dvwa_host: true             # Variable booléenne utilisée dans les templates
          ansible_ssh_common_args: >-
            -o ProxyJump=ubuntu@54.162.134.225

        metasploitable:
          ansible_host: 10.0.2.80
          ansible_ssh_common_args: >-
            -o ProxyJump=ubuntu@54.162.134.225
```

> [!IMPORTANT]
> Dans le pipeline CI/CD (Phase 4), le fichier `hosts.yml` est **regénéré automatiquement** par GitHub Actions à partir des outputs Terraform. Les IPs écrites dans ce fichier local ne sont donc valables que pour un déploiement manuel. C'est pourquoi ce fichier est listé dans `.gitignore`.

---

## Partie E — Fichier 3 : `site.yml` — Le Playbook Principal

Le fichier `site.yml` est le **chef d'orchestre**. Il définit l'ordre d'exécution de toutes les configurations et décide quel groupe de machines reçoit quel rôle.

L'ordre d'exécution est **critique** :

```
PLAY 1 : Wazuh Server → doit être OPÉRATIONNEL en premier
              ↓
         Wazuh Manager écoute sur les ports 1514 et 1515
              ↓
PLAY 2 : DVWA → installe Docker + l'application vulnérable
              ↓
         Pause de 45 secondes pour laisser la machine se stabiliser
              ↓
PLAY 3 : Wazuh Agent sur DVWA → s'enregistre auprès du Manager
```

**Pourquoi cet ordre ?** Si Alice déployait les agents Wazuh (Play 3) avant que le Manager soit prêt (Play 1), la commande d'enregistrement de l'agent échouerait : il n'y a personne pour l'écouter.

**Structure commentée du fichier :**

```yaml
---
# ═════════════════════════════════════════════════════
# PLAY 1 : Wazuh Server dans le VPC SOC
# ═════════════════════════════════════════════════════
- name: "SOC | Install and configure Wazuh Server"
  hosts: soc        # ← Cible le groupe "soc" de hosts.yml
  become: yes       # ← Exécute toutes les tâches en tant que root (sudo)
  gather_facts: no  # ← Ne collecte pas les infos système au début (on le fait après)

  pre_tasks:
    # Attendre que le SSH soit disponible avant de commencer
    # La machine vient de démarrer et peut ne pas être encore prête
    - name: "Wait for SSH to be available (max 5 min)"
      wait_for_connection:
        timeout: 300
        delay: 5
        sleep: 15

    - name: "Gather facts"  # Collecte les informations système (OS, IP, mémoire...)
      setup:

  roles:
    - role: wazuh-server    # ← Exécute le rôle wazuh-server

  post_tasks:
    # Vérification que le Manager écoute bien sur le port 1514
    # avant de passer à l'étape suivante
    - name: "Verify Wazuh Manager is listening on port 1514"
      wait_for:
        port: 1514
        host: 0.0.0.0
        timeout: 60

# ═════════════════════════════════════════════════════
# PLAY 2 : DVWA dans le VPC Client
# ═════════════════════════════════════════════════════
- name: "CLIENT | Install DVWA"
  hosts: dvwa         # ← Cible uniquement la machine "dvwa"
  become: yes
  ignore_unreachable: true  # ← Si la machine est temporairement inaccessible, continuer

  roles:
    - role: dvwa

  post_tasks:
    # Docker et le log-forwarder surchargent la machine
    # On attend qu'elle se stabilise avant d'ouvrir de nouvelles connexions SSH
    - name: "Wait 45s for machine to stabilize"
      pause:
        seconds: 45

# ═════════════════════════════════════════════════════
# PLAY 3 : Wazuh Agent sur DVWA
# ═════════════════════════════════════════════════════
- name: "CLIENT | Deploy Wazuh Agent on DVWA"
  hosts: dvwa
  become: yes

  roles:
    - role: wazuh-agent   # ← Installe et enregistre l'agent

  post_tasks:
    # Vérification finale : lister les agents connectés au Manager
    # La commande est exécutée SUR le serveur Wazuh (delegate_to)
    - name: "Confirm agents connected to manager"
      shell: /var/ossec/bin/agent_control -l
      delegate_to: "{{ groups['soc'][0] }}"  # Exécuté sur le Wazuh Server, pas sur DVWA
      run_once: true
```

---

## Partie F — Les Rôles Ansible : Concept et Structure

Un **rôle** Ansible est un dossier autonome qui encapsule toute la logique pour accomplir une mission précise. Il peut être réutilisé dans d'autres projets ou d'autres playbooks.

La structure standard d'un rôle :

```
mon-role/
├── tasks/
│   └── main.yml      → La liste des tâches à exécuter (le "quoi faire")
├── handlers/
│   └── main.yml      → Actions déclenchées par notify (ex: redémarrer un service)
├── templates/
│   └── *.j2          → Fichiers de configuration dynamiques (Jinja2)
├── files/
│   └── *             → Fichiers statiques à copier tels quels
└── defaults/
    └── main.yml      → Variables par défaut du rôle (les moins prioritaires)
```

**La notion de Handler :** Un handler est une tâche spéciale qui n'est exécutée que si une autre tâche l'a notifiée **et** que cette tâche a réellement effectué un changement. Par exemple :

```yaml
# Dans tasks/main.yml
- name: "Modifier la configuration de Wazuh"
  lineinfile:
    path: /var/ossec/etc/ossec.conf
    line: "..."
  notify: restart wazuh-manager   # ← Notifie le handler si le fichier a changé

# Dans handlers/main.yml
- name: restart wazuh-manager
  service:
    name: wazuh-manager
    state: restarted
```

Si le fichier `ossec.conf` n'a pas changé (idempotence), le handler n'est pas déclenché et le service n'est pas redémarré inutilement.

---

## Partie G — Rôle `wazuh-server` : Installer le SIEM

Ce rôle accomplit l'installation la plus complexe et la plus longue du projet (~15 minutes).

### Étape 1 : Préparer le système pour Wazuh Indexer

Wazuh Indexer est basé sur **OpenSearch** (une version libre d'Elasticsearch). OpenSearch a des exigences système strictes :

- **Swap de 2 GB** : Le `c7i-flex.large` a seulement 4 GB de RAM. L'Indexer, le Manager et le Dashboard ensemble peuvent dépasser cette limite lors des pics de charge. Le swap est un filet de sécurité.
- **`vm.max_map_count = 262144`** : OpenSearch crée de nombreuses zones mémoire mappées virtuellement. Le noyau Linux interdit par défaut plus de 65 536 mappings. Sans ce paramètre, OpenSearch refuse de démarrer.

```yaml
- name: "Create 2GB swapfile"
  command: fallocate -l 2G /swapfile
  when: swap_check.stdout == ""   # Idempotent : ne crée le swap que s'il n'existe pas

- name: "Kernel parameter for OpenSearch"
  sysctl:
    name: vm.max_map_count
    value: "262144"
    state: present
    reload: yes
```

### Étape 2 : Installer Wazuh en mode All-in-One

Le script officiel Wazuh installe les trois composants sur une seule machine en une seule commande. C'est pratique pour un environnement de démonstration.

```yaml
- name: "Download install script"
  get_url:
    url: https://packages.wazuh.com/4.11/wazuh-install.sh
    dest: /tmp/wazuh-install.sh
    mode: '0755'

- name: "Run all-in-one installer (10-15 min)"
  command: bash /tmp/wazuh-install.sh -a -i
  async: 1200     # ← Délai max : 20 minutes (l'installation prend du temps)
  poll: 30        # ← Vérification du statut toutes les 30 secondes
```

> [!NOTE]
> `async` et `poll` sont des paramètres Ansible importants. Sans eux, une tâche longue qui dépasse le timeout SSH serait incorrectement marquée comme échouée. Avec `async: 1200`, Ansible lance la tâche en arrière-plan et vérifie son état toutes les 30 secondes.

### Étape 3 : Configurer l'enregistrement sécurisé des agents

Par défaut, n'importe quelle machine pourrait s'enregistrer auprès du Manager Wazuh. Pour éviter ça, Alice configure un **mot de passe d'authentification** que les agents devront fournir lors de leur inscription.

```yaml
# Activer l'authentification par mot de passe dans ossec.conf
- name: "Configure manager for agent registration"
  lineinfile:
    path: /var/ossec/etc/ossec.conf
    regexp: '<use_password>no</use_password>'
    line:   '    <use_password>yes</use_password>'

# Écrire le mot de passe dans le fichier dédié
- name: "Set agent registration password"
  copy:
    content: "pfs-soc-wazuh-2026"
    dest: /var/ossec/etc/authd.pass
    owner: root
    group: wazuh
    mode: '0640'    # Lisible uniquement par root et le groupe wazuh
```

### Étape 4 : Déployer les règles de détection personnalisées

Wazuh est livré avec des milliers de règles par défaut. Pour les besoins du projet, Alice crée des règles spécifiques aux attaques qu'elle va simuler. Ces règles sont stockées dans le fichier `custom_rules.xml` à l'intérieur du rôle (dans le dossier `files/`) et copiées sur le serveur :

```yaml
- name: "Deploy custom detection rules"
  copy:
    src: custom_rules.xml          # Fichier dans ansible/roles/wazuh-server/files/
    dest: /var/ossec/etc/rules/custom_rules.xml
    owner: root
    group: wazuh
    mode: '0640'
  notify: restart wazuh-manager    # Wazuh recharge ses règles au redémarrage
```

**Exemples de règles personnalisées et leur logique :**

| ID Règle | Attaque Détectée | Log Analysé | Déclencheur |
|---|---|---|---|
| 100001 | SQL Injection | dvwa-access.log | URL contient `UNION SELECT` ou `' OR '1'='1` |
| 100003 | Cross-Site Scripting | dvwa-access.log | URL contient `<script>` ou `alert(` |
| 100004 | Local File Inclusion | dvwa-access.log | URL contient `../etc/passwd` |
| 100010 | SSH Brute-Force | auth.log | Plus de 8 échecs d'authentification en 30s depuis la même IP |
| 100020 | Privilege Escalation | auth.log | Commande `sudo` utilisée par un utilisateur non-sudoer |
| 100043 | OS Command Injection | dvwa-access.log | Requête POST avec paramètres contenant `; id`, `; whoami`, `| cat` |

---

## Partie H — Rôle `dvwa` : Déployer l'Application Vulnérable

### L'enjeu technique : Logs Docker inaccessibles depuis le Host

DVWA tourne dans un **conteneur Docker** pour sa portabilité. Cela crée un problème : les logs Apache de l'application (`/var/log/apache2/access.log`) sont générés **à l'intérieur** du conteneur, dans son propre système de fichiers isolé. L'agent Wazuh, installé sur la **machine hôte** (l'instance EC2), ne peut pas voir ce fichier.

**Sans le forwarder :**
```
Conteneur Docker           Hôte EC2 (Ubuntu)
┌─────────────────────┐    ┌─────────────────────────────┐
│ /var/log/apache2/   │    │ /var/log/                   │
│   access.log ◄──────│    │   auth.log   ← Agent lit ✓  │
│   (invisible dehors)│    │   (pas de access.log ici)   │
└─────────────────────┘    │ Wazuh Agent                 │
                           │   ✗ Ne peut pas lire        │
                           │     les logs DVWA           │
                           └─────────────────────────────┘
```

**Avec le service `dvwa-log-forwarder` :**

Alice crée un service systemd sur le host qui fait le pont entre les deux mondes. Ce service utilise la commande `docker exec` pour lire les logs en continu depuis l'intérieur du conteneur et les écrire dans un fichier sur le host :

```bash
# Ce que fait le service en continu
docker exec dvwa tail -F /var/log/apache2/access.log >> /var/log/dvwa-access.log
```

```
Conteneur Docker           Hôte EC2 (Ubuntu)
┌─────────────────────┐    ┌──────────────────────────────────┐
│ /var/log/apache2/   │    │ /var/log/                        │
│   access.log ───────│───►│   dvwa-access.log ← Agent lit ✓  │
│   (docker exec)     │    │   (créé par dvwa-log-forwarder)  │
└─────────────────────┘    │ Wazuh Agent                      │
                           │   ✓ Lit et analyse les logs DVWA │
                           └──────────────────────────────────┘
```

Ce service est défini comme une **unité systemd** pour qu'il démarre automatiquement avec la machine et redémarre en cas de plantage :

```ini
[Unit]
Description=DVWA Docker Apache Log Forwarder for Wazuh
After=docker.service      # Démarrer après Docker
Requires=docker.service   # Ne pas démarrer sans Docker

[Service]
Type=simple
Restart=always            # Redémarrer automatiquement si le service plante
RestartSec=10
# Attendre que le conteneur dvwa soit UP avant de lancer le forwarder
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do docker ps | grep -q dvwa && exit 0; sleep 2; done; exit 1'
# Streamer les logs du conteneur vers le fichier sur le host
ExecStart=/bin/bash -c 'docker exec dvwa tail -F /var/log/apache2/access.log >> /var/log/dvwa-access.log'

[Install]
WantedBy=multi-user.target  # Démarrer lors du boot du système
```

---

## Partie I — Rôle `wazuh-agent` : Enregistrement et Configuration des Agents

### Étape 1 : Installer le package wazuh-agent

Le package Wazuh Agent est installé depuis le dépôt officiel Wazuh. L'adresse du Manager est passée comme variable d'environnement lors de l'installation pour pré-configurer l'agent :

```yaml
- name: "Install wazuh-agent"
  apt:
    name: wazuh-agent=4.11.2-1    # Version épinglée pour la reproductibilité
    state: present
  environment:
    WAZUH_MANAGER: "{{ wazuh_manager_ip }}"         # IP du Wazuh Server (via Peering)
    WAZUH_AGENT_NAME: "{{ wazuh_agent_name }}"      # Nom de l'agent dans la console
```

### Étape 2 : Configurer l'agent avec un template Jinja2

Le fichier de configuration de l'agent (`ossec.conf`) doit varier selon la machine : DVWA doit surveiller `/var/log/dvwa-access.log` (logs Docker forwardés), mais une autre machine surveillerait `/var/log/apache2/access.log` (logs Apache directs).

Alice utilise un **template Jinja2** (`.j2`) pour générer dynamiquement ce fichier de configuration selon les variables de la machine :

```xml
<!-- Template : ansible/roles/wazuh-agent/templates/ossec_agent.conf.j2 -->

<ossec_config>
  <client>
    <!-- {{ wazuh_manager_ip }} est remplacé par la vraie IP lors du déploiement -->
    <server>
      <address>{{ wazuh_manager_ip }}</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
  </client>

  <!-- File Integrity Monitoring : surveille les modifications de fichiers critiques -->
  <syscheck>
    <frequency>300</frequency>   <!-- Scan toutes les 5 minutes -->
    <!-- realtime="yes" : alerte immédiatement si /etc est modifié -->
    <directories check_all="yes" realtime="yes">/etc</directories>
    <directories check_all="yes" realtime="yes">/usr/bin,/usr/sbin</directories>
  </syscheck>

  <!-- Surveillance des logs d'authentification (brute-force SSH) -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <!-- Condition Jinja2 : bloc inclus UNIQUEMENT si is_dvwa_host = true -->
{% if is_dvwa_host | default(false) %}
  <!-- Logs Apache via Docker forwarder (spécifique à DVWA) -->
  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/dvwa-access.log</location>
  </localfile>
{% endif %}

  <!-- Active Response activée sur l'agent -->
  <active-response>
    <disabled>no</disabled>
  </active-response>
</ossec_config>
```

**Comment fonctionne Jinja2 ici ?** Ansible lit ce fichier `.j2` et remplace toutes les expressions `{{ variable }}` et `{% if %}...{% endif %}` par leurs valeurs réelles avant de copier le fichier sur la machine cible. C'est ce qui permet d'avoir un fichier de configuration différent sur DVWA et sur Metasploitable à partir d'un seul template.

### Étape 3 : Enregistrement sécurisé de l'agent

L'enregistrement de l'agent utilise le binaire `agent-auth` de Wazuh. Cet outil :
1. Se connecte au Manager sur le port 1515.
2. S'authentifie avec le mot de passe partagé (`pfs-soc-wazuh-2026`).
3. Reçoit en retour un certificat unique et un ID d'agent.
4. Stocke ces informations dans `/var/ossec/etc/client.keys`.

```yaml
- name: "Register agent with manager"
  shell: |
    /var/ossec/bin/agent-auth \
      -m {{ wazuh_manager_ip }} \
      -A {{ wazuh_agent_name }} \
      -P pfs-soc-wazuh-2026
```

**Le problème des ré-inscriptions :** Si Alice relance le Playbook une seconde fois (ce qui est fréquent en DevSecOps pour des mises à jour), l'agent essaie de s'enregistrer à nouveau sous le même nom. Le Manager refuse car il existe déjà un agent avec ce nom dans sa base SQLite (`agents.db`).

**La solution** : Alice nettoie l'ancienne entrée dans la base de données du Manager **avant** de tenter la nouvelle inscription. La tâche utilise `delegate_to` pour s'exécuter sur le serveur Wazuh, et non sur l'agent :

```yaml
- name: "Remove stale agent from Wazuh SQLite DB"
  shell: |
    AGENT_ID=$(sqlite3 /var/ossec/var/db/agents.db \
      "SELECT id FROM agent WHERE name='{{ wazuh_agent_name }}'")
    if [ -n "$AGENT_ID" ]; then
      sqlite3 /var/ossec/var/db/agents.db \
        "DELETE FROM agent WHERE id='$AGENT_ID';"
    fi
  # Cette tâche s'exécute SUR LE SERVEUR WAZUH, pas sur l'agent
  delegate_to: "{{ groups['soc'][0] }}"
```

---

## Partie J — L'Idempotence : Le Principe Fondamental d'Ansible

> [!IMPORTANT]
> L'**idempotence** signifie qu'exécuter le Playbook une fois ou dix fois produit exactement le même résultat. Alice peut relancer `ansible-playbook site.yml` à tout moment sans risque de corrompre les configurations déjà en place.

Ansible garantit l'idempotence par plusieurs mécanismes :

| Mécanisme | Exemple dans ce projet |
|---|---|
| `stat` + `when: not installed` | Wazuh n'est installé que si `/var/ossec/bin/wazuh-control` n'existe pas |
| `args: creates:` | Le script d'installation n'est relancé que si son résultat n'existe pas encore |
| `grep -q "marqueur"` | Le bloc de config SOC n'est ajouté à `ossec.conf` que s'il n'est pas déjà présent |
| Module `lineinfile` | Une ligne ne peut exister qu'une fois dans un fichier même si on l'applique plusieurs fois |

---

## Récapitulatif : Le flux complet d'exécution Ansible

```
ansible-playbook site.yml
        |
        ├─── PLAY 1 : wazuh-server
        │    ├── Attente SSH (jusqu'à 5 min)
        │    ├── Préparer le swap + paramètres noyau
        │    ├── Télécharger et installer Wazuh All-in-One (15 min)
        │    ├── Configurer l'authentification des agents
        │    ├── Déployer les règles de détection personnalisées
        │    ├── Appliquer la config Active Response
        │    └── Vérifier que le port 1514 est ouvert ✓
        │
        ├─── PLAY 2 : dvwa
        │    ├── Attente SSH
        │    ├── Installer Docker Engine
        │    ├── Démarrer le conteneur DVWA (port 80)
        │    ├── Créer l'utilisateur demouser avec mot de passe faible
        │    ├── Déployer le service dvwa-log-forwarder (systemd)
        │    └── Pause 45 secondes (stabilisation de la machine) ⏸
        │
        └─── PLAY 3 : wazuh-agent
             ├── Attente SSH (après stabilisation)
             ├── Installer le package wazuh-agent
             ├── Générer ossec.conf depuis le template Jinja2
             ├── Nettoyer l'ancienne entrée dans agents.db (sur le Manager)
             ├── Enregistrer l'agent auprès du Manager (agent-auth)
             ├── Démarrer le service wazuh-agent
             └── Vérification : lister les agents connectés ✓
```

---

## Prochaine Étape
Alice a maintenant une infrastructure complète et configurée. Elle peut se connecter à son Dashboard Wazuh et voir les deux agents enregistrés. Dans la **Phase 4 (CI/CD avec GitHub Actions)**, elle va automatiser tout ce cycle de déploiement pour que chaque modification du code déclenche automatiquement les phases Terraform et Ansible.

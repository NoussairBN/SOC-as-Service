# Guide Phase 5 — Simulation d'Attaques & Validation du SOC

Les quatre phases précédentes ont servi à construire l'infrastructure. La Phase 5 est la **démonstration** : Alice va jouer le rôle d'un attaquant, lancer de vraies techniques d'intrusion contre ses cibles vulnérables et observer en temps réel comment son SOC les détecte et y répond automatiquement.

C'est la phase la plus importante pour valider que le projet fonctionne de bout en bout.

---

## Partie A — Comprendre le Modèle de Menace

Avant de commencer les attaques, Alice doit comprendre la situation depuis le point de vue de chaque acteur.

### La position de l'Attaquant

Dans ce scénario, l'attaquant a déjà réussi à se faire une présence initiale dans le **Subnet Public** du VPC Client. Dans la vraie vie, cela pourrait représenter :
- Un employé malveillant avec accès réseau interne.
- Un attaquant externe ayant compromis une première machine.

Alice simule cela en se connectant au **Bastion Host** (sa position d'attaquant) puis en ciblant les machines du Subnet Privé.

### La position du Défenseur (SOC)

Le SOC d'Alice collecte silencieusement les logs de toutes les machines cibles via les agents Wazuh. Le **Wazuh Manager** analyse ces logs en temps réel et compare chaque ligne avec les règles de détection. Le **Wazuh Dashboard** est l'écran de surveillance où l'analyste SOC voit les alertes.

### Le Scénario de la Démonstration

```
Alice (Attaquant)          Alice (Défenseur)
      │                           │
      │ SSH sur Bastion           │ Ouvre le Dashboard Wazuh
      │ (machine d'attaque)       │ (écran de surveillance)
      │                           │
      ▼                           ▼
Depuis le Bastion :         Dashboard Wazuh :
 → Scan réseau              → Alertes en temps réel
 → Brute-force SSH          → Niveau de sévérité
 → Injection SQL/XSS        → IP source de l'attaquant
 → Command Injection        → Règle déclenchée
                            → Active Response : BAN IP
```

---

## Partie B — Préparation : Accès aux Outils de Surveillance

### Étape 1 : Ouvrir le Dashboard Wazuh

Avant de commencer les attaques, Alice ouvre son navigateur sur :
```
https://<WAZUH_PUBLIC_IP>
```

Les identifiants par défaut sont `admin` et le mot de passe généré lors de l'installation (visible dans les logs du pipeline Ansible, ou récupérable sur le serveur).

Sur le Dashboard, Alice navigue vers **Security Events** (Évènements de Sécurité) pour voir les alertes en temps réel.

### Étape 2 : Se connecter au Bastion (position d'attaquant)

```bash
ssh -i ~/.ssh/pfs-soc-key ubuntu@<IP_PUBLIQUE_BASTION>
```

Alice est maintenant sur la machine d'attaque. Toutes les attaques seront lancées depuis cet hôte.

---

## Partie C — Attaque 1 : Reconnaissance réseau (Scan Nmap)

### Ce qu'est le scan de port

Avant d'attaquer, un vrai attaquant fait une phase de **reconnaissance**. Il utilise `nmap` pour découvrir quelles machines sont actives et quels services sont exposés sur le réseau.

### Lancer le scan depuis le Bastion

```bash
# Depuis le Bastion, scanner le sous-réseau privé (10.0.2.0/24)
nmap -sV -p 22,80,21,23 10.0.2.0/24
```

Les options utilisées :
- `-sV` : Détecter la version des services (ex: OpenSSH 8.9p1)
- `-p 22,80,21,23` : Scanner spécifiquement SSH, HTTP, FTP et Telnet

### Ce que Wazuh détecte

Le scan génère des tentatives de connexion sur différents ports qui apparaissent dans les logs système. Wazuh peut alerter sur des scans de ports avec ses règles intégrées (famille de règles 40000+) si plusieurs connexions refusées arrivent en rafale depuis la même IP.

---

## Partie D — Attaque 2 : Brute-Force SSH sur Metasploitable

### Comprendre le Brute-Force SSH

Un brute-force SSH consiste à tester automatiquement des milliers de combinaisons identifiant/mot de passe sur un service SSH jusqu'à en trouver une valide. C'est l'une des attaques les plus courantes et les plus détectables.

Alice utilise l'outil **Hydra** (pré-installé sur le Bastion) avec une wordlist de mots de passe courants.

### Lancer l'attaque depuis le Bastion

```bash
# Depuis le Bastion, brute-forcer SSH sur Metasploitable
hydra -l demouser \
      -P /usr/share/wordlists/fasttrack.txt \
      ssh://10.0.2.x    # Remplacer par l'IP de Metasploitable
```

Ce qui se passe en coulisse :
1. Hydra génère des centaines de tentatives de connexion SSH par minute.
2. Chaque tentative échouée génère une ligne dans `/var/log/auth.log` de Metasploitable :
   ```
   Failed password for demouser from 10.0.1.21 port 54832 ssh2
   ```
3. L'agent Wazuh de Metasploitable lit ce fichier en continu et envoie chaque ligne au Manager.
4. Le Manager compare contre la règle 100010 :

```xml
<!-- Règle 100010 : SSH Brute Force -->
<rule id="100010" level="10" frequency="8" timeframe="30">
  <if_matched_sid>5716</if_matched_sid>  <!-- Règle parente : échec SSH -->
  <description>SSH Brute Force: 8 failed logins in 30 seconds</description>
  <group>authentication_failures,pci_dss_10.6.1,gpg13_7.1</group>
</rule>
```

**Traduction de la règle :** Si la règle de base 5716 (échec d'authentification SSH) est déclenchée **8 fois ou plus** dans une fenêtre de **30 secondes** par la même source, déclencher l'alerte de niveau 10 "SSH Brute Force".

### Ce qui se passe côté SOC

Sur le Dashboard Wazuh, Alice voit apparaître :
- Des dizaines d'alertes de niveau 5 (tentatives individuelles) puis...
- Une alerte de niveau **10** : `SSH Brute Force` avec l'IP du Bastion comme source

### La Réponse Active — Le moment clé

À ce moment précis, la règle 100010 déclenche une **Active Response**. Wazuh ordonne à l'agent de Metasploitable d'exécuter le script `firewall-drop.sh` avec l'IP source comme argument :

```bash
# Ce script s'exécute AUTOMATIQUEMENT sur Metasploitable
# Il ajoute l'IP du Bastion à la liste de blocage du pare-feu
iptables -A INPUT -s 10.0.1.21 -j DROP   # L'IP du Bastion est bannie
```

**Comment Alice vérifier que l'Active Response a fonctionné ?**

Depuis le Bastion, elle essaie de pinguer Metasploitable :
```bash
ping 10.0.2.x   # Timeout : aucune réponse
```

La connexion est coupée. L'Active Response a fonctionné. Alice s'est elle-même bannie.

---

## Partie E — Attaque 3 : Injections Web sur DVWA

DVWA (Damn Vulnerable Web Application) est accessible depuis le Bastion sur son port 80. Alice peut y lancer des attaques web directement depuis le terminal ou depuis un navigateur via un tunnel SSH.

### Comprendre le flux de détection des attaques web

```
Alice (Bastion)       DVWA (10.0.2.y)           Wazuh
     │                      │                      │
     │ GET /vulns/sqli?id='  │                      │
     │  UNION SELECT 1,2--   │                      │
     │──────────────────────>│                      │
     │                       │ Log Apache :         │
     │                       │ GET /sqli?id=' UNION │
     │                       │──────────────────────>│
     │                       │                      │ Analyse règle 100001
     │                       │                      │ → ALERTE SQL Injection !
```

### Attaque 3a : SQL Injection

Une injection SQL consiste à insérer du code SQL dans un champ de saisie pour manipuler la base de données. C'est l'une des vulnérabilités OWASP les plus critiques.

```bash
# Depuis le Bastion, simuler une requête d'injection SQL
curl "http://10.0.2.y/vulnerabilities/sqli/?id=%27%20UNION%20SELECT%201%2C2--+&Submit=Submit" \
  -H "Cookie: security=low; PHPSESSID=abcdef"
```

Ce que génère cette requête dans les logs Apache :
```
10.0.1.21 - - [07/Jul/2026:14:00:00 +0000] "GET /vulnerabilities/sqli/?id=' UNION SELECT 1,2-- HTTP/1.1" 200 1845
```

La règle de détection correspondante :
```xml
<!-- Règle 100001 : SQL Injection détectée dans les logs Apache -->
<rule id="100001" level="12">
  <if_group>web|accesslog</if_group>
  <url_pcre2>(?i)(UNION\s+SELECT|OR\s+'1'='1|DROP\s+TABLE|INSERT\s+INTO)</url_pcre2>
  <description>DVWA SQL Injection attempt detected</description>
  <group>web,attack,sql_injection</group>
</rule>
```

### Attaque 3b : Cross-Site Scripting (XSS)

Le XSS consiste à injecter du JavaScript malveillant dans une page web pour qu'il s'exécute dans le navigateur d'une victime.

```bash
curl "http://10.0.2.y/vulnerabilities/xss_r/?name=%3Cscript%3Ealert%28%27HACKED%27%29%3C%2Fscript%3E" \
  -H "Cookie: security=low; PHPSESSID=abcdef"
```

Ce que génère cette requête dans les logs :
```
GET /vulnerabilities/xss_r/?name=<script>alert('HACKED')</script> HTTP/1.1
```

### Attaque 3c : Local File Inclusion (LFI)

Le LFI permet à un attaquant de lire des fichiers système sensibles du serveur (comme `/etc/passwd`) en manipulant les paramètres d'URL.

```bash
curl "http://10.0.2.y/vulnerabilities/fi/?page=../../../../etc/passwd" \
  -H "Cookie: security=low; PHPSESSID=abcdef"
```

### Attaque 3d : OS Command Injection

La plus dangereuse : elle permet d'exécuter des commandes système arbitraires sur le serveur.

```bash
# DVWA exécute cette commande sur le serveur Linux sous-jacent
curl -X POST "http://10.0.2.y/vulnerabilities/exec/" \
  -d "ip=127.0.0.1; id" \
  -H "Cookie: security=low; PHPSESSID=abcdef"
```

Le payload `; id` force le serveur à exécuter la commande `id` en plus du ping légitime, révélant l'identité de l'utilisateur qui fait tourner le serveur web.

---

## Partie F — Tester les Règles sans lancer d'Attaque : `wazuh-logtest`

Pendant le développement de ses règles, Alice ne voulait pas déclencher des vraies attaques pour tester si une règle fonctionnait. Wazuh fournit l'outil `wazuh-logtest` qui simule l'analyse d'une ligne de log sans la générer réellement.

**Utilisation sur le Wazuh Server :**

```bash
# Se connecter sur le Wazuh Server via le Bastion
ssh -i ~/.ssh/pfs-soc-key -J ubuntu@<BASTION_IP> ubuntu@10.1.1.x

# Tester une ligne de log XSS
echo '10.0.1.21 - - [07/Jul/2026:14:00:00 +0000] "GET /vulnerabilities/xss_r/?name=<script>alert(1)</script> HTTP/1.1" 200 1780' \
  | /var/ossec/bin/wazuh-logtest
```

**La sortie de `wazuh-logtest` :**
```
Type one log per line

Phase 1: Completed pre-decoding.
    full event: '10.0.1.21 - - ... "GET /vulnerabilities/xss_r/?name=<script>...'

Phase 2: Completed decoding.
    decoder: 'apache-access'
    srcip: '10.0.1.21'
    url: '/vulnerabilities/xss_r/?name=<script>alert(1)</script>'

Phase 3: Completed filtering (rules).
    id: '100003'
    level: '11'
    description: 'DVWA XSS (Cross-Site Scripting) attempt detected'
    groups: ['web', 'attack', 'xss']
**Alert to be generated.
```

Cet outil est extrêmement précieux : il permet de voir exactement comment Wazuh décode et interprète une ligne de log, et quelle règle sera déclenchée, sans aucun risque.

---

## Partie G — Validation Complète : La Checklist du SOC

À l'issue des tests, Alice doit valider que chaque composant du SOC fonctionne correctement.

| Test | Commande / Action | Résultat Attendu |
|---|---|---|
| Agents connectés | Sur Wazuh Server : `/var/ossec/bin/agent_control -l` | Liste `dvwa-apache` et `metasploitable` comme ACTIVE |
| Réception des logs | Dashboard → Security Events | Voir des events des agents |
| Brute-force SSH | Hydra depuis Bastion sur Metasploitable | Alerte Règle 100010 (niveau 10) sur le Dashboard |
| Active Response | Continuer après l'alerte brute-force | `ping 10.0.2.x` timeout depuis le Bastion |
| SQL Injection | curl avec payload UNION SELECT | Alerte Règle 100001 (niveau 12) sur le Dashboard |
| XSS | curl avec payload `<script>` | Alerte Règle 100003 (niveau 11) sur le Dashboard |
| LFI | curl avec `../../../../etc/passwd` | Alerte Règle 100004 (niveau 11) sur le Dashboard |
| Command Injection | curl POST avec `; id` | Alerte Règle 100043 (niveau 12) sur le Dashboard |
| FIM (Fichiers) | Sur DVWA : `sudo touch /etc/test_file` | Alerte syscheck (modification de /etc) |

### Vérifier l'état de l'Active Response

Pour voir les actions de blocage qui ont eu lieu, Alice peut consulter le log de l'Active Response sur le Wazuh Server :

```bash
sudo tail -f /var/ossec/logs/active-responses.log
```

Exemple de sortie attendue :
```
Mon Jul 07 14:05:32 2026 /var/ossec/active-response/bin/firewall-drop add - 10.0.1.21 1625661932.12345 100010
```

### Vérifier que l'IP est bien bannie sur la cible

Sur la machine Metasploitable (accessible via le Wazuh Server si le Bastion est banni) :

```bash
sudo iptables -L INPUT -n --line-numbers | grep DROP
```

Sortie attendue :
```
1    DROP    all  --  10.0.1.21   0.0.0.0/0
```

---

## Partie H — Destruction de l'Infrastructure après la Démonstration

Une fois la démonstration terminée, Alice doit **obligatoirement** supprimer toutes les ressources AWS pour éviter des frais continus. Le coût estimé est de ~8$ pour 3 jours de run complet.

### Via GitHub Actions (méthode recommandée)

1. Aller sur `GitHub → Actions → Deploy SOC Infrastructure → Run workflow`
2. Choisir l'action **`destroy`**
3. Cliquer sur **Run workflow**

Terraform supprimera toutes les ressources dans l'ordre inverse de leur création (les dépendances sont respectées automatiquement).

### Vérification après destruction

Alice peut vérifier que rien ne tourne encore sur AWS :
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=pfs-soc" \
  --query "Reservations[].Instances[].State.Name" \
  --profile pfs-soc
```

La réponse doit être une liste vide `[]` ou uniquement des états `terminated`.

> [!CAUTION]
> Le Bucket S3 et la table DynamoDB du backend **ne sont pas supprimés** par `terraform destroy`. Ils contiennent l'historique de l'état de l'infrastructure. Alice doit les supprimer manuellement depuis la console AWS si elle souhaite effacer toute trace du projet.

---

## Récapitulatif Final : Le Cycle de Vie Complet du Projet

```
Phase 1 : Prérequis & Environnement
  → AWS CLI configuré, Terraform installé, Ansible sous WSL, clé SSH générée

Phase 2 : Bootstrap & Terraform
  → S3 + DynamoDB créés (backend), code IaC écrit
  → VPCs, Peering, Security Groups, instances EC2 provisionnés

Phase 3 : Ansible
  → Wazuh Server installé (Manager + Indexer + Dashboard)
  → DVWA déployé sous Docker + dvwa-log-forwarder
  → Agents Wazuh enregistrés sur les cibles

Phase 4 : CI/CD GitHub Actions
  → Scan Shift-Left (Checkov + tfsec) à chaque commit
  → Pipeline automatisé : push → Terraform → Ansible → Résumé

Phase 5 : Simulation & Validation
  → Brute-Force SSH détecté → Active Response : IP bannie en < 30s
  → SQL Injection, XSS, LFI, Command Injection détectés sur DVWA
  → File Integrity Monitoring valide

Destroy : terraform destroy → Infrastructure supprimée proprement
```

---

## Conclusion : Ce que ce Projet Démontre

À travers les cinq phases, Alice a construit et validé plusieurs compétences DevSecOps clés :

| Compétence | Technologie | Phase |
|---|---|---|
| Infrastructure as Code | Terraform | 2 |
| Segmentation réseau | AWS VPC, Peering, Security Groups | 2 |
| Configuration Management | Ansible, Jinja2, Roles | 3 |
| SIEM et détection | Wazuh Manager, Règles personnalisées | 3 |
| Réponse automatisée | Wazuh Active Response | 3 & 5 |
| CI/CD sécurisé | GitHub Actions, Secrets | 4 |
| Shift-Left Security | Checkov, tfsec | 4 |
| Simulation d'attaques | Hydra, curl, nmap | 5 |
| Analyse forensique | wazuh-logtest, iptables | 5 |

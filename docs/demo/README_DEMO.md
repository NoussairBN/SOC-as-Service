# Démonstrations Vidéo — SOC-as-Code

Ce dossier contient les vidéos de démonstration du projet **SOC-as-Code (PFS)**.

> [!NOTE]
> Les fichiers `.mp4` ne sont **pas versionnés** dans Git (taille > 100 MB, limite GitHub).
> Ils sont stockés localement et doivent être copiés manuellement dans ce dossier.

---

## Vidéo 1 — `demo_wazuh_dashboard.mp4` (~292 MB)

**Enregistrée le :** 11 Juin 2026 à 21:23

**Contenu :**
- Connexion au Dashboard Wazuh (`https://<WAZUH_IP>`)
- Navigation dans l'interface : Security Events, Agents, Modules
- Vue d'ensemble de l'infrastructure déployée (2 agents connectés : `dvwa-apache` et `metasploitable`)
- Présentation des règles de détection personnalisées (IDs 100001–100043)

---

## Vidéo 2 — `demo_attack_detection.mp4` (~124 MB)

**Enregistrée le :** 11 Juin 2026 à 21:44

**Contenu :**
- Connexion SSH sur le Bastion Host (position de l'attaquant)
- **Attaque 1** : Brute-Force SSH avec Hydra sur Metasploitable
  - Observation des alertes en temps réel sur le Dashboard
  - Déclenchement de l'**Active Response** (ban automatique de l'IP)
  - Vérification que l'IP est bannie (`iptables -L`)
- **Attaque 2** : Injection SQL sur DVWA (`UNION SELECT`)
  - Alerte Règle 100001 (niveau 12) sur le Dashboard
- **Attaque 3** : XSS sur DVWA (`<script>alert()`)
  - Alerte Règle 100003 (niveau 11) sur le Dashboard

---

## Comment reproduire les démonstrations

Se référer au **[Guide Phase 5](../guide_phase_5.md)** pour le détail de chaque scénario d'attaque et de validation.

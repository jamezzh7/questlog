# Confidentialité et données locales

Mise à jour : 25 octobre 2026. [English](privacy.md) · [简体中文](privacy.zh-CN.md)

Questlog est maintenu par jamezzh7. L’app ne possède ni compte, ni outil d’analyse, ni publicité, ni intégration de modèle, ni serveur distant. Elle ne collecte et n’envoie aucune donnée au développeur.

Elle lit les listes Markdown connectées, les plans explicitement liés à l’intérieur du projet, les métadonnées nécessaires à l’actualisation et, dans la vue détaillée, une sélection limitée de documents et de métadonnées de commits Git. Elle ne lit pas les conversations. Le contexte est limité à quatre extraits, à 2 Mo par document et à 1 600 caractères par extrait. Tout contenu privé placé dans un document sélectionné peut apparaître dans l’interface.

La version Mac App Store demande de choisir un dossier dans la boîte de dialogue système avant d’obtenir un accès en lecture seule. Les index Codex / Claude Code nécessitent une sélection distincte ; autoriser un index n’autorise pas les dossiers qu’il référence. Les autorisations peuvent être conservées localement au moyen de signets à portée de sécurité. Les projets et les index des outils ne sont pas modifiés.

Les connexions, listes sélectionnées, périmètres, estimations, heures disponibles et préférences de langue et d’apparence, périmètres et objectifs simples restent sur le Mac. La version du store utilise son propre conteneur et un dossier QuestlogStore, avec les autorisations enregistrées séparément. La version installée depuis les sources utilise `~/Library/Application Support/Questlog/projects.json` ; le lanceur de développement utilise un fichier du dépôt. WebKit peut conserver des préférences de vue locales.

Réglages → Réinitialiser les autorisations oublie tous les accès aux dossiers et index, puis cesse de les utiliser. Les connexions et estimations sont conservées ; il faut choisir de nouveau un dossier pour reprendre sa lecture. Retirer une connexion supprime ses réglages de suivi, en conservant les fichiers du projet. Les autres préférences locales restent jusqu’à leur suppression. Il n’existe aucune copie serveur ni compte distant à supprimer.

La version du store embarque son environnement et utilise une passerelle au sein du processus, sans serveur HTTP local. WebKit exige la capacité de connexion sortante de macOS pour lancer son moteur, mais la page intégrée bloque les requêtes et navigations distantes. La version depuis les sources lance un service sur `127.0.0.1` uniquement pour la vue détaillée, avec vérification de l’origine des écritures JSON.

Les liens vers la politique ou l’aide s’ouvrent dans le navigateur. GitHub traite ces visites selon sa propre politique. Les informations que vous soumettez volontairement dans une demande d’aide sont envoyées à GitHub ; les tickets publics sont visibles par tous. Excluez les projets privés, identifiants et captures non expurgées. Les services du store et les diagnostics système facultatifs relèvent séparément des politiques d’Apple.

Pour toute question, consultez l’[aide](support.md). Pour un problème de sécurité sensible, utilisez un [signalement privé](https://github.com/jamezzh7/questlog/security/advisories/new). Toute modification de cette politique sera publiée ici avec une nouvelle date.

Sans structure de tâches, la mini-fenêtre et la barre des menus lisent les états explicites de quatre documents de projet connus au maximum. L’activité Git reste limitée à la vue de détails.

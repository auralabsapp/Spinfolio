# Tests manuels — Spinfolio (Spinlog)

Référence unique des tests à passer sur appareil (remplace `Spinfolio_Cahier_de_test.pdf` et `index.html`).
Les tests sont rangés par famille et numérotés : lettre de la famille + numéro (A1, A2…). Un numéro n'est jamais réattribué.

**Étiquettes** : `AUDIT` = ajouté lors d'une branche de fiabilisation ou d'une fonctionnalité récente, à passer en priorité ; `AUTO` = logique déjà couverte par les tests automatiques Xcode, le passage manuel peut se limiter au rendu et à ce que ces tests ne voient pas.

Pour noter un résultat : cocher la case et indiquer la date, l'appareil, la version et, en cas d'échec, une capture.

Total : 575 tests.

## Sommaire

- [A — Authentification & gestion de compte](#famille-a) (31)
- [B — Collection — Consultation & navigation standard](#famille-b) (53)
- [C — Collection — Sélection multiple & actions groupées](#famille-c) (18)
- [D — Rangement physique (Shelf placement)](#famille-d) (11)
- [E — Wantlist — Standard](#famille-e) (26)
- [F — Wantlist — Sélection multiple & alertes de prix](#famille-f) (24)
- [G — Recherche & Scan](#famille-g) (30)
- [H — Fiche détail d'un release](#famille-h) (38)
- [I — Statistiques](#famille-i) (31)
- [J — Réglages — Général](#famille-j) (44)
- [K — Réglages — Export & sauvegarde](#famille-k) (13)
- [L — Premium — Paywall, achat, restauration, dégradation](#famille-l) (38)
- [M — Synchronisation iCloud](#famille-m) (31)
- [N — Mode hors ligne](#famille-n) (29)
- [O — Widgets & Live Activity](#famille-o) (24)
- [P — Cas transverses / non-fonctionnel](#famille-p) (41)
- [Q — Lecture Apple Music (mini-lecteur & connexion de compte)](#famille-q) (33)
- [R — Mise à jour & migration de données](#famille-r) (8)
- [S — Langues, libellés & traductions](#famille-s) (14)
- [T — Guide de l'app (Réglages > Guide)](#famille-t) (27)
- [U — Grades et badges](#famille-u) (11)

<a id="famille-a"></a>

## A — Authentification & gestion de compte

### A1 — Connexion initiale (premier lancement)

**Conditions** : App fraîchement installée, aucune session Discogs enregistrée, réseau disponible.

**Étapes** :

1. Lancer l'app.
2. Suivre l'écran de connexion Discogs (OAuth).
3. Autoriser l'app sur le site Discogs.
4. Revenir dans l'app.

**Résultat attendu** : L'app revient au premier plan et affiche la Collection de l'utilisateur connecté ; le nom d'utilisateur apparaît dans Réglages.

- [ ] Passé — date / appareil / version :

### A2 — Déconnexion

**Conditions** : Utilisateur connecté.

**Étapes** :

1. Réglages → Se déconnecter.
2. Confirmer dans la boîte de dialogue « Se déconnecter ».

**Résultat attendu** : Retour à l'écran de connexion ; plus aucune donnée de l'ancien compte visible ; les identifiants ne sont plus dans le Keychain.

- [ ] Passé — date / appareil / version :

### A3 — Reconnexion avec le même compte

**Conditions** : Venir de se déconnecter (A2).

**Étapes** :

1. Se reconnecter avec le même compte Discogs.

**Résultat attendu** : Collection, wantlist, tags et préférences de tri/filtres reviennent comme avant la déconnexion (iCloud si premium) ou sont ré-importés depuis Discogs (si non premium).

- [ ] Passé — date / appareil / version :

### A4 — Changement de compte (compte A → compte B)

**Conditions** : Connecté avec le compte A ; disposer d'un compte B avec des données différentes.

**Étapes** :

1. Se déconnecter du compte A.
2. Se connecter avec le compte B.

**Résultat attendu** : Toutes les données affichées (collection, wantlist, tags, préférences, dossiers) appartiennent exclusivement au compte B ; aucune trace résiduelle du compte A.

- [ ] Passé — date / appareil / version :

### A5 — Session révoquée côté Discogs

**Conditions** : App connectée localement.

**Étapes** :

1. Révoquer l'autorisation de l'app depuis Discogs.com (Réglages → Applications autorisées → Révoquer).
2. Revenir dans l'app et déclencher un appel réseau (tirer pour rafraîchir la Collection).

**Résultat attendu** : L'app détecte l'erreur d'authentification et invite à se reconnecter ; pas de crash, pas de boucle de requêtes.

- [ ] Passé — date / appareil / version :

### A6 — Connexion sans réseau

**Conditions** : Mode avion activé, aucune session existante.

**Étapes** :

1. Lancer l'app.
2. Tenter de se connecter.

**Résultat attendu** : Message d'erreur clair indiquant l'absence de réseau ; pas de crash.

- [ ] Passé — date / appareil / version :

### A7 — Révocation pendant une opération en cours `LIMITE`

**Conditions** : Un envoi iCloud ou un appel Discogs est en cours.

**Étapes** :

1. Révoquer l'autorisation Discogs au milieu de l'opération.

**Résultat attendu** : L'opération en cours échoue proprement (message d'erreur ou retry), aucun état incohérent persisté localement.

- [ ] Passé — date / appareil / version :

### A8 — Connexion à un compte sans aucune collection `LIMITE`

**Conditions** : Compte Discogs test avec 0 album et 0 élément en wantlist.

**Étapes** :

1. Se connecter avec ce compte.

**Résultat attendu** : États vides corrects sur Collection et Wantlist (pas de crash, message « Collection vide » adapté), Stats n'affiche aucun graphique cassé.

- [ ] Passé — date / appareil / version :

### A9 — Déconnexion pendant une synchro iCloud en cours `LIMITE` `PREMIUM`

**Conditions** : Compte premium, synchro iCloud en cours d'envoi.

**Étapes** :

1. Se déconnecter pendant que ` sentRecordZoneChanges` est en cours.

**Résultat attendu** : La synchro s'arrête proprement (`stop()`), aucun crash, l'état est repris correctement à la reconnexion.

- [ ] Passé — date / appareil / version :

### A10 — Double appui sur « Se connecter » `LIMITE`

**Conditions** : Écran de connexion affiché.

**Étapes** :

1. Taper rapidement deux fois sur le bouton de connexion.

**Résultat attendu** : Une seule session OAuth démarrée, pas de double callback ni d'état de connexion incohérent.

- [ ] Passé — date / appareil / version :

### A11 — Callback OAuth annulé par l'utilisateur `LIMITE`

**Conditions** : Flux OAuth lancé dans Safari.

**Étapes** :

1. Annuler/fermer l'onglet Safari avant d'autoriser l'app.

**Résultat attendu** : Retour à l'écran de connexion sans erreur bloquante ; nouvel essai possible immédiatement.

- [ ] Passé — date / appareil / version :

### A12 — Horloge système décalée pendant le flux OAuth `LIMITE`

**Conditions** : Date/heure de l'appareil réglée dans le passé ou le futur avant la connexion.

**Étapes** :

1. Modifier la date système.
2. Lancer le flux de connexion Discogs.

**Résultat attendu** : La connexion réussit ou échoue avec un message clair ; pas de session « expirée » immédiatement après une connexion réussie.

- [ ] Passé — date / appareil / version :

### A13 — Échec réseau juste après l'autorisation Discogs `AUDIT` `LIMITE`

**Conditions** : Aucune session existante, réseau disponible au départ.

**Étapes** :

1. Lancer la connexion et autoriser l'app sur Discogs.
2. Activer le mode avion au moment exact du retour dans l'app.
3. Fermer l'app (balayage), désactiver le mode avion, relancer.

**Résultat attendu** : Message « Impossible de se connecter à Discogs » ; au relancement, l'écran de connexion s'affiche. Jamais d'état « connecté » sans nom d'utilisateur où rien ne se charge.

- [ ] Passé — date / appareil / version :

### A14 — Changement de compte pendant le chargement de la collection `AUDIT` `RÉGRESSION` `LIMITE`

**Conditions** : Compte A avec une grande collection (plusieurs pages), compte B différent.

**Étapes** :

1. Avec le compte A, tirer pour rafraîchir la collection (dossier « Tous »).
2. Pendant que les pages se chargent, se déconnecter puis se connecter immédiatement au compte B.
3. Attendre la fin du chargement, puis relancer l'app.

**Résultat attendu** : Aucun disque du compte A n'apparaît chez le compte B, ni pendant le chargement ni après relancement (cache local non mélangé).

- [ ] Passé — date / appareil / version :

### A15 — Reconnexion après une session de connexion avortée `AUDIT` `LIMITE`

**Conditions** : Écran de connexion affiché.

**Étapes** :

1. Lancer la connexion puis la faire échouer (annuler, ou verrouiller l'iPhone pendant l'ouverture de la page Discogs).
2. Toucher à nouveau « Se connecter ».

**Résultat attendu** : Le bouton reste utilisable : une nouvelle session de connexion démarre, sans devoir relancer l'app (plus de bouton figé « en cours »).

- [ ] Passé — date / appareil / version :

### A16 — Explorer la collection de démo depuis l'écran de connexion `AUDIT` `AUTO`

**Conditions** : App fraîchement installée ou déconnectée, réseau disponible.

**Étapes** :

1. Sur l'écran de connexion (onglet Collection), toucher « Explorer avec une collection de démo ».
2. Parcourir Collection, Wantlist et Stats.

**Résultat attendu** : La collection d'exemple s'affiche immédiatement (44 disques), la Wantlist (12 souhaits) et les Stats se remplissent. Aucun compte Discogs demandé.

- [ ] Passé — date / appareil / version :

### A17 — Quitter le mode démo `AUDIT` `AUTO`

**Conditions** : Mode démo actif, quelques tags ajoutés et une écoute lancée.

**Étapes** :

1. Réglages → « Quitter le mode démo ».
2. Revenir sur Collection, puis relancer la démo.

**Résultat attendu** : Retour à l'écran de connexion. À la relance, la démo repart de zéro : tags et écoutes ajoutés précédemment effacés.

- [ ] Passé — date / appareil / version :

### A18 — Démo non conservée après fermeture de l'app `AUDIT`

**Conditions** : Mode démo actif.

**Étapes** :

1. Fermer l'app depuis le sélecteur d'apps (balayage).
2. La rouvrir.

**Résultat attendu** : L'app s'ouvre sur l'écran de connexion habituel (qui propose la démo), pas sur la collection de démo. Le widget « Album du jour » ne propose plus de disque de la démo.

- [ ] Passé — date / appareil / version :

### A19 — Se connecter à Discogs depuis la démo `AUDIT`

**Conditions** : Mode démo actif, compte Discogs réel disponible.

**Étapes** :

1. Réglages → section Compte → « Se connecter à Discogs ».
2. Terminer la connexion OAuth.

**Résultat attendu** : La démo est quittée puis la vraie collection du compte se charge ; aucune donnée d'exemple ne s'y mélange. Si la connexion est annulée, l'app revient à l'écran de connexion.

- [ ] Passé — date / appareil / version :

### A20 — Déconnexion : plus aucun traitement pour l'ancien compte `AUDIT`

**Conditions** : Compte connecté, premium : téléchargement hors ligne en cours, écoute sur platine et lecture Apple Music lancées, au moins une alerte de prix avec notification reçue.

**Étapes** :

1. Se déconnecter.
2. Observer la Live Activity, le lecteur, le centre de notifications et le widget pendant quelques minutes.

**Résultat attendu** : Téléchargement interrompu, écoute et lecture arrêtées, notifications d'alerte de ce compte retirées, widget vidé ; aucune nouvelle notification ni requête pour l'ancien compte (Console : aucun appel Discogs après la déconnexion).

- [ ] Passé — date / appareil / version :

### A21 — Supprimer mon compte : tout est effacé, iCloud compris `AUDIT` `PREMIUM` `DEV`

**Conditions** : Compte premium avec tags, écoutes, alertes, préférences personnalisées, une action hors ligne en attente et une synchro iCloud active.

**Étapes** :

1. Réglages → Supprimer mon compte → Effacer les données de l'app… → retaper le nom d'utilisateur → Effacer définitivement mes données.
2. Vérifier dans CloudKit Dashboard la zone `account-<compte>`.
3. Se reconnecter avec le même compte.

**Résultat attendu** : La zone iCloud est supprimée et n'est pas recréée ; au retour, ni tags, ni écoutes, ni alertes, ni préférences, ni action en attente ; Réglages → Mode hors ligne n'affiche plus de date de dernière synchro.

- [ ] Passé — date / appareil / version :

### A22 — Connexion : le retour de Discogs est vérifié `AUDIT` `AUTO`

**Conditions** : Aucune session, réseau disponible.

**Étapes** :

1. Se connecter à Discogs et autoriser l'app.
2. Se déconnecter, relancer la connexion, puis annuler sur la page Discogs.

**Résultat attendu** : La connexion aboutit normalement (le code de retour de Discogs correspond bien à la demande en cours) ; l'annulation ramène à l'écran de connexion sans erreur bloquante.

- [ ] Passé — date / appareil / version :

### A23 — Créer un compte Discogs depuis l'app `AUDIT`

**Conditions** : App déconnectée (écran « Connecte-toi à Discogs » de Collection, Wantlist ou Stats, ou Réglages → Compte Discogs), adresse e-mail jamais utilisée sur Discogs.

**Étapes** :

1. Toucher « Pas de compte ? Crée-en un » (écran de connexion, puis refaire depuis Réglages).
2. Remplir le formulaire d'inscription Discogs, puis confirmer l'adresse e-mail.
3. Fermer la webview, toucher « Se connecter » et se connecter avec ce nouveau compte.
4. Rouvrir le lien plus tard (le lendemain) pour vérifier qu'il fonctionne toujours.

**Résultat attendu** : La webview ouvre directement le formulaire d'inscription Discogs (pas de page d'erreur « state » expiré ni de page d'accueil). Après inscription, la connexion OAuth aboutit et la collection (vide) s'affiche. Le lien fonctionne encore les jours suivants.

- [ ] Passé — date / appareil / version :

### A24 — Fermer la fenêtre de connexion sans se connecter `AUDIT` `AUTO`

**Conditions** : App déconnectée (première ouverture ou après déconnexion).

**Étapes** :

1. Toucher « Se connecter », puis fermer la fenêtre de connexion Discogs sans rien saisir (bouton de fermeture, glissé).
2. Refaire en touchant « Annuler » dans la demande « … souhaite utiliser discogs.com pour se connecter ».
3. Toucher de nouveau « Se connecter » et aller jusqu'au bout.

**Résultat attendu** : Aucun message d'erreur rouge après la fermeture ou l'annulation ; le bouton « Se connecter » redevient utilisable immédiatement ; la connexion complète fonctionne ensuite. Une vraie panne (réseau coupé) affiche toujours son message.

- [ ] Passé — date / appareil / version :

### A25 — Se déconnecter depuis le profil Discogs `AUDIT`

**Conditions** : Connecté avec un compte Discogs.

**Étapes** :

1. Réglages → toucher le profil Discogs.
2. Faire défiler : le bouton « Se déconnecter » est juste au-dessus de « Supprimer mon compte… ».
3. Le toucher, puis « Annuler ». Le retoucher et confirmer.

**Résultat attendu** : « Annuler » ne change rien. La confirmation déconnecte, ferme le profil et ramène à l'écran de connexion ; les tags et écoutes sont retrouvés à la reconnexion avec le même compte.

- [ ] Passé — date / appareil / version :

### A26 — Effacer les données de l'app : confirmation explicite en deux étapes `AUDIT` `AUTO`

**Conditions** : Compte Discogs connecté avec des écoutes, des tags et une alerte de prix ; depuis Réglages, puis depuis le profil Discogs.

**Étapes** :

1. Réglages (ou profil) > Supprimer le compte Discogs > « Effacer les données de l'app… ».
2. Lire la feuille « Effacer mes données » : texte d'avertissement, liste des données avec leurs quantités.
3. Toucher le champ de saisie : observer la hauteur de la feuille et la position du champ par rapport au clavier ; refermer le clavier par un toucher à côté, par « OK » et par glissé.
- 3 bis. Essayer le bouton rouge sans rien taper, puis avec un nom incorrect, puis avec le bon nom (casse indifférente).
4. Fermer par la croix ou en glissant la feuille, puis recommencer et confirmer.
5. Vérifier après confirmation : déconnexion, données effacées.

**Résultat attendu** : Le bouton du dialogue ne supprime plus rien : il ouvre une feuille qui dit « Ton historique d'écoute, tes tags et tes alertes seront perdus définitivement, y compris sur iCloud », avec les quantités réelles (écoutes, exemplaires avec tags, alertes, grades) et précise que les disques restent sur Discogs. Le bouton rouge « Effacer définitivement mes données » reste grisé tant que le nom d'utilisateur Discogs n'est pas retapé exactement (casse et espaces ignorés). Fermer la feuille n'efface rien. Après confirmation, la déconnexion a lieu et tout est effacé, y compris dans iCloud. La feuille s'ouvre d'emblée en grand (jamais à mi-hauteur) ; au toucher du champ, il se centre au-dessus du clavier, bouton rouge visible juste dessous (jamais recouvert) ; un toucher hors du champ, « OK » au-dessus du clavier, la touche Terminé ou un glissé de la liste referment le clavier. Même parcours depuis les deux entrées (règle du nom couverte par EraseAccountDataConfirmationTests).

- [ ] Passé — date / appareil / version :

### A27 — Écran d'accueil animé, plein écran, avant la connexion `AUDIT` `AUTO`

**Conditions** : App lancée sans compte connecté (ou -uiTestSignedOut) ; Réduire les animations désactivé puis activé ; thèmes clair et sombre ; petit écran (iPhone mini) ; VoiceOver.

**Étapes** :

1. Lancer l'app sans compte et observer l'écran pendant une dizaine de secondes.
2. Toucher « Se connecter », « Pas de compte ? Crée-en un » puis « Explorer avec une collection de démo ».
3. Depuis la démo, aller dans Réglages et quitter le mode démo.
4. Se connecter avec un vrai compte, puis se déconnecter.
5. Refaire avec Réduire les animations activé, en thème sombre, sur un petit écran, avec VoiceOver.

**Résultat attendu** : L'écran d'accueil occupe tout l'écran : ni barre d'onglets, ni barre de navigation, ni titre « Collection ». Le disque tourne entouré des pochettes qui flottent, avec un halo rose qui respire ; le nom de l'app puis les accroches arrivent l'un après l'autre et l'accroche rose change toutes les 3 s en glissant vers le haut. Les trois actions fonctionnent. À la connexion ou en démo, l'écran se fond vers les onglets (Collection d'abord) ; en quittant la démo ou en se déconnectant, il revient en fondu par-dessus les onglets. Réduire les animations : tout est immobile, contenu identique. Petit écran : l'écran défile, rien n'est coupé. VoiceOver : titre, phrase fixe et boutons seulement, sans accès aux onglets masqués. La sortie de démo est couverte par DemoModeUITests.

- [ ] Passé — date / appareil / version :

### A28 — Démo : pastille flottante et sortie vers l'écran d'accueil `AUDIT` `AUTO`

**Conditions** : App lancée sans compte ; thèmes clair et sombre ; Réduire les animations désactivé puis activé ; texte en taille standard puis très grande ; VoiceOver.

**Étapes** :

1. Toucher « Explorer avec une collection de démo ».
2. Parcourir Collection, Wantlist, Stats, Recherche et Réglages, ouvrir une fiche de disque, faire défiler les listes.
3. Toucher la pastille « Mode démo ».
4. Refaire la sortie par Réglages > « Quitter le mode démo ».

**Résultat attendu** : Une pastille orange translucide « Mode démo ✕ » flotte en haut à droite, sous la barre de navigation, sans déplacer ni masquer les boutons de la barre ni les titres ; elle reste visible sur les cinq onglets et sur la fiche d'un disque, mais pas dans les feuilles. Elle ne gêne pas le toucher des lignes voisines. La toucher quitte la démo aussitôt, sans confirmation, et ramène en fondu à l'écran d'accueil, sans pastille. Le bouton de Réglages fonctionne toujours. Avec Réduire les animations, la pastille apparaît et disparaît sans mouvement. VoiceOver annonce un bouton « Quitter la démo ». La sortie est couverte par DemoModeUITests.

- [ ] Passé — date / appareil / version :

### A29 — Entrée en démo : toujours sur Collection, grand titre intact `AUDIT` `AUTO`

**Conditions** : App lancée sans compte ; iPhone avec grand titre (dont un petit écran) ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Toucher « Explorer avec une collection de démo » et observer le grand titre « Collection ».
2. Aller dans Réglages, ouvrir une sous-page, toucher la pastille « Mode démo ».
3. Relancer la démo depuis l'écran d'accueil.
4. Refaire en ayant quitté la démo depuis la fiche d'un disque ouverte dans Wantlist.

**Résultat attendu** : À chaque entrée en démo, l'app s'ouvre sur l'onglet Collection, à sa racine (aucune fiche ni sous-page restée ouverte, aussi dans les autres onglets). Le grand titre « Collection » s'affiche en entier dès l'arrivée, sans être coupé et sans devoir changer d'onglet ; il se réduit normalement au défilement. La sélection d'onglet est couverte par DemoModeUITests ; le grand titre est à vérifier sur appareil.

- [ ] Passé — date / appareil / version :

### A30 — Supprimer mes données : cotes et pochettes effacées `AUDIT` `DEV`

**Conditions** : Compte connecté ayant ouvert des fiches disque (cotes chargées) et dont les pochettes sont en cache.

**Étapes** :

1. Noter la taille du cache d'images (Réglages → Mode hors ligne, ou Stats).
2. Réglages → Supprimer mon compte → Effacer les données de l'app… → retaper le nom d'utilisateur → Effacer définitivement mes données.
3. Se reconnecter, passer en mode avion, ouvrir une fiche disque et la collection.

**Résultat attendu** : Aucune pochette ni cote ne reste disponible hors ligne après la suppression ; le cache d'images est vide. Les années de sortie d'origine et le classement Albums / Singles & EP sont aussi effacés : après reconnexion, Stats (sorties originales) et la page d'un artiste les recalculent avec la barre de progression. Une simple déconnexion, elle, ne vide pas ces données.

- [ ] Passé — date / appareil / version :

### A31 — Supprimer mes données : brouillon du scan et historique effacés ; déconnexion Google `AUDIT` `AUTO`

**Conditions** : Compte réel avec un brouillon de scan par lot ; connexion à discogs.com dans une fiche (webview) via « Continuer avec Google ».

**Étapes** :

1. Réglages > Supprimer mes données, confirmer, puis se reconnecter au même compte et ouvrir le scan par lot.
2. Avec un autre compte : ouvrir une page discogs.com dans l'app, se déconnecter de l'app, se reconnecter avec un autre compte et rouvrir discogs.com.

**Résultat attendu** : 1 : le scan par lot est vide (aucun brouillon restauré) ; les réglages de rangement sont revenus par défaut. 2 : la page discogs.com n'est plus connectée et Google redemande le compte (session Google de l'app vidée ; Safari n'est pas touché). Règles couvertes par AccountLeftoversTests.

- [ ] Passé — date / appareil / version :

<a id="famille-b"></a>

## B — Collection — Consultation & navigation standard

### B1 — Affichage Liste

**Conditions** : Collection non vide.

**Étapes** :

1. Onglet Collection → menu «... » → Affichage → Liste.

**Résultat attendu** : La collection s'affiche en liste groupée par section (index alphabétique).

- [ ] Passé — date / appareil / version :

### B2 — Affichage Carrousel

**Conditions** : Collection non vide.

**Étapes** :

1. Menu «... » → Affichage → Carrousel.

**Résultat attendu** : Affichage en carrousel de pochettes, défilement fluide.

- [ ] Passé — date / appareil / version :

### B3 — Affichage Mosaïque

**Conditions** : Collection non vide.

**Étapes** :

1. Menu «... » → Affichage → Mosaïque.

**Résultat attendu** : Affichage en grille de pochettes.

- [ ] Passé — date / appareil / version :

### B4 — Tri de la collection (chaque option) `AUTO`

**Conditions** : Collection avec plusieurs exemplaires.

**Étapes** :

1. Menu «... » → Tri → tester successivement chaque option disponible.

**Résultat attendu** : La liste se réordonne immédiatement selon le critère choisi, sans doublon ni élément manquant.

- [ ] Passé — date / appareil / version :

### B5 — Recherche texte

**Conditions** : Collection non vide.

**Étapes** :

1. Taper un terme dans la barre de recherche (titre, artiste, label).

**Résultat attendu** : Résultats filtrés en temps réel ; la barre de recherche reste stable (pas de décrochage visuel).

- [ ] Passé — date / appareil / version :

### B6 — Filtrage par format

**Conditions** : Collection avec plusieurs formats (Vinyle, CD…).

**Étapes** :

1. Menu «... » → Filtres → choisir un format.

**Résultat attendu** : Seuls les exemplaires du format sélectionné sont affichés ; chip de filtre visible en haut de liste.

- [ ] Passé — date / appareil / version :

### B7 — Filtrage par un tag

**Conditions** : Au moins un tag existant sur la collection.

**Étapes** :

1. Menu «... » → Filtres → Filtrer par tag → sélectionner un tag.

**Résultat attendu** : Seuls les exemplaires portant ce tag sont affichés.

- [ ] Passé — date / appareil / version :

### B8 — Filtrage par plusieurs tags (logique ET)

**Conditions** : Au moins deux tags utilisés sur des exemplaires communs et distincts.

**Étapes** :

1. Sélectionner le tag X puis le tag Y dans la feuille de filtre.

**Résultat attendu** : Seuls les exemplaires portant À LA FOIS X ET Y sont affichés (pas une union).

- [ ] Passé — date / appareil / version :

### B9 — Combinaison recherche + filtres tag + format

**Conditions** : Collection variée.

**Étapes** :

1. Appliquer un filtre de tag, un filtre de format, puis taper un texte de recherche.

**Résultat attendu** : Les trois critères se cumulent correctement ; le compteur « x/y albums » reflète le résultat final.

- [ ] Passé — date / appareil / version :

### B10 — Effacer tous les filtres

**Conditions** : Au moins un filtre actif.

**Étapes** :

1. Toucher « Tout effacer » dans la barre de filtres actifs.

**Résultat attendu** : Tous les filtres (tags + format) sont retirés en une action ; la liste complète réapparaît.

- [ ] Passé — date / appareil / version :

### B11 — Changement de dossier

**Conditions** : Plusieurs dossiers existants.

**Étapes** :

1. Menu «... » → Dossier → sélectionner un dossier spécifique, puis « Tous dossiers ».

**Résultat attendu** : La liste se restreint au dossier choisi ; revenir à « Tous dossiers » réaffiche tout.

- [ ] Passé — date / appareil / version :

### B12 — Barre d'index alphabétique

**Conditions** : Affichage Liste, collection volumineuse.

**Étapes** :

1. Glisser le doigt sur la barre d'index à droite de l'écran.

**Résultat attendu** : Défilement rapide et fluide vers la lettre correspondante.

- [ ] Passé — date / appareil / version :

### B13 — Pull-to-refresh

**Conditions** : Collection affichée.

**Étapes** :

1. Tirer la liste vers le bas.

**Résultat attendu** : Rafraîchissement déclenché sans sursensibilité (ne se déclenche pas sur un filtre actif au simple survol).

- [ ] Passé — date / appareil / version :

### B14 — Lecture aléatoire (carrousel)

**Conditions** : Affichage Carrousel.

**Étapes** :

1. Déclencher la sélection aléatoire d'un album.

**Résultat attendu** : Animation de sélection visible (pas de saut sans transition) ; l'album choisi est mis en avant.

- [ ] Passé — date / appareil / version :

### B15 — Accès fiche détail depuis chaque affichage

**Conditions** : Un exemplaire visible.

**Étapes** :

1. Toucher un exemplaire en Liste, puis en Carrousel, puis en Mosaïque.

**Résultat attendu** : La fiche détail s'ouvre correctement dans les trois cas.

- [ ] Passé — date / appareil / version :

### B16 — Édition d'un exemplaire

**Conditions** : Un exemplaire sélectionné.

**Étapes** :

1. Ouvrir la fiche détail → modifier prix d'achat, état, notes, tags → enregistrer.

**Résultat attendu** : Les modifications sont persistées et visibles immédiatement dans la liste et la fiche.

- [ ] Passé — date / appareil / version :

### B17 — Compteur « x/y albums »

**Conditions** : Un filtre actif.

**Étapes** :

1. Observer le sous-titre de navigation après application d'un filtre.

**Résultat attendu** : Le sous-titre affiche bien le nombre d'albums filtrés sur le total du dossier courant.

- [ ] Passé — date / appareil / version :

### B18 — Barre de défilement système masquée `RÉGRESSION`

**Conditions** : Liste filtrée courte (quelques éléments seulement), `SectionIndexBar` visible.

**Étapes** :

1. Appliquer un filtre réduisant la liste à 2-3 sections.
2. Observer le bord droit de l'écran.

**Résultat attendu** : Seule la barre de navigation rapide personnalisée (jetons) est visible ; plus de longue barre grise native superposée (corrigé via `.scrollIndicators(.hidden)`).

- [ ] Passé — date / appareil / version :

### B19 — Filtre donnant 0 résultat `LIMITE`

**Conditions** : Filtre combinant tag + format + recherche sans aucune correspondance.

**Étapes** :

1. Appliquer une combinaison de filtres qui ne correspond à aucun exemplaire.

**Résultat attendu** : Message d'état vide adapté (pas « Collection vide » générique) ; la barre de filtres actifs reste visible pour pouvoir les retirer.

- [ ] Passé — date / appareil / version :

### B20 — Collection avec exactement 1 exemplaire `LIMITE`

**Conditions** : Collection réduite à un seul exemplaire (via filtre ou dossier).

**Étapes** :

1. Afficher cette collection à 1 élément dans les 3 modes d'affichage.

**Résultat attendu** : Pas de barre d'index (n'apparaît que si plus d'une section), pas de pull-to-refresh à rebond excessif, aucun crash sur un seul élément.

- [ ] Passé — date / appareil / version :

### B21 — Collection très volumineuse (1000+ exemplaires) `LIMITE`

**Conditions** : Compte de test avec une très grande collection, ou générée pour le test.

**Étapes** :

1. Faire défiler rapidement du haut en bas sur toute la collection.

**Résultat attendu** : Chargement progressif (pagination) sans blocage ni ralentissement notable ; la barre d'index reste utilisable.

- [ ] Passé — date / appareil / version :

### B22 — Recherche avec caractères spéciaux / emoji / espaces superflus `LIMITE`

**Conditions** : Collection non vide.

**Étapes** :

1. Rechercher avec des emoji, des accents, des espaces en début/fin, des caractères type « é », « ñ », « 日本語 ».

**Résultat attendu** : Aucun crash ; résultats cohérents (vides si rien ne correspond), pas de requête malformée.

- [ ] Passé — date / appareil / version :

### B23 — Titre d'album extrêmement long `LIMITE`

**Conditions** : Un release avec un titre très long (>100 caractères) ajouté à la collection.

**Étapes** :

1. Afficher cet exemplaire dans les 3 modes d'affichage.

**Résultat attendu** : Le titre est tronqué proprement (pas de débordement hors de l'écran ni de superposition avec d'autres éléments).

- [ ] Passé — date / appareil / version :

### B24 — Dossier supprimé sur Discogs.com pendant la consultation `LIMITE`

**Conditions** : Dossier affiché dans l'app, supprimé via le site Discogs entre-temps.

**Étapes** :

1. Supprimer le dossier sur Discogs.com.
2. Revenir dans l'app et rafraîchir.

**Résultat attendu** : L'app détecte l'absence du dossier et retombe sur « Tous dossiers » sans crash ni état bloqué.

- [ ] Passé — date / appareil / version :

### B25 — Perte réseau en pleine pagination `LIMITE`

**Conditions** : Collection longue, défilement proche de la fin de la page chargée.

**Étapes** :

1. Activer le mode avion juste avant d'atteindre le bas de la page chargée.

**Résultat attendu** : Message d'erreur réseau localisé (pas un écran d'erreur plein écran) ; le chargement reprend normalement au retour du réseau.

- [ ] Passé — date / appareil / version :

### B26 — Rotation pendant un défilement rapide `LIMITE`

**Conditions** : iPad ou iPhone en orientation libre.

**Étapes** :

1. Faire défiler rapidement tout en tournant l'appareil.

**Résultat attendu** : Pas de saut de position ni de crash ; la mise en page s'adapte correctement à la nouvelle orientation.

- [ ] Passé — date / appareil / version :

### B27 — Disque supprimé sur Discogs.com `AUDIT` `RÉGRESSION`

**Conditions** : Exemplaire présent dans l'app.

**Étapes** :

1. Supprimer cet exemplaire de la collection sur discogs.com.
2. Dans l'app, tirer pour rafraîchir et attendre la fin du chargement de toutes les pages.
3. Activer le mode avion et relancer l'app.

**Résultat attendu** : Le disque disparaît de la liste après le chargement complet, et n'est plus présent dans le cache hors ligne après relancement.

- [ ] Passé — date / appareil / version :

### B28 — Disque déplacé de dossier sur Discogs.com `AUDIT` `RÉGRESSION`

**Conditions** : Plusieurs dossiers ; exemplaire dans le dossier X.

**Étapes** :

1. Déplacer l'exemplaire du dossier X vers Y sur discogs.com.
2. Dans l'app, afficher le dossier X et tirer pour rafraîchir.
3. Afficher le dossier Y.

**Résultat attendu** : L'exemplaire disparaît du dossier X et apparaît dans Y ; compteurs de dossiers cohérents.

- [ ] Passé — date / appareil / version :

### B29 — Rafraîchissement interrompu : rien n'est supprimé à tort `AUDIT` `LIMITE`

**Conditions** : Grande collection (plusieurs pages).

**Étapes** :

1. Tirer pour rafraîchir.
2. Pendant le chargement, au choix : activer le mode avion, changer de dossier ou changer de tri.
3. Revenir à l'état initial.

**Résultat attendu** : Aucun disque ne disparaît de la liste suite à l'interruption ; le rafraîchissement suivant, complet, remet tout à jour.

- [ ] Passé — date / appareil / version :

### B30 — Disque ajouté pendant le chargement de fond `AUDIT` `LIMITE`

**Conditions** : Grande collection.

**Étapes** :

1. Tirer pour rafraîchir la collection.
2. Pendant le chargement, ajouter un nouveau disque depuis la Recherche.
3. Revenir à la Collection et attendre la fin du chargement.

**Résultat attendu** : Le disque ajouté reste affiché à la fin du chargement (il n'est pas retiré par le nettoyage des disques absents).

- [ ] Passé — date / appareil / version :

### B31 — Fluidité pendant la synchro d'une grosse collection `AUDIT` `RÉGRESSION` `LIMITE`

**Conditions** : Collection de 1000+ disques, cache local vide (nouvelle connexion ou réinstallation).

**Étapes** :

1. Se connecter et ouvrir la Collection.
2. Faire défiler pendant que les pages se chargent en arrière-plan.

**Résultat attendu** : Défilement fluide pendant toute la synchro (pas de gel qui s'aggrave au fil des pages) ; le widget « Album aléatoire » est mis à jour à la fin.

- [ ] Passé — date / appareil / version :

### B32 — Retirer un exemplaire déjà supprimé sur Discogs.com `AUDIT` `LIMITE`

**Conditions** : Exemplaire visible dans l'app, supprimé entre-temps sur discogs.com (sans rafraîchir l'app).

**Étapes** :

1. Retirer cet exemplaire depuis l'app (liste ou fiche).

**Résultat attendu** : Retrait accepté sans message d'erreur ; aucune action mise en file, donc pas d'« Échec définitif de synchronisation » plus tard.

- [ ] Passé — date / appareil / version :

### B33 — Déplacement de dossier avec Discogs injoignable `AUDIT`

**Conditions** : Network Link Conditioner sur « 100% Loss » (réseau présent mais Discogs injoignable).

**Étapes** :

1. Changer un exemplaire de dossier.
2. Rétablir le réseau normal.

**Résultat attendu** : Alerte « Discogs ne répond pas : la modification sera synchronisée automatiquement » ; l'exemplaire reste dans son nouveau dossier et le déplacement est appliqué sur discogs.com au retour du réseau.

- [ ] Passé — date / appareil / version :

### B34 — Déplacement refusé par Discogs `AUDIT` `LIMITE`

**Conditions** : Dossier Y supprimé sur discogs.com sans rafraîchir l'app.

**Étapes** :

1. Déplacer un exemplaire vers le dossier Y dans l'app.

**Résultat attendu** : Alerte « Impossible de changer ce disque de dossier sur Discogs » ; l'exemplaire revient dans son dossier d'origine, compteurs des dossiers restaurés.

- [ ] Passé — date / appareil / version :

### B35 — Message « modification bloquée » hors ligne visible `AUDIT` `RÉGRESSION`

**Conditions** : Mode avion + cache de plus de 6 h (Options développeur › simuler un cache périmé).

**Étapes** :

1. Tenter de retirer puis de déplacer un exemplaire de la collection.

**Résultat attendu** : Une alerte explique que la modification est bloquée (auparavant ce message restait invisible) ; rien n'est modifié.

- [ ] Passé — date / appareil / version :

### B36 — Changements rapides de tri et de dossier `AUDIT` `LIMITE`

**Conditions** : Grande collection, réseau disponible.

**Étapes** :

1. Changer de tri, puis de dossier, plusieurs fois de suite très rapidement.

**Résultat attendu** : Aucun message d'erreur technique (« CancellationError »…) ; la liste finale correspond au dernier tri et dossier choisis.

- [ ] Passé — date / appareil / version :

### B37 — Contenu de la collection de démo `AUDIT` `AUTO`

**Conditions** : Mode démo actif.

**Étapes** :

1. Parcourir la Collection en Liste, Mosaïque et Carrousel.
2. Filtrer par support et par dossier (Jazz, Électronique, Uncategorized).

**Résultat attendu** : Pochettes, années et genres affichés. Vinyles, CD et cassettes présents (filtre Support). Les compteurs de dossiers correspondent à leur contenu. « Oasis » affiché sans le suffixe « (2) ».

- [ ] Passé — date / appareil / version :

### B38 — Démo : retrait bloqué depuis la Collection `AUDIT`

**Conditions** : Mode démo actif.

**Étapes** :

1. Balayer un disque pour le retirer.
2. En sélection multiple, tenter de retirer ou déplacer plusieurs disques.

**Résultat attendu** : Alerte « En mode démo, il n'est pas possible de retirer des albums… » ; le disque ne disparaît jamais, même brièvement.

- [ ] Passé — date / appareil / version :

### B39 — Mon exemplaire : échec d'enregistrement à la fermeture `AUDIT` `LIMITE`

**Conditions** : Collection ouverte, un exemplaire avec un champ personnalisé texte. Network Link Conditioner prêt à renvoyer une erreur, ou champ supprimé sur discogs.com juste avant.

**Étapes** :

1. Ouvrir « Mon exemplaire », modifier le champ sans le valider.
2. Fermer aussitôt la feuille (glisser vers le bas).

**Résultat attendu** : Si Discogs refuse l'enregistrement, une alerte s'affiche sur l'écran d'origine (Collection ou fiche release) ; la saisie n'est plus perdue en silence. Hors ligne, la modification part en file comme avant.

- [ ] Passé — date / appareil / version :

### B40 — Grosse collection : interface fluide pendant le chargement `AUDIT` `LIMITE`

**Conditions** : Compte avec une collection de plusieurs milliers d'exemplaires, cache vidé (Réglages → options développeur, ou réinstallation).

**Étapes** :

1. Ouvrir la Collection, dossier « Tous », et faire défiler pendant que les pages se chargent.
2. Ouvrir les Stats pendant le chargement complet.

**Résultat attendu** : Défilement et onglets restent réactifs pendant le chargement (les pages sont décodées hors du fil principal) ; aucun gel de plus d'une fraction de seconde.

- [ ] Passé — date / appareil / version :

### B41 — Grand titre qui se réduit au défilement (petit écran) `AUDIT` `RÉGRESSION`

**Conditions** : iPhone 13 mini (ou autre petit écran) sous iOS 26.x, collection d'au moins 10 disques répartis sur plusieurs sections ; noter la version d'iOS.

**Étapes** :

1. Ouvrir Collection en mode Liste et faire défiler lentement, en franchissant plusieurs sections (lettres).
2. Remonter en haut, puis recommencer en Mosaïque et en Carrousel.
3. Changer le tri, puis refaire défiler.
4. Répéter dans Wantlist, Stats et Réglages ; tester aussi en grande taille de texte.

**Résultat attendu** : Le grand titre « Collection » se réduit en petit titre centré dès que la liste défile et redevient grand en haut ; la barre du haut reste lisible (flou net, pas de liste visible à travers le titre, pas de texte superposé). Même comportement que sur un iPhone récent.

- [ ] Passé — date / appareil / version :

### B42 — Première connexion : la Collection s'affiche même avec un exemplaire atypique `AUDIT` `AUTO`

**Conditions** : Compte Discogs réel, app fraîchement installée (aucun cache).

**Étapes** :

1. Se connecter pour la première fois.
2. Ouvrir l'onglet Collection sans attendre.
3. Comparer le nombre d'exemplaires avec celui du dossier « All » sur discogs.com.

**Résultat attendu** : La Collection se remplit sans message « Les données n'ont pas pu être lues car elles sont introuvables » ; la Wantlist aussi. Un exemplaire dont les données sont inutilisables est ignoré sans bloquer les autres.

- [ ] Passé — date / appareil / version :

### B43 — Carrousel : cran haptique au défilement des pochettes `AUDIT`

**Conditions** : iPhone réel (le Simulateur n'a pas de retour haptique), Collection et Wantlist en affichage Carrousel, retours haptiques système activés.

**Étapes** :

1. Faire défiler lentement le carrousel au doigt, pochette par pochette.
2. Balayer rapidement sur une grosse collection.
3. Utiliser la barre A-Z du bas et le bouton « Disque au hasard ».
4. Désactiver les retours haptiques système (Réglages iOS → Sons et vibrations) et refaire l'étape 1.

**Résultat attendu** : Un petit cran léger est perçu chaque fois qu'une nouvelle pochette arrive au centre pendant un défilement au doigt (y compris pendant l'élan qui suit le geste), sans jamais devenir un bourdonnement continu lors d'un balayage rapide (au plus un cran toutes les 50 ms environ). Aucun cran pendant un saut par la barre A-Z ; « Disque au hasard » garde son seul impact moyen au départ. Aucun cran si les retours haptiques système sont désactivés.

- [ ] Passé — date / appareil / version :

### B44 — Barre A-Z verticale (Liste et Mosaïque) : cran haptique à chaque lettre `AUDIT`

**Conditions** : iPhone réel, Collection et Wantlist en affichage Liste puis Mosaïque, tri alphabétique ou par date, retours haptiques système activés.

**Étapes** :

1. Poser le doigt sur la barre de lettres à droite et le glisser lentement du haut vers le bas.
2. Le glisser vite, puis remonter.
3. Rester sur la même lettre en bougeant très légèrement le doigt.
4. Désactiver les retours haptiques système et refaire l'étape 1.

**Résultat attendu** : Un petit cran léger à chaque changement de lettre ou d'année sous le doigt (le même que sur la barre horizontale du carrousel), un seul cran par lettre traversée, aucun cran tant qu'on reste sur la même lettre. La liste suit comme avant. Aucun cran si les retours haptiques système sont désactivés.

- [ ] Passé — date / appareil / version :

### B45 — Carrousel : le doigt reste aligné sur la barre A-Z horizontale `AUDIT`

**Conditions** : Collection et Wantlist en affichage Carrousel ; un tri avec peu de lettres (la rangée de lettres plus étroite que l'écran) puis un tri avec beaucoup de lettres (A-Z complet, rangée compressée).

**Étapes** :

1. Poser le doigt sur une lettre précise de la barre du bas, sans bouger.
2. Glisser lentement d'un bord à l'autre de la rangée de lettres.
3. Essayer sur la première et la dernière lettre, et au bord gauche et droit de l'écran.

**Résultat attendu** : La lettre mise en évidence (et la bulle) est toujours celle qui se trouve juste sous le doigt, du bord gauche au bord droit de la rangée, sans décalage qui grandit vers les extrémités. Au-delà de la rangée, la première ou la dernière lettre reste sélectionnée.

- [ ] Passé — date / appareil / version :

### B46 — Liste : un disque retiré s'efface en douceur (Collection et Wantlist) `AUDIT`

**Conditions** : Collection et Wantlist avec plusieurs disques ; affichages Liste, Mosaïque et Carrousel ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Retirer un disque de la Wantlist (balayage, menu contextuel ou fiche), puis de la Collection.
2. Observer la ligne ou la pochette.
3. Refaire avec Réduire les animations activé.

**Résultat attendu** : La ligne ou la pochette s'efface en fondu et les suivantes se resserrent, au lieu de disparaître d'un coup. Avec Réduire les animations : disparition immédiate. Un retrait refusé par Discogs réaffiche le disque comme avant.

- [ ] Passé — date / appareil / version :

### B47 — Tirer pour actualiser : pastille « À jour » et haptique `AUDIT`

**Conditions** : Compte connecté, avec réseau ; Collection et Wantlist en Liste, puis hors ligne.

**Étapes** :

1. Tirer la liste vers le bas jusqu'à la synchronisation.
2. Attendre la fin de l'actualisation.
3. Couper le réseau et refaire le geste.

**Résultat attendu** : À la fin d'une actualisation réussie, une pastille verte « À jour » descend en haut de la liste avec un haptique de succès, puis disparaît seule après environ 1,5 s. Hors ligne, aucune pastille. Limite connue : l'indicateur de tirage reste celui du système (pas de disque qui tourne).

- [ ] Passé — date / appareil / version :

### B48 — États vides illustrés : Collection et Wantlist `AUDIT`

**Conditions** : Compte sans disque en collection, puis sans disque en wantlist (ou démo vidée) ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir la Collection vide puis la Wantlist vide.
2. Toucher « Rechercher un disque ».
3. Refaire avec Réduire les animations activé et en thème sombre.

**Résultat attendu** : Un disque noir à étiquette rose tourne lentement au-dessus du titre (avec une pastille cœur ou pile de disques), suivi de l'explication et du bouton qui ouvre la recherche. Disque fixe avec Réduire les animations ; lisible en thème clair et sombre ; l'illustration est ignorée par VoiceOver.

- [ ] Passé — date / appareil / version :

### B49 — Carrousel : appui long sur la jaquette (menu d'actions, retrait avec confirmation) `AUDIT`

**Conditions** : Collection et Wantlist en affichage Carrousel ; compte Premium puis non Premium ; en ligne puis hors ligne avec données de plus de 6 h ; mode sélection actif puis non.

**Étapes** :

1. En Collection (Carrousel), appuyer longuement sur une jaquette.
2. Tester « J'écoute ce disque sur la platine » / « Arrêter l'écoute », « Où ranger », « Modifier la note / notes », puis « Supprimer de la collection » (confirmer, puis refaire en annulant).
3. En Wantlist (Carrousel), appuyer longuement : « Définir/Modifier une alerte prix », « Vers la collection », « Supprimer de la wantlist » (confirmer, puis annuler).
4. Toucher brièvement une jaquette, puis la cloche de la Wantlist.
5. Activer le mode sélection et appuyer longuement.
6. Passer hors ligne avec des données périmées et refaire l'appui long en Wantlist.

**Résultat attendu** : Un menu s'ouvre sous le doigt avec les actions listées ; chacune fait la même chose que dans la Liste. Les suppressions demandent une confirmation et, une fois confirmées, la pochette s'efface en fondu ; en annulant, rien ne change. « Où ranger » sans Premium ouvre l'offre. Le toucher bref ouvre toujours la fiche et la cloche de la Wantlist garde son comportement. En mode sélection, aucun menu : l'appui long ne fait rien de plus que le toucher. Hors ligne avec données périmées, la Wantlist ne propose que l'alerte (pas de retrait ni de passage en collection).

- [ ] Passé — date / appareil / version :

### B50 — Ouverture d'une fiche en zoom depuis la pochette `AUDIT`

**Conditions** : Collection et Wantlist avec des disques ; modes Liste, Mosaïque et Carrousel ; Réduire les animations désactivé puis activé ; un disque possédé en deux exemplaires.

**Étapes** :

1. Toucher une pochette en mode Mosaïque, puis revenir (bouton retour, puis geste du bord gauche).
2. Refaire en mode Carrousel puis en mode Liste, dans la Collection puis dans la Wantlist.
3. Ouvrir la fiche, remonter en haut de page et tirer vers le bas ; faire défiler la fiche normalement.
4. Ouvrir un disque depuis un artiste ou une notification, depuis une recherche.
5. Refaire avec Réduire les animations activé.

**Résultat attendu** : La fiche grandit depuis la pochette touchée (angles arrondis comme la pochette) et s'y résorbe au retour. Mosaïque, Carrousel et Liste, Collection comme Wantlist. Le défilement de la fiche et le geste de retour restent normaux, sans fermeture involontaire en tirant vers le bas en haut de page. Un disque en deux exemplaires s'ouvre sans défaut (le zoom part de l'un d'eux). Les ouvertures qui ne partent pas d'une pochette de la Collection ou de la Wantlist restent correctes (à surveiller : pas de saut ni de fond blanc). Avec Réduire les animations : transition simple, sans zoom.

- [ ] Passé — date / appareil / version :

### B51 — Onglets : rechargement depuis Discogs au plus toutes les 5 min, tirer-pour-actualiser immédiat `AUDIT` `AUTO`

**Conditions** : Compte réel avec une grande collection ; réseau actif ; une modification faite sur discogs.com depuis un ordinateur.

**Étapes** :

1. Ouvrir Collection, puis passer plusieurs fois de Collection à Wantlist et Stats en moins de 5 min.
2. Modifier un disque sur discogs.com, revenir sur Collection dans les 5 min, puis tirer pour actualiser.
3. Attendre plus de 5 min et revenir sur Collection.
4. Se déconnecter et se connecter avec un autre compte.

**Résultat attendu** : 1 : le contenu s'affiche aussitôt depuis le cache, sans squelette ni rechargement à chaque retour ; la synchro de fond d'une grosse collection va au bout. 2 : la modification apparaît après le tirer-pour-actualiser (pastille « À jour »). 3 : rechargement automatique. 4 : le nouveau compte se charge tout de suite. Délai couvert par ReloadThrottleTests.

- [ ] Passé — date / appareil / version :

### B52 — Filtre « À compléter » : albums sans prix d'achat ou sans état du média `AUDIT` `AUTO`

**Conditions** : Champs « Prix d'achat » et « État du média » choisis dans Réglages > Prix d'achat et état ; quelques disques sans l'un, sans l'autre, sans les deux, et avec les deux ; scan par lot de 3 disques ajoutés à la collection sans rien renseigner.

**Étapes** :

1. Collection > « ··· » > Filtres > « À compléter » : cocher « Sans prix d'achat ».
2. Cocher en plus « Sans état du média ».
3. Combiner avec un tag ou un format, puis avec la recherche.
4. Ouvrir un disque de la liste, renseigner son prix, revenir.
5. Retirer un filtre par sa pastille, puis « Tout effacer ».
6. Dans Réglages, retirer le champ « Prix d'achat », revenir à la Collection.
7. Se connecter à un compte sans ces champs configurés.

**Résultat attendu** : 1 : seuls les disques sans prix d'achat restent, avec une pastille « Sans prix d'achat » dans le bandeau. 2 : seuls ceux sans prix ET sans état (les deux filtres se cumulent). 3 : les filtres se cumulent aussi avec tags, format et recherche. 4 : le disque complété disparaît de la liste filtrée. 5 : la pastille se retire seule ; « Tout effacer » vide aussi ce filtre. 6 : l'option du champ retiré disparaît du menu et sort de la sélection. 7 : le sous-menu « À compléter » n'apparaît pas. Les 3 disques du scan par lot sont retrouvés par le filtre. Les filtres ne sont pas conservés au prochain lancement. Règle couverte par MissingFieldFilterTests ; la liste ne contient que les albums déjà chargés.

- [ ] Passé — date / appareil / version :

### B53 — Suppression par balayage : confirmation puis retrait, sans arrêt de l'app `AUDIT`

**Conditions** : Collection en mode Liste ; faire le test sur un disque de la 1re section (haut de liste) et sur un disque d'une section de 2 disques ; réseau actif.

**Étapes** :

1. Balayer une ligne vers la gauche, toucher « Supprimer ».
2. Dans la confirmation, toucher « Annuler », puis refaire et confirmer la suppression.
3. Répéter la suppression sur le 1er disque d'une section (l'en-tête change de titre ou d'artistes).
4. Répéter après un tirage pour actualiser, puis avec un tag filtré.

**Résultat attendu** : 1 : la ligne reste en place tant que la suppression n'est pas confirmée (elle ne disparaît pas au toucher). 2 : Annuler referme le balayage sans rien retirer ; confirmer retire le disque avec l'animation, sans arrêt de l'app. 3 et 4 : même résultat, compteurs de section et de dossier à jour, aucune ligne fantôme.

- [ ] Passé — date / appareil / version :

<a id="famille-c"></a>

## C — Collection — Sélection multiple & actions groupées

### C1 — Entrer en mode sélection

**Conditions** : Collection non vide.

**Étapes** :

1. Menu «... » → Sélectionner.

**Résultat attendu** : Mode sélection activé : cercles de sélection visibles sur chaque exemplaire, barre d'action en bas.

- [ ] Passé — date / appareil / version :

### C2 — Sélectionner / désélectionner plusieurs exemplaires

**Conditions** : Mode sélection actif.

**Étapes** :

1. Toucher plusieurs exemplaires successivement.

**Résultat attendu** : Chaque cercle s'anime et se remplit ; le compteur de sélection se met à jour.

- [ ] Passé — date / appareil / version :

### C3 — Sortir du mode sélection sans action

**Conditions** : Mode sélection actif avec sélection en cours.

**Étapes** :

1. Toucher la coche en haut de l'écran.

**Résultat attendu** : Retour à l'affichage normal, aucune modification appliquée.

- [ ] Passé — date / appareil / version :

### C4 — Action groupée — Tag `PREMIUM`

**Conditions** : Au moins 1 exemplaire sélectionné.

**Étapes** :

1. Barre d'action → icône Tag.

**Résultat attendu** : TagManagementView s'ouvre en mode application groupée, feuille ouverte à mi-hauteur (.medium) ; les tags appliqués impactent tous les exemplaires sélectionnés.

- [ ] Passé — date / appareil / version :

### C5 — Action groupée — Déplacer (1 exemplaire)

**Conditions** : Exactement 1 exemplaire sélectionné.

**Étapes** :

1. Barre d'action → Dossier → choisir un dossier cible.

**Résultat attendu** : Dialogue de confirmation au singulier : « Déplacer l'exemplaire dans le dossier X ? » avec bouton « Déplacer ».

- [ ] Passé — date / appareil / version :

### C6 — Action groupée — Déplacer (N exemplaires)

**Conditions** : Plusieurs exemplaires sélectionnés.

**Étapes** :

1. Barre d'action → Dossier → choisir un dossier cible.

**Résultat attendu** : Dialogue au pluriel : « Déplacer les N exemplaires dans le dossier X ? » avec bouton « Déplacer » (sans répéter le nombre dans le bouton).

- [ ] Passé — date / appareil / version :

### C7 — Annuler la confirmation de déplacement

**Conditions** : Dialogue de confirmation de déplacement affiché.

**Étapes** :

1. Toucher « Annuler ».

**Résultat attendu** : Aucun exemplaire déplacé, sélection conservée.

- [ ] Passé — date / appareil / version :

### C8 — Action groupée — Supprimer (1 exemplaire)

**Conditions** : Exactement 1 exemplaire sélectionné.

**Étapes** :

1. Barre d'action → icône corbeille.

**Résultat attendu** : Confirmation au singulier « Supprimer de la collection ? » ; après confirmation l'exemplaire disparaît.

- [ ] Passé — date / appareil / version :

### C9 — Action groupée — Supprimer (N exemplaires)

**Conditions** : Plusieurs exemplaires sélectionnés.

**Étapes** :

1. Barre d'action → icône corbeille.

**Résultat attendu** : Confirmation au pluriel avec le nombre correct ; tous les exemplaires sélectionnés disparaissent après confirmation.

- [ ] Passé — date / appareil / version :

### C10 — Annuler la suppression groupée

**Conditions** : Dialogue de suppression affiché.

**Étapes** :

1. Toucher « Annuler ».

**Résultat attendu** : Aucun exemplaire supprimé, sélection conservée.

- [ ] Passé — date / appareil / version :

### C11 — Sélectionner la totalité de la collection `LIMITE`

**Conditions** : Collection complète (ex. 278/278 éléments).

**Étapes** :

1. Sélectionner tous les exemplaires un par un ou via un éventuel raccourci.

**Résultat attendu** : Aucun ralentissement notable, compteur exact, action groupée (suppression/déplacement) fonctionnelle sur l'intégralité.

- [ ] Passé — date / appareil / version :

### C12 — Action groupée avec 0 élément sélectionné `LIMITE`

**Conditions** : Mode sélection actif, aucun élément coché.

**Étapes** :

1. Observer la barre d'action en bas.

**Résultat attendu** : Les boutons d'action sont désactivés ou absents ; aucune action possible sans sélection.

- [ ] Passé — date / appareil / version :

### C13 — Changement de filtre pendant une sélection en cours `LIMITE`

**Conditions** : Plusieurs exemplaires sélectionnés, mode sélection actif.

**Étapes** :

1. Changer le filtre de tag/format sans quitter le mode sélection.

**Résultat attendu** : Comportement cohérent : soit la sélection est conservée pour les éléments encore visibles, soit elle est clairement réinitialisée — dans tous les cas pas de compteur incohérent ni de crash.

- [ ] Passé — date / appareil / version :

### C14 — Perte réseau pendant une suppression groupée `LIMITE`

**Conditions** : Suppression groupée confirmée, mode avion activé juste après.

**Étapes** :

1. Confirmer la suppression puis activer immédiatement le mode avion.

**Résultat attendu** : Message d'erreur clair, pas de suppression partielle silencieuse ; l'état se resynchronise correctement au retour du réseau.

- [ ] Passé — date / appareil / version :

### C15 — Suppression groupée avec Discogs injoignable `AUDIT` `LIMITE`

**Conditions** : Network Link Conditioner sur « 100% Loss ».

**Étapes** :

1. Sélectionner plusieurs exemplaires et les supprimer.
2. Rétablir le réseau.

**Résultat attendu** : Message « Discogs ne répond pas… » ; les exemplaires restent retirés de l'app et sont supprimés sur discogs.com au retour du réseau.

- [ ] Passé — date / appareil / version :

### C16 — Tag appliqué à un très grand nombre d'exemplaires `AUDIT` `LIMITE` `PREMIUM`

**Conditions** : Sélection de 200+ exemplaires (premium : 2e appareil disponible).

**Étapes** :

1. Appliquer un tag à toute la sélection.
2. Retirer ce même tag de toute la sélection.

**Résultat attendu** : Application et retrait quasi instantanés, sans gel ; en premium, le 2e appareil reçoit les changements.

- [ ] Passé — date / appareil / version :

### C17 — Retrait groupé d'un tag porté par une partie seulement `AUDIT` `PREMIUM`

**Conditions** : Sélection mêlant des exemplaires qui portent le tag X et d'autres non.

**Étapes** :

1. Retirer le tag X de toute la sélection.

**Résultat attendu** : Le tag disparaît des exemplaires qui le portaient ; les autres exemplaires et leurs tags sont inchangés.

- [ ] Passé — date / appareil / version :

### C18 — Suppression en lot fluide et widget à jour `AUDIT` `AUTO`

**Conditions** : Compte réel avec une grande collection (idéalement 500 disques ou plus) ; widget « Album du jour » sur l'écran d'accueil ; dont un disque possédé en 2 exemplaires.

**Étapes** :

1. Collection > Sélectionner 20 disques, dont un seul des 2 exemplaires du disque en double, puis Retirer.
2. Faire défiler la liste pendant le retrait.
3. Revenir à l'écran d'accueil et faire défiler le widget (ou attendre son prochain tirage).
4. Ouvrir le Guide de rangement d'un disque, puis Réglages > Rangement > Tri des artistes.

**Résultat attendu** : 1-2 : aucun gel de l'interface pendant le retrait. 3 : le widget ne propose plus les disques retirés, mais propose toujours le disque dont il reste un exemplaire. 4 : les deux écrans s'ouvrent sans à-coup (un indicateur de chargement bref sur le Guide si la collection est grosse). Règle couverte par WidgetSnapshotRemovalTests. Option : mesurer avec Instruments (Time Profiler) avant/après.

- [ ] Passé — date / appareil / version :

<a id="famille-d"></a>

## D — Rangement physique (Shelf placement)

> PREMIUM

### D1 — Accès « Où ranger cet album » — non premium `PREMIUM`

**Conditions** : Compte non premium, fiche détail d'un exemplaire en collection.

**Étapes** :

1. Toucher l'action « Où ranger cet album ».

**Résultat attendu** : Carte verrouillée Or Hifi affichée, puis paywall à l'appui.

- [ ] Passé — date / appareil / version :

### D2 — Guide de rangement — premium `PREMIUM`

**Conditions** : Compte premium.

**Étapes** :

1. Toucher « Où ranger cet album ».

**Résultat attendu** : Guide affiché avec : position dans le meuble, disques repères (voisins immédiats), instructions de rangement.

- [ ] Passé — date / appareil / version :

### D3 — Lien « Modifier » → Réglages `PREMIUM`

**Conditions** : Guide de rangement ouvert.

**Étapes** :

1. Toucher « Modifier » sous « Méthode de classement ».

**Résultat attendu** : Navigation vers Réglages, défilement automatique jusqu'à la section Collection & Rangement, titre visible (pas masqué sous la barre de nav).

- [ ] Passé — date / appareil / version :

### D4 — Impact d'un changement de règle de tri `PREMIUM`

**Conditions** : Guide de rangement affiché pour un album donné.

**Étapes** :

1. Changer la règle de rangement ou le tri par nom de famille dans Réglages.
2. Revenir au guide de rangement du même album.

**Résultat attendu** : La position et les disques repères sont recalculés selon la nouvelle règle.

- [ ] Passé — date / appareil / version :

### D5 — Personnalisation du tri par artiste `PREMIUM`

**Conditions** : Au moins 2 albums du même artiste.

**Étapes** :

1. Réglages → Personnaliser le tri des artistes → réordonner manuellement.

**Résultat attendu** : L'ordre personnalisé est respecté dans le guide de rangement et le tri de la collection.

- [ ] Passé — date / appareil / version :

### D6 — Album sans année de sortie renseignée `LIMITE` `PREMIUM`

**Conditions** : Exemplaire dont le champ année est vide/inconnu côté Discogs.

**Étapes** :

1. Ouvrir le guide de rangement pour cet exemplaire.

**Résultat attendu** : Position calculée malgré tout (placé en fin ou selon une règle de repli définie), pas de crash ni de position « undefined ».

- [ ] Passé — date / appareil / version :

### D7 — Collection réduite à un seul exemplaire `LIMITE` `PREMIUM`

**Conditions** : Dossier/filtre ramenant la collection à 1 seul exemplaire.

**Étapes** :

1. Ouvrir le guide de rangement de cet unique exemplaire.

**Résultat attendu** : Aucun disque repère affiché (pas de voisin), message adapté plutôt qu'une section vide cassée.

- [ ] Passé — date / appareil / version :

### D8 — Égalité parfaite entre deux albums selon le tri `LIMITE` `PREMIUM`

**Conditions** : Deux exemplaires du même artiste, même année, même titre (ex. deux pressages identiques).

**Étapes** :

1. Ouvrir le guide de rangement sur l'un des deux.

**Résultat attendu** : Ordre stable et reproductible entre les deux (ne change pas aléatoirement d'un lancement à l'autre).

- [ ] Passé — date / appareil / version :

### D9 — Années originales résolues pendant le chargement `AUDIT` `RÉGRESSION` `PREMIUM`

**Conditions** : Tri « Rangement » avec une règle utilisant l'année originale ; nombreux masters encore inconnus (nouvelle installation).

**Étapes** :

1. Ouvrir la Collection et la laisser charger plusieurs minutes.

**Résultat attendu** : L'ordre s'affine progressivement à mesure que les années sont résolues (environ une toutes les 1,5 s) ; la résolution ne reste pas bloquée pendant la synchro de la collection.

- [ ] Passé — date / appareil / version :

### D10 — Master sans année sur Discogs `AUDIT` `LIMITE` `PREMIUM`

**Conditions** : Exemplaire dont le master n'a pas d'année sur Discogs ; proxy HTTP (Proxyman) facultatif.

**Étapes** :

1. Ouvrir sa fiche et son guide de rangement.
2. Fermer puis rouvrir plusieurs fois.

**Résultat attendu** : Rangement calculé avec l'année du pressage ; le master n'est demandé à Discogs qu'une seule fois (pas de requête /masters/ID à chaque ouverture).

- [ ] Passé — date / appareil / version :

### D11 — Réglages de rangement propres à chaque compte `AUDIT` `AUTO`

**Conditions** : Deux comptes A et B ; mise à jour depuis une version où A avait déjà réglé le rangement (règle, nom de famille, personnalisations d'artistes).

**Étapes** :

1. Avec A, ouvrir Réglages > Rangement : vérifier les réglages d'avant.
2. Se déconnecter, se connecter avec B, ouvrir Rangement et Tri des artistes.
3. Changer la règle avec B, puis revenir sur A.
4. Entrer en démo, changer un réglage de rangement, quitter et revenir en démo.

**Résultat attendu** : 1 : A retrouve ses réglages. 2 : B part des réglages par défaut, sans les personnalisations de A. 3 : A retrouve sa règle, B garde la sienne. 4 : la démo repart des réglages par défaut. Couvert par ShelfPreferencesStoreTests.

- [ ] Passé — date / appareil / version :

<a id="famille-e"></a>

## E — Wantlist — Standard

### E1 — Ajouter un disque à la wantlist

**Conditions** : Résultat de recherche ou fiche détail ouverte.

**Étapes** :

1. Toucher l'action d'ajout à la wantlist.

**Résultat attendu** : L'élément apparaît dans l'onglet Wantlist.

- [ ] Passé — date / appareil / version :

### E2 — Visualiser la wantlist

**Conditions** : Au moins un élément en wantlist.

**Étapes** :

1. Ouvrir l'onglet Wantlist.

**Résultat attendu** : Liste affichée correctement avec pochette, titre, artiste.

- [ ] Passé — date / appareil / version :

### E3 — Tri wantlist

**Conditions** : Plusieurs éléments en wantlist.

**Étapes** :

1. Menu «... » → Tri → tester chaque option.

**Résultat attendu** : La liste se réordonne sans erreur.

- [ ] Passé — date / appareil / version :

### E4 — Filtrage par format (pas de filtre tag)

**Conditions** : Éléments de formats différents en wantlist.

**Étapes** :

1. Menu «... » → Filtres → format.

**Résultat attendu** : Filtrage correct ; aucune option « Filtrer par tag » n'est proposée en Wantlist (comportement volontaire).

- [ ] Passé — date / appareil / version :

### E5 — Recherche texte wantlist

**Conditions** : Plusieurs éléments en wantlist.

**Étapes** :

1. Taper un terme de recherche.

**Résultat attendu** : Résultats filtrés en temps réel.

- [ ] Passé — date / appareil / version :

### E6 — Retirer un élément individuellement

**Conditions** : Au moins un élément en wantlist.

**Étapes** :

1. Supprimer un élément via le geste ou le bouton dédié.

**Résultat attendu** : L'élément disparaît immédiatement de la liste.

- [ ] Passé — date / appareil / version :

### E7 — Déplacer un élément vers la Collection

**Conditions** : Élément en wantlist possédé physiquement.

**Étapes** :

1. Confirmer le déplacement vers la Collection.

**Résultat attendu** : L'élément quitte la Wantlist et apparaît dans la Collection.

- [ ] Passé — date / appareil / version :

### E8 — Élément supprimé ne réapparaît pas après refresh `RÉGRESSION`

**Conditions** : Supprimer un élément puis tirer pour rafraîchir plusieurs fois de suite rapidement.

**Étapes** :

1. Supprimer un élément.
2. Tirer immédiatement pour rafraîchir 2-3 fois.

**Résultat attendu** : L'élément supprimé ne réapparaît JAMAIS, même en cas d'incohérence temporaire de l'API Discogs (régression corrigée via `locallyRemovedIds`).

- [ ] Passé — date / appareil / version :

### E9 — Pull-to-refresh wantlist

**Conditions** : Wantlist affichée.

**Étapes** :

1. Tirer la liste vers le bas.

**Résultat attendu** : Rafraîchissement correct, pas de doublon.

- [ ] Passé — date / appareil / version :

### E10 — Wantlist vide `LIMITE`

**Conditions** : Aucun élément en wantlist.

**Étapes** :

1. Ouvrir l'onglet Wantlist.

**Résultat attendu** : État vide adapté (message + illustration), pas de section ou de barre d'index affichée.

- [ ] Passé — date / appareil / version :

### E11 — Ajouter un disque déjà présent dans la wantlist `LIMITE`

**Conditions** : Élément déjà en wantlist.

**Étapes** :

1. Tenter de l'ajouter une seconde fois depuis la recherche.

**Résultat attendu** : Pas de doublon créé ; message ou état visuel indiquant qu'il y est déjà, le cas échéant.

- [ ] Passé — date / appareil / version :

### E12 — Élément retiré du catalogue Discogs `LIMITE`

**Conditions** : Release supprimée/fusionnée côté Discogs après son ajout en wantlist.

**Étapes** :

1. Rafraîchir la wantlist contenant cet élément.

**Résultat attendu** : L'élément est soit retiré proprement, soit affiché avec un état « indisponible » explicite — jamais un crash ou une fiche vide cassée.

- [ ] Passé — date / appareil / version :

### E13 — Disque retiré de la wantlist sur Discogs.com, consulté hors ligne `AUDIT` `RÉGRESSION`

**Conditions** : Élément présent dans la wantlist de l'app.

**Étapes** :

1. Retirer cet élément de la wantlist sur discogs.com.
2. Dans l'app, rafraîchir la wantlist et la faire défiler jusqu'en bas.
3. Activer le mode avion et relancer l'app.

**Résultat attendu** : L'élément a disparu en ligne ET reste absent hors ligne (cache local remplacé, pas seulement complété).

- [ ] Passé — date / appareil / version :

### E14 — Retrait bloqué hors ligne (cache de plus de 6 h) `AUDIT` `RÉGRESSION`

**Conditions** : Mode avion + cache wantlist périmé (Options développeur).

**Étapes** :

1. Tenter de retirer un élément de la wantlist.
2. Relancer l'app, toujours hors ligne.

**Résultat attendu** : Message de blocage ; l'élément reste dans la liste ET dans le cache après relancement (il ne disparaît plus en silence).

- [ ] Passé — date / appareil / version :

### E15 — Déplacement wantlist → collection hors ligne : bon dossier `AUDIT` `RÉGRESSION`

**Conditions** : Plusieurs dossiers Discogs, mode avion activé.

**Étapes** :

1. Déplacer un élément de la wantlist vers la collection, dossier X.
2. Rétablir le réseau et attendre la synchronisation.
3. Vérifier sur discogs.com.

**Résultat attendu** : Le disque est ajouté dans le dossier X (et non dans « Uncategorized »).

- [ ] Passé — date / appareil / version :

### E16 — Ajout à la wantlist avec Discogs injoignable `AUDIT`

**Conditions** : Network Link Conditioner sur « 100% Loss ».

**Étapes** :

1. Ajouter un disque à la wantlist depuis la recherche.
2. Rétablir le réseau.

**Résultat attendu** : Message « Discogs ne répond pas… » ; le disque reste affiché dans la wantlist et y est ajouté sur discogs.com au retour du réseau.

- [ ] Passé — date / appareil / version :

### E17 — Wantlist : messages d'action visibles `AUDIT` `RÉGRESSION`

**Conditions** : Wantlist chargée, données de plus de 6 h, mode avion activé.

**Étapes** :

1. Tenter de retirer un souhait.
2. En mode démo, tenter « Ajouter à la collection » depuis un souhait.

**Résultat attendu** : Une alerte s'affiche à chaque fois (« Mode hors ligne… : modification bloquée », message de démo). Avant correction, ces messages n'apparaissaient que si la wantlist était vide.

- [ ] Passé — date / appareil / version :

### E18 — Wantlist : refus définitif de Discogs `AUDIT` `LIMITE`

**Conditions** : Disque de la wantlist retiré entre-temps sur discogs.com, ou compte sans droit (provoquer un refus).

**Étapes** :

1. Retirer un disque de la wantlist dont Discogs refuse le retrait.
2. Déplacer vers la collection un disque dont Discogs refuse l'ajout.

**Résultat attendu** : Retrait refusé : le disque réapparaît et un message l'explique (plus de mise en file qui échouait plusieurs fois). Déplacement refusé : le disque reste dans la wantlist avec un message, au lieu de disparaître des deux listes. Un disque déjà absent sur Discogs est simplement retiré.

- [ ] Passé — date / appareil / version :

### E19 — Liste courte : la barre d'onglets réduite revient en tirant vers le bas `AUDIT`

**Conditions** : Wantlist (et Collection filtrée) de quelques disques seulement, qui tient entièrement à l'écran.

**Étapes** :

1. Ouvrir une fiche depuis la liste, y défiler vers le bas (la barre d'onglets se réduit), puis revenir en arrière.
2. Tirer légèrement la liste vers le bas.
3. Refaire en modes Liste, Mosaïque et Carrousel, sur la Wantlist puis sur la Collection.

**Résultat attendu** : Même quand la liste est courte, elle rebondit sous le doigt et ce léger tirage vers le bas ramène la barre d'onglets à sa taille normale presque aussitôt (sans plus de délai que le défilement normal), dans les modes Liste et Mosaïque ; sans à-coup ni clignotement de la barre. En Carrousel, le rebond est possible mais le retour de la barre peut rester plus lent. Une liste longue se comporte comme avant.

- [ ] Passé — date / appareil / version :

### E20 — « Alerte de prix » : grand champ, tuiles de marché, jauge et pastilles `AUDIT` `AUTO`

**Conditions** : Disque de la wantlist avec des offres en vente (puis un sans offre) ; compte Premium.

**Étapes** :

1. Ouvrir « Alerte de prix » depuis la wantlist.
2. Saisir un prix maximum plus bas que le prix le plus bas en ligne, puis plus haut.
3. Toucher les pastilles -10 %, -20 %, -30 % et une cote par état.
4. Enregistrer, rouvrir, supprimer l'alerte.
5. Essayer sans offre en vente, hors ligne, thème sombre, police agrandie.

**Résultat attendu** : Pendant le chargement du marché, des squelettes animés (tuiles, jauge si un prix est déjà saisi, pastilles de cotes) occupent la place du contenu, sans saut de mise en page à l'arrivée des données (animation figée avec Réduire les animations). Le prix maximum se saisit dans un grand champ rose, le montant exactement centré dans sa carte (devise à côté, pas de saut de curseur). Deux tuiles montrent le nombre d'offres et l'annonce la moins chère (tous états confondus). Dès qu'un prix est saisi, la jauge apparaît juste sous le champ (visible au-dessus du clavier, elle suit la saisie en direct) et place « Mon seuil » et « Annonce la moins chère » : texte « Il manque X (Y %) pour atteindre ton seuil » sous le seuil, « Seuil atteint » en vert au-dessus, « Aucune annonce » sans vente. Le pied de page explique que l'alerte se base sur l'annonce la moins chère et que les cotes par état (ventes passées) peuvent être plus basses sans offre à ce prix. Toucher la tuile « Annonce la moins chère » (flèche en haut à droite) ouvre la même page Discogs que « Consulter les annonces sur Discogs.com » en bas. Les pastilles appliquent leur prix et la pastille de la cote par état correspondant au prix saisi est mise en évidence. Un seul toucher sur le champ (ou n'importe où dans sa carte rose) suffit pour le sélectionner, y compris juste après l'ouverture ; le curseur se place toujours à la fin du montant, même sur un prix déjà saisi ou une alerte existante, pour le corriger à la suite. Le clavier se ferme avec « OK », au défilement ou au glissé. « OK » (enregistrer) reste dans la barre d'outils ; le bouton du clavier se nomme « Terminé ». Le fond prend la teinte de la pochette. La feuille s'ouvre en grand (pleine hauteur), comme « Mon exemplaire ».

- [ ] Passé — date / appareil / version :

### E21 — « Alerte de prix » : entrée en séquence, jauge glissante, prix qui roule, seuil atteint `AUDIT`

**Conditions** : Disque de la wantlist avec des annonces et des cotes par état ; compte Premium ; Réduire les animations désactivé puis activé ; iPhone réel pour les retours haptiques.

**Étapes** :

1. Ouvrir « Alerte de prix » sur un disque sans alerte, puis sur un disque avec une alerte existante.
2. Observer l'arrivée du marché (tuiles, pastilles de cotes) après le squelette.
3. Taper un prix au clavier, chiffre après chiffre, en dessous puis au-dessus de l'annonce la moins chère.
4. Toucher une pastille (-10 %, une cote par état).
5. Franchir le prix de l'annonce la moins chère en tapant, puis redescendre.
6. Toucher le champ de prix, puis fermer le clavier (« OK »).
7. Refaire avec Réduire les animations activé.

**Résultat attendu** : Le squelette laisse place aux deux tuiles qui montent l'une après l'autre, puis la jauge se remplit jusqu'au seuil et les pastilles défilent en cascade (une seule fois par ouverture). Pendant la saisie, les repères de la jauge glissent d'une valeur à l'autre sans sauter. Une pastille se tasse sous le doigt avec un rebond, et le grand prix fait défiler ses chiffres de l'ancienne valeur à la nouvelle en gonflant légèrement, un cran haptique léger accompagnant le toucher. Au moment où le seuil rejoint l'annonce la moins chère : repère qui rebondit, retour haptique de succès et brève lueur verte autour du prix (une seule fois par franchissement, pas à l'ouverture ni au chargement du marché). Le champ de prix s'entoure d'un halo rose qui respire tant qu'il a le focus et s'éteint à la fermeture du clavier. Une cloche sur la jaquette (grise sans alerte, rose si l'alerte est active, verte si elle est déclenchée, comme dans la liste de la Wantlist) balance une fois peu après l'ouverture. Avec Réduire les animations : tout est direct, sans rebond, défilement ni lueur.

- [ ] Passé — date / appareil / version :

### E22 — Wantlist : retour visuel au toucher de la cloche d'alerte `AUDIT`

**Conditions** : Compte Premium ; Wantlist en affichage Liste puis Carrousel ; Réduire les animations désactivé puis activé.

**Étapes** :

1. En Liste : toucher la cloche d'une ligne (sans alerte, avec alerte active, avec alerte déclenchée).
2. Maintenir le doigt un instant avant de relâcher, puis faire un toucher bref.
3. En Carrousel : toucher la cloche posée en bas à droite de la jaquette (sans alerte, active, déclenchée).
4. Refaire avec Réduire les animations activé, et sans compte Premium.

**Résultat attendu** : Sous le doigt, la cloche se tasse et une pastille rose s'allume derrière elle ; au relâchement elle rebondit (et la cloche fait un rebond de symbole en Liste) avec un léger retour haptique, puis la feuille « Alerte de prix » s'ouvre (ou l'offre Premium sans abonnement). En Carrousel, la cloche (sur un disque clair en thème clair et sombre en thème sombre, aux mêmes couleurs qu'en Liste : grise, rose, verte) se tasse de même, sans ouvrir la fiche du disque ; il n'y a plus de capsule sous la jaquette. Avec Réduire les animations : seule la pastille rose s'allume, sans changement d'échelle ni rebond de symbole. Le toucher reste facile à atteindre (zone de toucher inchangée).

- [ ] Passé — date / appareil / version :

### E23 — Alerte de prix : le titre « Mon seuil d'alerte » remonte au focus du prix `AUDIT`

**Conditions** : Compte Premium ; feuille « Alerte de prix » ouverte ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Toucher le champ « Prix maximum ».
2. Observer le défilement pendant l'apparition du clavier.
3. Appuyer sur « OK » du clavier, puis refaire avec Réduire les animations activé.

**Résultat attendu** : Le titre de la section « Mon seuil d'alerte » est aligné en haut de l'écran : champ, jauge et pastilles de prix restent visibles au-dessus du clavier. Avec Réduire les animations, le défilement se fait sans animation. Sur une feuille trop courte pour défiler, rien ne bouge et le champ reste utilisable.

- [ ] Passé — date / appareil / version :

### E24 — Alerte de prix : suppression depuis le bouton sous le champ du seuil, avec confirmation `AUDIT`

**Conditions** : Compte Premium ; disque de la Wantlist ayant déjà une alerte ; feuille « Alerte de prix » ouverte.

**Étapes** :

1. Repérer le bouton « Supprimer cette alerte » sous le champ « Prix maximum » (après la jauge et les raccourcis), sans défiler.
2. Le toucher, puis choisir d'annuler la confirmation.
3. Le toucher de nouveau et confirmer.
4. Ouvrir la feuille d'un disque sans alerte.

**Résultat attendu** : Une confirmation « Supprimer cette alerte ? » apparaît avant toute suppression ; en annulant, l'alerte et la feuille restent inchangées. En confirmant, l'alerte est supprimée (cloche grise en Liste et en Carrousel) et la feuille se ferme. Le bouton n'existe plus en bas de la feuille et n'apparaît pas pour un disque sans alerte.

- [ ] Passé — date / appareil / version :

### E25 — Retrait depuis la fiche : le disque ne revient pas dans la liste `AUDIT` `AUTO`

**Conditions** : Compte réel avec un disque en wantlist ; réseau actif.

**Étapes** :

1. Ouvrir l'onglet Wantlist, puis la fiche d'un disque.
2. Toucher le cœur « Wantlist » et confirmer « Supprimer de la wantlist ».
3. Revenir à la liste, attendre 10 s, changer d'onglet et revenir.
4. Tirer la liste vers le bas pour rafraîchir.

**Résultat attendu** : Le disque disparaît de la liste dès le retour et ne réapparaît ni après l'attente, ni après le changement d'onglet, ni après le rafraîchissement ; le compteur de l'onglet Stats baisse d'un. Après un relancement de l'app, il reste absent. (Couvert en partie par WantlistRemovalTests.)

- [ ] Passé — date / appareil / version :

### E26 — Écrans vides et écran de connexion : pochettes tirées au hasard `AUDIT`

**Conditions** : Compte sans disque en collection ni en wantlist ; thèmes clair et sombre ; une fois avec « Réduire les animations » (Accessibilité).

**Étapes** :

1. Ouvrir l'onglet Collection, puis Wantlist, et observer l'illustration.
2. Quitter l'onglet et y revenir plusieurs fois.
3. Toucher « Cherche ou scanne un album ».
4. Activer « Réduire les animations » et rouvrir les deux onglets.
5. Se déconnecter (ou relancer l'app déconnecté) plusieurs fois et observer les pochettes qui flottent sur l'écran de connexion.

**Résultat attendu** : 1 : Collection : 3 à 4 pochettes arrivent l'une après l'autre en éventail derrière le disque qui tourne, puis ne bougent plus ; Wantlist : des pochettes et des cœurs montent lentement en s'estompant autour du disque, sans être rognés sur les côtés. Le texte indique de rechercher (artiste, titre, label, code-barres) ou de scanner. 2 : les pochettes changent d'une visite à l'autre. 3 : l'onglet Recherche s'ouvre. 4 : plus aucun mouvement, les pochettes sont visibles d'emblée. 5 : les pochettes de l'écran de connexion changent d'une apparition à l'autre. Les 21 pochettes embarquées (WelcomeCover1 à 21) peuvent toutes apparaître ; aucune image manquante ni vide.

- [ ] Passé — date / appareil / version :

<a id="famille-f"></a>

## F — Wantlist — Sélection multiple & alertes de prix

### F1 — Entrer en mode sélection wantlist

**Conditions** : Wantlist non vide.

**Étapes** :

1. Menu «... » → Sélectionner.

**Résultat attendu** : Cases à cocher animées apparaissent sur chaque ligne.

- [ ] Passé — date / appareil / version :

### F2 — Suppression groupée

**Conditions** : Plusieurs éléments sélectionnés.

**Étapes** :

1. Barre d'action Liquid Glass → icône corbeille.

**Résultat attendu** : Confirmation avec le bon nombre d'éléments (singulier/pluriel) ; suppression effective après confirmation.

- [ ] Passé — date / appareil / version :

### F3 — Annuler la suppression groupée

**Conditions** : Dialogue de confirmation affiché.

**Étapes** :

1. Toucher Annuler.

**Résultat attendu** : Aucun élément supprimé.

- [ ] Passé — date / appareil / version :

### F4 — Créer une alerte de prix `PREMIUM`

**Conditions** : Compte premium, élément en wantlist.

**Étapes** :

1. Toucher l'icône cloche → définir un prix cible → enregistrer.

**Résultat attendu** : Alerte créée, icône cloche pleine visible sur la ligne.

- [ ] Passé — date / appareil / version :

### F5 — Notification reçue au prix cible `PREMIUM`

**Conditions** : Alerte active dont le prix cible est atteignable sur le marketplace.

**Étapes** :

1. Attendre une vérification (ouverture de l'app ou rafraîchissement en arrière-plan).

**Résultat attendu** : Notification locale reçue, icône cloche passe à l'état « déclenchée ».

- [ ] Passé — date / appareil / version :

### F6 — Icône cloche reflète l'état de l'alerte `PREMIUM`

**Conditions** : Alertes à différents états (aucune / active / déclenchée).

**Étapes** :

1. Observer l'icône sur chaque ligne concernée.

**Résultat attendu** : Icône vide / pleine / avec badge selon l'état exact de l'alerte.

- [ ] Passé — date / appareil / version :

### F7 — Suppression d'une alerte `PREMIUM`

**Conditions** : Alerte active.

**Étapes** :

1. Ouvrir la feuille d'alerte → supprimer.

**Résultat attendu** : L'alerte disparaît, plus aucune notification pour cet élément.

- [ ] Passé — date / appareil / version :

### F8 — Tentative de création d'alerte — non premium `PREMIUM`

**Conditions** : Compte non premium.

**Étapes** :

1. Toucher l'icône cloche sur un élément de la wantlist.

**Résultat attendu** : Carte verrouillée / paywall affiché, aucune alerte créée.

- [ ] Passé — date / appareil / version :

### F9 — Prix cible nul ou négatif `LIMITE` `PREMIUM`

**Conditions** : Feuille de création d'alerte ouverte.

**Étapes** :

1. Saisir 0, une valeur négative, ou laisser le champ vide, puis valider.

**Résultat attendu** : Validation refusée avec message clair ; aucune alerte invalide enregistrée.

- [ ] Passé — date / appareil / version :

### F10 — Alerte sur un release sans aucune offre `LIMITE` `PREMIUM`

**Conditions** : Release présent en wantlist mais absent du marketplace Discogs.

**Étapes** :

1. Créer une alerte sur cet élément.
2. Déclencher une vérification.

**Résultat attendu** : Aucune notification envoyée ; pas d'erreur visible pour l'utilisateur, l'alerte reste simplement « en attente ».

- [ ] Passé — date / appareil / version :

### F11 — Devise de l'alerte différente de celle du marketplace `LIMITE` `PREMIUM`

**Conditions** : Alerte créée en EUR sur un release vendu en USD.

**Étapes** :

1. Déclencher une vérification avec une offre proche du seuil après conversion.

**Résultat attendu** : La conversion de devise est appliquée avant comparaison au seuil ; déclenchement cohérent avec le prix converti.

- [ ] Passé — date / appareil / version :

### F12 — Deux alertes déclenchées simultanément `LIMITE` `PREMIUM`

**Conditions** : Deux alertes actives dont les seuils sont atteints au même moment (vérification groupée).

**Étapes** :

1. Déclencher une vérification couvrant les deux.

**Résultat attendu** : Les deux notifications sont envoyées correctement, sans que l'une n'empêche ou ne retarde indéfiniment l'autre.

- [ ] Passé — date / appareil / version :

### F13 — Vérification en arrière-plan exécutée (simulation) `AUDIT` `PREMIUM` `DEV`

**Conditions** : Alertes actives, app lancée depuis Xcode puis mise en arrière-plan.

**Étapes** :

1. Mettre l'app en pause dans le débogueur.
2. Exécuter : `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.aurelienscarpa.Spinlog.wantlistAlertsCheck"]`
3. Reprendre l'exécution.

**Résultat attendu** : La vérification s'exécute (dernier prix constaté et date de vérification mis à jour) et une nouvelle vérification est planifiée.

- [ ] Passé — date / appareil / version :

### F14 — Vérification jamais repoussée par un usage fréquent `AUDIT` `RÉGRESSION` `PREMIUM`

**Conditions** : Alertes actives, actualisation en arrière-plan autorisée.

**Étapes** :

1. Pendant 24 h, ouvrir et quitter l'app toutes les 1 à 2 h.
2. Consulter la date de dernière vérification des alertes.

**Résultat attendu** : Au moins une vérification a eu lieu en arrière-plan dans les 24 h (auparavant, chaque passage en arrière-plan repoussait la vérification de 3 h).

- [ ] Passé — date / appareil / version :

### F15 — Expiration de la tâche de fond pendant la vérification `AUDIT` `PREMIUM` `DEV` `LIMITE`

**Conditions** : Nombreuses alertes (10+), vérification lancée comme en F13.

**Étapes** :

1. Pendant la vérification, exécuter dans le débogueur : `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.aurelienscarpa.Spinlog.wantlistAlertsCheck"]`
2. Relancer une vérification complète.

**Résultat attendu** : L'app n'est pas tuée ; les alertes déjà vérifiées restent enregistrées ; aucune notification déjà envoyée n'est renvoyée à la vérification suivante.

- [ ] Passé — date / appareil / version :

### F16 — Vérification iPhone verrouillé `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Alertes actives, iPhone verrouillé depuis au moins 10 minutes (après un premier déverrouillage depuis le redémarrage).

**Étapes** :

1. Laisser une vérification en arrière-plan se produire iPhone verrouillé (ou F13 avec l'écran verrouillé).

**Résultat attendu** : La vérification réussit (requêtes Discogs authentifiées) ; aucun « Échec de lecture Keychain » dans la console.

- [ ] Passé — date / appareil / version :

### F17 — Pas de notification en double `AUDIT` `PREMIUM`

**Conditions** : Alerte déjà déclenchée et notifiée, prix inchangé.

**Étapes** :

1. Relancer plusieurs vérifications.

**Résultat attendu** : Aucune nouvelle notification tant que le prix ne baisse pas ; une seule notification par disque dans le Centre de notifications (une nouvelle bonne affaire remplace la précédente).

- [ ] Passé — date / appareil / version :

### F18 — Alerte réarmée après remontée du prix `AUDIT` `PREMIUM`

**Conditions** : Alerte notifiée, puis prix le plus bas repassé au-dessus du prix cible (ou plus aucune offre).

**Étapes** :

1. Lancer une vérification (prix au-dessus du seuil).
2. Plus tard, le prix redescend sous le seuil : lancer une vérification.

**Résultat attendu** : Une nouvelle notification est envoyée, même si le prix est identique à celui déjà notifié auparavant.

- [ ] Passé — date / appareil / version :

### F19 — Modifier le prix cible pendant une vérification `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Vérification de nombreuses alertes en cours (réseau lent conseillé).

**Étapes** :

1. Pendant la vérification, modifier le prix cible d'une alerte et enregistrer.
2. Rouvrir l'alerte une fois la vérification terminée.

**Résultat attendu** : Le nouveau prix cible est conservé (il n'est pas écrasé par la vérification en cours).

- [ ] Passé — date / appareil / version :

### F20 — Supprimer une alerte retire sa notification `AUDIT` `PREMIUM`

**Conditions** : Notification d'alerte présente dans le Centre de notifications.

**Étapes** :

1. Supprimer l'alerte dans l'app.
2. Ouvrir le Centre de notifications.

**Résultat attendu** : La notification de ce disque a disparu.

- [ ] Passé — date / appareil / version :

### F21 — Notifications refusées `LIMITE` `PREMIUM`

**Conditions** : Autorisation de notifications refusée dans Réglages iOS.

**Étapes** :

1. Créer une alerte dont le seuil est atteint.
2. Lancer une vérification.

**Résultat attendu** : L'alerte est créée et l'état « déclenchée » visible dans l'app ; indication claire que les notifications sont désactivées ; aucun crash.

- [ ] Passé — date / appareil / version :

### F22 — Actualisation en arrière-plan désactivée `AUDIT` `LIMITE` `PREMIUM`

**Conditions** : Réglages iOS › Général › Actualisation en arrière-plan désactivée pour l'app.

**Étapes** :

1. Créer une alerte, puis fermer l'app (balayage).
2. Rouvrir l'app plus de 15 minutes plus tard.
3. Consulter la date de dernière vérification de l'alerte.

**Résultat attendu** : Une vérification complète des alertes est lancée à l'ouverture de l'app (lancement ou retour au premier plan) : la date de dernière vérification est mise à jour, et une notification est envoyée si un seuil est atteint — même sans actualisation en arrière-plan.

- [ ] Passé — date / appareil / version :

### F23 — Ouvertures rapprochées : pas de vérification en rafale `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Plusieurs alertes actives ; proxy HTTP (Proxyman) facultatif pour compter les requêtes.

**Étapes** :

1. Ouvrir l'app (une vérification part).
2. Dans les 15 minutes suivantes, quitter et rouvrir l'app plusieurs fois.

**Résultat attendu** : Aucune nouvelle vérification n'est relancée avant 15 minutes après la dernière vérification complète (premier plan ou arrière-plan) : pas de rafale de requêtes /marketplace/stats, le reste de l'app reste réactif.

- [ ] Passé — date / appareil / version :

### F24 — Suppression en lot : tout disparaît d'un coup, Discogs en arrière-plan `AUDIT`

**Conditions** : Compte connecté (hors démo) ; Collection puis Wantlist avec au moins 10 éléments ; en ligne, puis hors ligne, puis réseau lent ; un disque en deux exemplaires dans la Collection.

**Étapes** :

1. Passer en sélection multiple, cocher une dizaine d'éléments (dont les deux exemplaires du même disque), supprimer et confirmer.
2. Observer la liste pendant et juste après la confirmation.
3. Refaire hors ligne, puis avec un réseau lent (ou en coupant le réseau après la confirmation).
4. Rouvrir l'écran puis recharger depuis Discogs.

**Résultat attendu** : Dès la confirmation, le mode sélection se ferme et tous les éléments choisis disparaissent ensemble (un seul fondu), sans attendre le réseau ni disparaître un par un. Discogs est mis à jour en arrière-plan, un élément après l'autre ; hors ligne ou en cas de panne passagère, les retraits sont mis en file puis rejoués. Un refus définitif de Discogs réaffiche l'élément concerné avec un message. Après rechargement, l'état correspond à Discogs. Les disques absents de la Collection ne réapparaissent plus dans les fiches (badges « En collection »).

- [ ] Passé — date / appareil / version :

<a id="famille-g"></a>

## G — Recherche & Scan

### G1 — Recherche texte (artiste, album, label, master)

**Conditions** : Réseau disponible.

**Étapes** :

1. Onglet Recherche → taper un terme.

**Résultat attendu** : Résultats pertinents affichés, regroupés par type.

- [ ] Passé — date / appareil / version :

### G2 — Scan code-barres simple

**Conditions** : Un disque avec code-barres valide à disposition.

**Étapes** :

1. Lancer le scan → viser le code-barres.

**Résultat attendu** : Le bon release est identifié et proposé pour ajout à la Collection ou la Wantlist.

- [ ] Passé — date / appareil / version :

### G3 — Scan par lot `PREMIUM`

**Conditions** : Compte premium, plusieurs disques à scanner.

**Étapes** :

1. Lancer « Scan par lot » → scanner plusieurs codes successivement → choisir le dossier → passer en revue → valider l'ajout.

**Résultat attendu** : Tous les codes scannés sont listés dans la revue ; l'ajout final répartit correctement vers Collection ou Wantlist selon le choix.

- [ ] Passé — date / appareil / version :

### G4 — Tentative de scan par lot — non premium `PREMIUM`

**Conditions** : Compte non premium.

**Étapes** :

1. Essayer d'accéder au Scan par lot.

**Résultat attendu** : Carte verrouillée / paywall affiché.

- [ ] Passé — date / appareil / version :

### G5 — Choix du pressage (plusieurs résultats pour un code-barres)

**Conditions** : Code-barres correspondant à plusieurs pressages.

**Étapes** :

1. Scanner un tel code-barres.

**Résultat attendu** : Écran « Choisir le pressage » affiché avec la liste des pressages candidats.

- [ ] Passé — date / appareil / version :

### G6 — Aucun disque trouvé

**Conditions** : Code-barres invalide ou non référencé.

**Étapes** :

1. Scanner ce code.

**Résultat attendu** : Message « Aucun disque trouvé », pas de crash, possibilité de réessayer.

- [ ] Passé — date / appareil / version :

### G7 — Fiches Artiste / Label / Master

**Conditions** : Résultat de recherche pertinent.

**Étapes** :

1. Toucher un artiste, puis un label, puis un master depuis les résultats.

**Résultat attendu** : Chaque fiche détail s'ouvre avec les informations et la discographie associée.

- [ ] Passé — date / appareil / version :

### G8 — Recherche vide ou uniquement des espaces `LIMITE`

**Conditions** : Champ de recherche vide.

**Étapes** :

1. Valider une recherche vide ou composée uniquement d'espaces.

**Résultat attendu** : Aucune requête réseau inutile envoyée, ou résultat neutre sans erreur affichée.

- [ ] Passé — date / appareil / version :

### G9 — Scan du même code-barres deux fois rapidement `LIMITE`

**Conditions** : Scan simple en cours.

**Étapes** :

1. Scanner deux fois de suite très rapidement le même disque.

**Résultat attendu** : Pas d'ajout en double ; la deuxième détection est soit ignorée, soit redemande confirmation.

- [ ] Passé — date / appareil / version :

### G10 — Scan en mauvaises conditions (flou, code partiel) `LIMITE`

**Conditions** : Code-barres partiellement masqué ou image floue.

**Étapes** :

1. Tenter le scan dans ces conditions.

**Résultat attendu** : Pas de faux positif (mauvais disque identifié) ; l'app continue d'essayer ou signale l'échec sans se bloquer.

- [ ] Passé — date / appareil / version :

### G11 — Perte réseau en pleine recherche `LIMITE`

**Conditions** : Recherche texte en cours d'exécution.

**Étapes** :

1. Activer le mode avion juste après avoir lancé la recherche.

**Résultat attendu** : Message d'erreur réseau clair ; la recherche peut être relancée normalement au retour du réseau.

- [ ] Passé — date / appareil / version :

### G12 — Valider le scan par lot avec 0 code scanné `LIMITE` `PREMIUM`

**Conditions** : Écran de revue du scan par lot ouvert sans avoir scanné quoi que ce soit.

**Étapes** :

1. Toucher le bouton de validation.

**Résultat attendu** : Bouton désactivé ou message explicite ; aucun ajout vide déclenché.

- [ ] Passé — date / appareil / version :

### G13 — Frappe rapide pendant une recherche `AUDIT` `RÉGRESSION`

**Conditions** : Collection en cours de chargement (forte activité réseau).

**Étapes** :

1. Taper, effacer et retaper rapidement plusieurs termes de recherche.

**Résultat attendu** : Jamais de message d'erreur technique (« CancellationError ») ; les résultats affichés correspondent toujours au dernier texte saisi, jamais à une recherche précédente.

- [ ] Passé — date / appareil / version :

### G14 — Ouverture rapide de l'onglet Recherche `AUDIT`

**Conditions** : Grande collection et grande wantlist.

**Étapes** :

1. Ouvrir l'onglet Recherche à plusieurs reprises.
2. Rechercher un disque possédé et un disque en wantlist.

**Résultat attendu** : Ouverture instantanée ; les indicateurs « en collection » / « en wantlist » sont corrects.

- [ ] Passé — date / appareil / version :

### G15 — Scan par lot : ajouts rapprochés puis tags `AUDIT` `RÉGRESSION` `PREMIUM`

**Conditions** : 5+ disques à scanner.

**Étapes** :

1. Scanner les disques et valider l'ajout groupé à la collection.
2. Ajouter un tag différent à chacun.

**Résultat attendu** : Tous les disques sont ajoutés ; chacun garde uniquement son tag (aucun mélange de tags entre disques ajoutés dans la même seconde) ; aucun disque ne disparaît.

- [ ] Passé — date / appareil / version :

### G16 — Quota Discogs sous forte charge `AUDIT` `LIMITE`

**Conditions** : Réseau disponible, compte avec grande collection.

**Étapes** :

1. Lancer simultanément : téléchargement hors ligne complet, ouverture de Stats, plusieurs recherches.

**Résultat attendu** : Aucune erreur « Trop de requêtes » ni erreur d'authentification ; tout finit par se charger (un ralentissement est acceptable).

- [ ] Passé — date / appareil / version :

### G17 — Scan par lot : codes conservés après fermeture de l'app `AUDIT` `PREMIUM`

**Conditions** : Compte premium, réseau disponible.

**Étapes** :

1. Ouvrir le scan par lot et scanner 3 codes-barres.
2. Fermer l'app depuis le sélecteur d'apps, la rouvrir.
3. Rouvrir le scan par lot.

**Résultat attendu** : Les 3 codes sont retrouvés, de nouveau recherchés sur Discogs, avec le pressage choisi à la main conservé.

- [ ] Passé — date / appareil / version :

### G18 — Scan par lot : perte de réseau pendant le scan `AUDIT` `PREMIUM` `RÉGRESSION`

**Conditions** : Compte premium, scan par lot ouvert avec quelques codes.

**Étapes** :

1. Activer le mode avion et scanner 2 codes de plus.
2. Désactiver le mode avion.

**Résultat attendu** : L'écran reste ouvert avec un bandeau « Hors ligne » ; les nouveaux codes restent « en cours de recherche » (jamais « introuvable ») puis se résolvent au retour du réseau. Avant correction, l'écran se fermait et le lot était perdu.

- [ ] Passé — date / appareil / version :

### G19 — Scan par lot : confirmation de fermeture `AUDIT` `PREMIUM`

**Conditions** : Scan par lot ouvert avec au moins un code.

**Étapes** :

1. Toucher « Annuler », puis tester chaque choix : « Fermer et garder les codes », « Supprimer les codes scannés », « Continuer ».
2. Tenter aussi de fermer la revue par glissement vers le bas.

**Résultat attendu** : La confirmation apparaît dans tous les cas (le glissement est bloqué). Garder : codes retrouvés à la réouverture. Supprimer : liste vide. Sans aucun code, fermeture directe sans question.

- [ ] Passé — date / appareil / version :

### G20 — Caméra refusée : explication au lieu d'un écran noir `AUDIT`

**Conditions** : Réglages iOS → Spinfolio → Appareil photo désactivé.

**Étapes** :

1. Recherche → icône de scan.
2. Toucher « Ouvrir les Réglages », autoriser la caméra, revenir dans l'app.
3. Refaire l'essai avec le scan par lot.

**Résultat attendu** : « Accès à la caméra refusé » avec le bouton « Ouvrir les Réglages » (scan simple et scan par lot) ; au retour, le scanner s'affiche sans rouvrir l'écran. Premier lancement : la demande d'autorisation système apparaît.

- [ ] Passé — date / appareil / version :

### G21 — Scan par lot : bilan honnête des ajouts `AUDIT` `LIMITE` `AUTO`

**Conditions** : Scan par lot avec au moins 3 codes trouvés.

**Étapes** :

1. Ajouter la sélection à la collection en mode avion.
2. Recommencer en ligne avec un code dont l'ajout échoue (ex. compte non autorisé / release refusée).

**Résultat attendu** : Mode avion : « N disques ajoutés » suivi de « N disques en attente de synchronisation avec Discogs ». Échec : les codes refusés restent dans la liste et le bilan les signale ; seuls les codes ajoutés disparaissent.

- [ ] Passé — date / appareil / version :

### G22 — Recherche : bouton Réessayer `AUDIT`

**Conditions** : Recherche Discogs qui échoue (réseau coupé juste après la saisie, ou code-barres introuvable).

**Étapes** :

1. Lancer une recherche texte qui échoue, toucher « Réessayer ».
2. Scanner un code-barres inconnu, toucher « Réessayer ».

**Résultat attendu** : « Réessayer » relance la même recherche (texte ou code-barres) ; les résultats s'affichent si la cause a disparu.

- [ ] Passé — date / appareil / version :

### G23 — Scan par lot : retour visuel d'un code reconnu `AUDIT`

**Conditions** : Compte Premium, caméra autorisée, quelques disques avec code-barres ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir le scan par lot et attendre sans rien viser.
2. Scanner un code-barres reconnu par Discogs.
3. Scanner un second disque dans les 2 s.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : En attente : quatre coins de visée qui respirent doucement. À chaque code lu : haptique de succès, éclair vert bref sur le pourtour de l'écran, rebond du compteur. Dès que le disque est identifié, une pastille (pochette, titre, coche verte) monte au-dessus du compteur, reste environ 2 s puis disparaît ; un second scan la remplace sans chevauchement. Les codes restaurés d'un brouillon n'affichent pas de pastille. Avec Réduire les animations : coins immobiles, pas de rebond, pastille en simple fondu ; l'éclair et l'haptique restent.

- [ ] Passé — date / appareil / version :

### G24 — Recherche : suggestions qui tournent dans le champ `AUDIT`

**Conditions** : Onglet Recherche, champ vide ; Réduire les animations désactivé puis activé ; VoiceOver pour le dernier point.

**Étapes** :

1. Ouvrir la Recherche sans toucher le champ et attendre une quinzaine de secondes.
2. Toucher le champ (le garder vide), puis saisir une lettre, puis l'effacer.
3. Refaire avec Réduire les animations activé.
4. Avec VoiceOver, se placer sur le champ.

**Résultat attendu** : Le texte d'invite change toutes les 3 s en glissant vers le haut (l'invite d'origine « Artiste, disque, label, code-barre… », puis artiste, album, label, code-barres, et retour au début). La rotation s'arrête pendant la saisie ou quand le champ a le focus, et le texte disparaît dès qu'une lettre est saisie ; elle repart champ vide et au repos. Avec Réduire les animations : l'invite d'origine reste fixe. VoiceOver annonce toujours « Artiste, disque, label, code-barre… », jamais les suggestions.

- [ ] Passé — date / appareil / version :

### G25 — Scan par lot : retour à l'onglet de destination après l'ajout `AUDIT`

**Conditions** : Compte Premium connecté (hors démo), quelques disques scannés et reconnus.

**Étapes** :

1. Dans la revue du scan, ajouter tous les disques à la collection, puis fermer le bilan par OK.
2. Refaire un lot et l'ajouter à la wantlist.
3. Refaire avec un lot dont un disque est décoché, puis avec un ajout qui échoue.

**Résultat attendu** : Après OK, le scan par lot se ferme et l'app affiche l'onglet Collection (ajout en collection) ou Wantlist (ajout en wantlist). Si des codes restent dans la liste (décochés ou en échec), le scan reste ouvert sur la revue, sans changer d'onglet.

- [ ] Passé — date / appareil / version :

### G26 — Scan par lot : codes non reconnus à part, retirés en fin de lot `AUDIT`

**Conditions** : Compte Premium connecté (hors démo), un code-barres inconnu de Discogs et quelques disques reconnus scannés ; réseau actif.

**Étapes** :

1. Scanner un code inconnu et deux disques reconnus, puis toucher « Terminer ».
2. Dans la revue, toucher « Réessayer » sur le code inconnu, puis le retirer (balayage ou appui long) ; le rescanner.
3. Ajouter un seul des deux disques reconnus à la collection (l'autre décoché), fermer le bilan par OK.
4. Ajouter le dernier disque à la wantlist, fermer le bilan par OK.

**Résultat attendu** : Le code inconnu apparaît dans une section « Non reconnus (1) » sous les disques reconnus ; « Terminer (N) » ne compte que les codes reconnus ou en cours de recherche, et est grisé s'il n'y en a aucun. Étape 3 : il reste un disque à traiter, donc le code non reconnu est conservé et le scan reste ouvert. Étape 4 : le lot est terminé, le bilan ajoute « 1 code non reconnu retiré de la liste. », le code disparaît (aussi du brouillon à la réouverture), le scan se ferme et l'onglet Wantlist s'affiche.

- [ ] Passé — date / appareil / version :

### G27 — Scan par lot : transitions des lignes et des compteurs `AUDIT`

**Conditions** : Compte Premium (hors démo), quelques codes dont un inconnu de Discogs ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Scanner plusieurs codes et observer « Terminer (N) » à chaque scan.
2. Ouvrir la revue : observer les lignes qui passent de « Recherche en cours… » à un disque trouvé, ou à « Aucun disque trouvé ».
3. Retirer une ligne (balayage ou appui long), réessayer un code non reconnu, ajouter les disques et laisser purger les codes non reconnus.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : Les chiffres de « Terminer (N) » et de « Non reconnus (N) » roulent d'une valeur à l'autre. Dans la revue, la ligne se fond de la roue de chargement vers la pochette et le titre ; un code non reconnu glisse vers la section « Non reconnus » ; une ligne retirée ou purgée s'efface en douceur. Avec Réduire les animations : tout change sans mouvement. Les compteurs « (N) » du menu des dossiers et le sous-titre « N éléments » de la Collection ne roulent pas (éléments système).

- [ ] Passé — date / appareil / version :

### G28 — Scan par lot : pastilles Collection et Wantlist comme ailleurs `AUDIT`

**Conditions** : Scan par lot avec au moins un disque déjà en collection et un disque déjà en wantlist ; thème Violet puis Signature.

**Étapes** :

1. Scanner les deux codes-barres.
2. Regarder la liste sous le titre de chaque disque.
3. Ajouter un disque scanné à la collection, un autre à la wantlist, et regarder les lignes.
4. Comparer avec la pastille d'une page artiste.

**Résultat attendu** : Collection : pastille verte « Collection » avec coche. Wantlist : pastille « Wantlist » avec cœur, à la couleur du thème (violette en thème Violet). Identiques à celles de la page artiste, en clair comme en sombre.

- [ ] Passé — date / appareil / version :

### G29 — Scan par lot : saisie rapide du prix d'achat et de l'état après l'ajout `AUDIT` `PREMIUM` `AUTO`

**Conditions** : Compte Premium ; champs « Prix d'achat » et « État du média » choisis dans Réglages (puis un seul des deux, puis aucun) ; 3 disques scannés, en ligne.

**Étapes** :

1. Scanner 3 disques, les ajouter à la collection.
2. Dans le bilan, toucher « Renseigner ».
3. Disque 1 : saisir un prix (avec une virgule) et choisir un état, « Enregistrer ».
4. Disque 2 : « Passer ».
5. Disque 3 : saisir seulement l'état, « Enregistrer ».
6. Après la dernière feuille, regarder l'onglet Collection et le filtre « À compléter ».
7. Refaire un lot et toucher « Plus tard ».
8. Refaire un lot en mode avion.
9. Fermer la feuille de saisie au milieu du lot.

**Résultat attendu** : 1 : le bilan se termine par « Renseigner prix et état maintenant ? » avec deux boutons « Renseigner » et « Plus tard » (avec un seul champ configuré, la question ne cite que lui ; sans champ configuré, simple « OK »). 2-3 : la feuille montre pochette, titre, rang (1 / 3), champs prix et état ; « Enregistrer » est grisé tant que rien n'est saisi ; le prix part sur Discogs au format « 12.50 EUR ». 4 : le disque 2 reste sans prix ni état. 5 : l'état seul est enregistré. 6 : les disques 1 et 3 ont leurs valeurs dans leur fiche et la liste ; seul le disque 2 apparaît sous « Sans prix d'achat ». 7 : le scan se ferme et ouvre la Collection comme avant. 8 : rien n'est proposé pour les disques en attente du réseau (ils se complètent plus tard, avec le filtre « À compléter »). 9 : ce qui est enregistré le reste ; le scan se ferme ensuite sur la Collection. Règles couvertes par BatchCompletionTests. À vérifier à la main : la feuille s'ouvre bien juste après l'alerte.

- [ ] Passé — date / appareil / version :

### G30 — Ajout unitaire : saisie rapide du prix d'achat et de l'état `AUDIT`

**Conditions** : Champs « Prix d'achat » et « État du média » choisis dans Réglages (puis un seul des deux, puis aucun) ; en ligne.

**Étapes** :

1. Scanner un disque (scan unitaire), ouvrir sa fiche, toucher le bouton « En collection ».
2. Dans la feuille « Compléter les disques », saisir un prix et choisir un état, « Enregistrer ».
3. Sur une fiche déjà en collection, ajouter un autre exemplaire (menu ou appui long), puis « Passer ».
4. Retirer le champ prix dans Réglages, ajouter un disque.
5. Retirer les deux champs, ajouter un disque.
6. Mode avion : ajouter un disque.
7. Mode démo : ajouter un disque.

**Résultat attendu** : 1 : l'ajout se fait puis la feuille de saisie s'ouvre. 2 : les valeurs apparaissent dans la fiche de l'exemplaire et sur Discogs. 3 : la feuille s'ouvre aussi pour l'exemplaire ajouté ; « Passer » la ferme sans rien écrire. 4 : seul l'état est demandé. 5 : aucune feuille. 6 : aucune feuille (l'ajout part au retour du réseau). 7 : ajout bloqué comme avant, aucune feuille.

- [ ] Passé — date / appareil / version :

<a id="famille-h"></a>

## H — Fiche détail d'un release

### H1 — Affichage des sections

**Conditions** : Fiche détail ouverte.

**Étapes** :

1. Parcourir la fiche : infos, tracklist, images, vidéos.

**Résultat attendu** : Toutes les sections se chargent sans erreur ni contenu manquant.

- [ ] Passé — date / appareil / version :

### H2 — Visionneuse d'images

**Conditions** : Release avec plusieurs images.

**Étapes** :

1. Toucher une pochette → zoomer → swiper entre les images.

**Résultat attendu** : Zoom fluide, navigation entre images sans à-coup.

- [ ] Passé — date / appareil / version :

### H3 — Lecture vidéo YouTube intégrée

**Conditions** : Release avec vidéo associée.

**Étapes** :

1. Toucher la vignette vidéo.

**Résultat attendu** : Le lecteur YouTube embarqué se lance et joue correctement.

- [ ] Passé — date / appareil / version :

### H4 — Marketplace Discogs

**Conditions** : Release présent sur le marketplace Discogs.

**Étapes** :

1. Ouvrir la section Marketplace.

**Résultat attendu** : Prix le plus bas, nombre en vente et estimation par état affichés correctement, ou « Indisponible » si pas de données.

- [ ] Passé — date / appareil / version :

### H5 — Édition prix d'achat / état du disque `PREMIUM`

**Conditions** : Compte premium, exemplaire en collection.

**Étapes** :

1. Ouvrir l'édition du prix d'achat → saisir prix, réduction, état → enregistrer.

**Résultat attendu** : Le prix d'achat net (prix − réduction) est recalculé et persisté.

- [ ] Passé — date / appareil / version :

### H6 — Plus-value verrouillée — non premium `PREMIUM`

**Conditions** : Compte non premium.

**Étapes** :

1. Ouvrir la fiche d'un exemplaire en collection.

**Résultat attendu** : La cote actuelle reste visible ; seule la plus-value (comparaison au prix d'achat) affiche une carte verrouillée.

- [ ] Passé — date / appareil / version :

### H7 — Comparaison prix payé vs cote actuelle `PREMIUM`

**Conditions** : Exemplaire avec prix d'achat renseigné, compte premium.

**Étapes** :

1. Observer l'écart affiché entre prix payé et cote Discogs actuelle.

**Résultat attendu** : Écart calculé et affiché correctement (plus-value/moins-value).

- [ ] Passé — date / appareil / version :

### H8 — Release sans image de pochette `LIMITE`

**Conditions** : Release dont Discogs ne fournit aucune image.

**Étapes** :

1. Ouvrir la fiche détail de ce release.

**Résultat attendu** : Image de remplacement (placeholder) affichée, pas d'espace vide cassé ni de crash d'`AsyncCoverImage`.

- [ ] Passé — date / appareil / version :

### H9 — Tracklist vide `LIMITE`

**Conditions** : Release sans piste renseignée côté Discogs.

**Étapes** :

1. Ouvrir la section tracklist.

**Résultat attendu** : Section masquée ou message « non renseigné », pas de liste vide avec en-tête orpheline.

- [ ] Passé — date / appareil / version :

### H10 — Vidéo YouTube indisponible `LIMITE`

**Conditions** : Vidéo associée supprimée ou bloquée dans la région.

**Étapes** :

1. Toucher la vignette vidéo.

**Résultat attendu** : Message d'erreur du lecteur, pas de crash de l'app ni d'écran noir permanent.

- [ ] Passé — date / appareil / version :

### H11 — Prix d'achat négatif ou non numérique `LIMITE` `PREMIUM`

**Conditions** : Champ de saisie du prix d'achat ouvert.

**Étapes** :

1. Saisir une valeur négative, puis des lettres.

**Résultat attendu** : Validation refusée ou valeur ignorée ; aucune valeur invalide persistée dans le suivi de cote.

- [ ] Passé — date / appareil / version :

### H12 — Marketplace dans une devise non supportée `LIMITE`

**Conditions** : Release vendu uniquement dans une devise rare/non gérée par l'app.

**Étapes** :

1. Ouvrir la section Marketplace de ce release.

**Résultat attendu** : Affichage brut de la devise d'origine ou message « conversion indisponible », jamais un montant erroné silencieusement mal converti.

- [ ] Passé — date / appareil / version :

### H13 — Ouverture rapide d'une fiche `AUDIT`

**Conditions** : Grande collection et grande wantlist en cache.

**Étapes** :

1. Ouvrir successivement plusieurs fiches de disques possédés et non possédés.

**Résultat attendu** : Statut collection / wantlist affiché instantanément, sans latence à l'ouverture.

- [ ] Passé — date / appareil / version :

### H14 — Ajout à la collection avec Discogs injoignable `AUDIT` `RÉGRESSION`

**Conditions** : Network Link Conditioner sur « 100% Loss ».

**Étapes** :

1. Ajouter le disque à la collection depuis sa fiche.
2. Rétablir le réseau et attendre la synchro.
3. Vérifier sur discogs.com.

**Résultat attendu** : Message « Discogs ne répond pas… » ; le bouton reste « En collection » ; un seul exemplaire ajouté sur Discogs (plus de doublon).

- [ ] Passé — date / appareil / version :

### H15 — Retirer tous les exemplaires, réseau coupé en cours `AUDIT` `LIMITE`

**Conditions** : Release possédée en 3 exemplaires.

**Étapes** :

1. « Supprimer tous les exemplaires ».
2. Couper le réseau juste après la confirmation.
3. Rétablir le réseau.

**Résultat attendu** : Tous les exemplaires finissent retirés sur Discogs ; aucun message « Échec définitif » pour un exemplaire déjà retiré.

- [ ] Passé — date / appareil / version :

### H16 — Ajout refusé par Discogs `AUDIT` `LIMITE`

**Conditions** : Release supprimée/fusionnée côté Discogs, fiche encore ouverte dans l'app.

**Étapes** :

1. Toucher « Collection » pour l'ajouter.

**Résultat attendu** : Message « Impossible d'ajouter ce disque sur Discogs » ; le bouton revient à l'état non ajouté ; rien n'est mis en file.

- [ ] Passé — date / appareil / version :

### H17 — Démo : ajout à la wantlist bloqué depuis la fiche `AUDIT` `AUTO`

**Conditions** : Mode démo actif, réseau disponible.

**Étapes** :

1. Ouvrir la fiche d'un disque de la collection de démo.
2. Toucher « Wantlist », puis « Collection » (ajout d'un exemplaire), changer la note.

**Résultat attendu** : Alerte titrée « Mode démo » avec le message dédié (ajout, retrait ou modification) ; l'état des boutons ne change pas.

- [ ] Passé — date / appareil / version :

### H18 — « Mes exemplaires » : actions par appui long `AUDIT`

**Conditions** : Release possédée, fiche ouverte (iOS 26 et iOS 27).

**Étapes** :

1. Maintenir le doigt sur un exemplaire de « Mes exemplaires ».
2. Tester Modifier, Où ranger cet exemplaire, Supprimer.

**Résultat attendu** : Menu contextuel avec les 3 actions, fonctionnel sur iOS 26 (où le balayage n'existe pas) comme sur iOS 27 (où le balayage reste disponible).

- [ ] Passé — date / appareil / version :

### H19 — Taille des tags dans « Mon exemplaire » `AUDIT`

**Conditions** : Exemplaire avec plusieurs tags et un prix d'achat.

**Étapes** :

1. Ouvrir la fiche, section « Mon exemplaire », et l'édition de l'exemplaire.

**Résultat attendu** : Les tags ont la même taille de police que la variation de prix.

- [ ] Passé — date / appareil / version :

### H20 — Prix le plus bas dans la devise choisie `AUDIT`

**Conditions** : Devise d'affichage réglée sur EUR (Réglages → Prix d'achat et état).

**Étapes** :

1. Ouvrir la fiche d'un disque en vente sur le Marketplace.
2. Lire « N exemplaires en vente dès … » sous la tracklist.
3. Passer la devise en USD et rouvrir.

**Résultat attendu** : Le prix est affiché en euros (converti depuis le dollar renvoyé par Discogs), puis en dollars après le changement de devise.

- [ ] Passé — date / appareil / version :

### H21 — Mon exemplaire : plus-value masquée sans Premium `AUDIT`

**Conditions** : Compte sans abonnement, champ prix d'achat configuré, disque présent dans la collection avec un prix d'achat renseigné.

**Étapes** :

1. Ouvrir la fiche du disque, section « Mon exemplaire ».
2. Comparer la pastille avec celle d'un compte Premium (prix d'achat renseigné).
3. Toucher la pastille.

**Résultat attendu** : La pastille a le même aspect que pour un compte Premium (flèche montante, montant seul, sans pourcentage), avec le montant masqué : « +? € » ; le toucher ouvre l'offre Premium. VoiceOver annonce « Plus-value masquée ».

- [ ] Passé — date / appareil / version :

### H22 — Cote visible sans Premium `AUDIT`

**Conditions** : Compte sans abonnement, disque présent dans la collection et coté sur Discogs.

**Étapes** :

1. Ouvrir la fiche du disque, section « Mon exemplaire ».
2. Ouvrir la feuille d'édition de l'exemplaire, section « Plus-value de l'exemplaire ».
3. Toucher la ligne « Cote actuelle » de la feuille.
4. Hors ligne, plus de 6 h après le dernier chargement, rouvrir la fiche.

**Résultat attendu** : « Cote actuelle » et son montant (dans la devise par défaut) s'affichent au-dessus de la carte Premium verrouillée, sur la fiche comme dans la feuille ; la pastille de plus-value reste masquée. Le toucher de la ligne ouvre le Marketplace Discogs. Hors ligne avec une cote ancienne, la ligne affiche « Cote du … ». Disque sans cote Discogs : pas de ligne, seulement la carte verrouillée.

- [ ] Passé — date / appareil / version :

### H23 — Prix d'achat saisi sans Premium `AUDIT`

**Conditions** : Compte sans abonnement, connecté à Discogs.

**Étapes** :

1. Réglages → Prix d'achat et état : choisir le champ prix d'achat, le champ état et la devise.
2. Ouvrir la fiche d'un disque sans prix d'achat, toucher « + Prix d'achat » et saisir un prix.
3. Regarder la pastille, puis la toucher.
4. Ouvrir Stats.

**Résultat attendu** : La section Réglages « Prix d'achat et état » est accessible ; la section « Suivi de plus-value » juste au-dessus affiche une carte verrouillée (« Comment ça fonctionne ? » réservé au Premium). Le prix est enregistré sur Discogs. La pastille masquée « +? € » apparaît seulement une fois le prix saisi, et son toucher ouvre l'offre Premium. Dans Stats, « Investi vs Cote actuelle » reste verrouillé (carte « Suivi de plus-value »).

- [ ] Passé — date / appareil / version :

### H24 — Démo : cote d'exemple et plus-value `AUDIT` `AUTO`

**Conditions** : Mode démo actif.

**Étapes** :

1. Ouvrir Mon exemplaire de plusieurs disques de la collection de démo.
2. Quitter la démo, se connecter à un vrai compte et ouvrir un disque qui figurait aussi dans la démo.

**Résultat attendu** : En démo : ligne « Cote d'exemple (démo) » et plus-value calculée (positive ou négative selon le disque), valeurs identiques d'une ouverture à l'autre. Le Marketplace ne montre que les vraies données Discogs. Sur le vrai compte : aucune cote d'exemple reprise, la vraie cote Discogs est demandée.

- [ ] Passé — date / appareil / version :

### H25 — Retour sur un écran (fiche, master, label, artiste, profil) : même position qu'au départ `AUDIT`

**Conditions** : Une fiche release longue (tracklist, crédits, exemplaires), un master avec beaucoup de pressages, un label, un artiste à longue discographie.

**Étapes** :

1. Ouvrir une fiche et faire défiler jusqu'au milieu ou en bas.
2. Toucher le master, le label ou un artiste pour ouvrir son écran.
3. Revenir en arrière.
- 3bis. Refaire depuis le master vers une fiche, depuis le label vers une fiche, depuis l'artiste vers un master ou une fiche, puis depuis Réglages vers le profil Discogs et ses liens.
4. Refaire avec une fiche ouverte hors ligne (version limitée), puis après avoir ajouté le disque à la collection depuis l'écran du master.

**Résultat attendu** : Au retour, chaque écran (fiche, master, label, artiste, profil) est exactement à la même position qu'avant l'ouverture de l'autre écran, sans squelette de chargement ni retour en haut. Les boutons Collection et Wantlist reflètent l'état à jour. Une fiche en échec de chargement se recharge bien au retour.

- [ ] Passé — date / appareil / version :

### H26 — « Mon exemplaire » : en-tête, fond teinté et pastilles de plus-value `AUDIT` `AUTO`

**Conditions** : Exemplaire avec prix d'achat renseigné (champ associé dans Réglages) ; un compte Premium et un compte gratuit.

**Étapes** :

1. Ouvrir « Mon exemplaire » depuis la fiche d'un disque possédé.
2. Observer l'en-tête et le fond.
3. Avec Premium : observer les pastilles Payé / Cote / Plus-value, changer le prix d'achat ou l'état du disque.
4. Sans Premium puis hors ligne.
5. Thème sombre et police agrandie.

**Résultat attendu** : L'en-tête montre la jaquette en grand avec son halo, titre, artiste et pastilles (année, format, dossier) ; le fond prend une teinte douce de la pochette une fois chargée. Avec Premium, trois pastilles côte à côte : prix payé, cote, plus-value en vert (gain) ou rouge (perte) avec le pourcentage ; la ligne de cote en dessous ouvre toujours le Marketplace. Sans Premium : cote seule et carte d'offre, aucune plus-value. Hors ligne ou sans prix d'achat : message explicatif à la place des pastilles.

- [ ] Passé — date / appareil / version :

### H27 — « Mon exemplaire » : pastille « Utilisé pour la plus-value » vers Réglages `AUDIT`

**Conditions** : Champs « prix d'achat » et « état du disque » choisis dans Réglages → Prix d'achat et état ; compte gratuit et Premium.

**Étapes** :

1. Ouvrir « Mon exemplaire » : repérer la pastille rose « Utilisé pour la plus-value › » collée sous le nom de chacun des deux champs choisis (et seulement ceux-là), y compris pour un champ texte long, un menu déroulant ou une case à cocher : elle ne doit jamais sembler appartenir à la ligne voisine.
2. Toucher la pastille sous le prix d'achat.
3. Revenir sur « Mon exemplaire » et toucher celle de l'état du disque.
- 3bis. Après un lancement à froid de l'app (Réglages jamais ouvert pendant la session), refaire l'étape 2 : c'est le cas du tout premier essai.
4. Depuis un exemplaire ouvert dans la fiche d'un disque puis depuis la Collection ; avec un champ modifié non validé ; avec VoiceOver.

**Résultat attendu** : Le nom de chaque champ concerné et sa pastille ont la même teinte (orange vif pour le prix d'achat, orange plus brûlé pour l'état du disque), lisibles en thème clair comme sombre. La feuille se ferme, l'onglet Réglages s'ouvre, défile jusqu'à « Prix d'achat et état » et la ligne correspondante (Champ prix d'achat ou Champ état du disque) prend, pendant environ 2 secondes, une surbrillance de la même teinte que le champ, comme la règle de rangement depuis le guide. Aucune pastille si aucun champ n'est choisi. Une modification de champ non validée au moment du toucher est enregistrée comme à la fermeture normale. VoiceOver annonce « Utilisé pour la plus-value » avec l'indication « Ouvre ce réglage dans Réglages ».

- [ ] Passé — date / appareil / version :

### H28 — Fiche : retour au geste après un ajout ou un retrait (collection, wantlist) `AUDIT` `AUTO`

**Conditions** : Compte connecté (pas la démo) ; fiche d'un disque absent de la collection et de la wantlist ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Toucher « Collection » (ajout), puis « Wantlist ».
2. Retirer le disque de la collection, puis de la wantlist (avec leurs confirmations).
3. Ouvrir la fiche d'un disque déjà en collection : aucune réaction ne doit se produire au chargement.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : À chaque ajout : haptique de succès, le bouton fait un petit « pop » et sa coche remplace l'icône, la jaquette pulse très légèrement. À chaque retrait : choc haptique léger, le bouton reprend son état sans pop. Rien ne se passe au simple chargement d'une fiche. Avec Réduire les animations : haptique seul, sans pop ni pulsation (règle couverte par LibraryFeedbackEventTests).

- [ ] Passé — date / appareil / version :

### H29 — Fiche : les sections arrivent en cascade au chargement `AUDIT`

**Conditions** : Fiche d'un disque en collection (exemplaires, rangement, écoutes, note) ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir la fiche d'un disque.
2. Observer l'arrivée des sections sous la jaquette.
3. Ouvrir une autre fiche depuis celle-ci (artiste, label), puis revenir.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : Une fois la fiche chargée, les actions rapides, « Mes exemplaires », le rangement, les écoutes et la note montent et apparaissent l'un après l'autre. Au retour depuis une autre fenêtre, l'animation ne se rejoue pas. Avec Réduire les animations : tout est affiché directement.

- [ ] Passé — date / appareil / version :

### H30 — Ajout : la pochette vole vers la barre d'onglets `AUDIT` `AUTO`

**Conditions** : Compte connecté (hors démo) ; Réduire les animations désactivé puis activé ; barre d'onglets dépliée puis réduite par un défilement.

**Étapes** :

1. Depuis une fiche, ajouter un disque à la collection.
2. Ajouter un autre disque à la wantlist.
3. Refaire avec la barre d'onglets réduite (défiler une liste vers le bas, puis ouvrir une fiche).
4. Ajouter plusieurs disques d'un coup par le scan par lot.
5. Refaire avec Réduire les animations activé.

**Résultat attendu** : La pochette part du milieu de l'écran et file en courbe vers l'icône de l'onglet concerné (Collection ou Wantlist), en rapetissant, puis un halo rose s'élargit à l'arrivée ; la bulle de confirmation et le haptique restent. Barre réduite : le vol se termine près du coin inférieur gauche, sans geste parasite (point d'arrivée estimé, à régler sur appareil si l'écart est visible). Scan par lot : un seul vol à la fois, pas une rafale. Aucun vol avec Réduire les animations ; aucune interférence avec les touchers pendant le vol (calcul du point d'arrivée couvert par LibraryAddFlightGeometryTests).

- [ ] Passé — date / appareil / version :

### H31 — « Mes écoutes sur platine » seulement pour un disque possédé `AUDIT`

**Conditions** : Un disque en collection, un disque seulement en wantlist, un disque absent des deux.

**Étapes** :

1. Ouvrir la fiche du disque en collection.
2. Ouvrir celle du disque en wantlist, puis celle du disque absent.
3. Depuis la fiche du disque absent, l'ajouter à la collection, puis le retirer.

**Résultat attendu** : La section « Mes écoutes sur platine » est visible pour le disque en collection, absente pour les deux autres. Elle apparaît dès l'ajout à la collection et disparaît au retrait, sans autre changement de la page.

- [ ] Passé — date / appareil / version :

### H32 — Écoute sur platine : seulement pour un disque possédé (recherche et raccourcis) `AUDIT` `AUTO`

**Conditions** : Un disque en collection, un disque hors collection (en wantlist ou absent) ; raccourci « Démarrer une écoute » enregistré dans l'app Raccourcis ; Siri disponible.

**Étapes** :

1. Dans l'onglet Recherche, chercher les deux disques et balayer chaque ligne vers la droite (ou appui long).
2. Lancer « Démarrer une écoute » avec le disque en collection, puis avec Siri.
3. Retirer le disque de la collection, puis relancer le raccourci enregistré avec ce disque.

**Résultat attendu** : Recherche : « J'écoute » n'est proposé que sur le disque en collection. Raccourci : l'écoute démarre pour un disque possédé ; pour un disque qui n'est plus dans la collection, Siri ou Raccourcis répond que le disque n'est pas dans la collection et aucune écoute ni Live Activity n'est créée (règle couverte par RecordLibraryTests).

- [ ] Passé — date / appareil / version :

### H33 — Vidéos d'une fiche : lecture intégrée toujours possible après le durcissement `AUDIT` `AUTO`

**Conditions** : Fiche d'un disque avec plusieurs vidéos YouTube (liens youtube.com/watch et youtu.be) ; connecté à discogs.com dans une page de l'app.

**Étapes** :

1. Ouvrir la section Vidéos, toucher une vidéo.
2. La lire, passer en plein écran, fermer.
3. Ouvrir ensuite une page discogs.com dans l'app.

**Résultat attendu** : 1-2 : la vidéo se lit dans l'app comme avant (vignette affichée, lecture et plein écran). Un lien vidéo non YouTube ou mal formé s'ouvre en externe au lieu du lecteur intégré. 3 : la session discogs.com est toujours ouverte (le lecteur vidéo utilise un stockage séparé). Validation des identifiants couverte par ReleaseVideoTests.

- [ ] Passé — date / appareil / version :

### H34 — Feuille « Prix et état » : prix d'achat et état du média ensemble `AUDIT`

**Conditions** : Champs « Prix d'achat » et « État du média » choisis dans Réglages ; un disque possédé sans prix ni état ; puis un disque avec un prix mais sans état ; compte non Premium puis Premium.

**Étapes** :

1. Sur la fiche du disque, section « Mon exemplaire », toucher la pastille « Prix et état ».
2. Saisir seulement un prix, « OK ».
3. Rouvrir (depuis Collection > Modifier si la pastille n'est plus là), choisir seulement un état.
4. Rouvrir la feuille avec prix et état déjà renseignés, ne rien changer.
5. Retirer le champ « État du média » dans Réglages et rouvrir la feuille.
6. Mode avion, saisir un prix et un état.

**Résultat attendu** : 1 : la feuille s'intitule « Prix et état », avec les cartes « Prix d'achat » et « État du média » (menu des valeurs Discogs) et la phrase sur le calcul de la plus-value ; la pastille dit « Prix et état » (« Prix d'achat » si le champ état n'est pas configuré). 2-3 : seul le champ modifié est écrit sur Discogs ; la cote se recalcule avec l'état choisi. 4 : « OK » est grisé. 5 : seule la carte du prix reste. 6 : les deux valeurs s'affichent et partent au retour du réseau. Limite : une fois le prix renseigné, la pastille laisse place à la plus-value ; l'état se complète alors par « Modifier » ou le filtre « À compléter ».

- [ ] Passé — date / appareil / version :

### H35 — Prix d'achat et état du disque saisis dans l'app (sans champ Discogs) `AUDIT` `AUTO`

**Conditions** : Compte neuf, sans aucun champ Discogs associé dans Réglages > Suivi de plus-value ; puis un compte déjà configuré (champs associés). Un album en collection.

**Étapes** :

1. Mon exemplaire > section « Plus-value de l'exemplaire » : saisir un prix puis quitter le champ ; changer la devise ; choisir un état dans la liste (« — », Mint (M) … Poor (P)).
2. Fermer et rouvrir la feuille, puis la fiche de l'album (pastille de plus-value ou « Prix et état »).
3. Ajouter un album (réglage « Proposer après un ajout » activé) : la fenêtre « Compléter les albums » propose prix et état ; la désactiver dans Réglages et recommencer.
4. Collection > ··· > Filtres > « À compléter » : « Sans prix d'achat », « Sans état du média ».
5. Stats > « Investi vs cote actuelle » (Premium), exports CSV et PDF.
6. Réglages > Suivi de plus-value : devise, « Proposer après un ajout », « Champ Discogs du prix d'achat » / « … de l'état du disque ».
7. Compte configuré : associer puis dissocier un champ, saisir un prix, vérifier sur discogs.com ; mode avion.
8. Mode démo : saisir un prix et un état.

**Résultat attendu** : 1-2 : valeurs enregistrées sans réseau ni champ Discogs, aucune erreur ; sur un compte configuré, les deux champs Discogs associés restent listés dans « Champs personnalisés Discogs » et affichent la même valeur (une modification faite d'un côté apparaît de l'autre) ; l'état proposé en 8 grades Discogs plus « — ». 3 : la fenêtre propose toujours les deux saisies quand le réglage est actif, jamais sinon. 4 : les filtres suivent les valeurs saisies, sans configuration préalable, et se mettent à jour dès la saisie. 5 : total investi et colonnes « Prix d'achat » / « État du disque » reprennent les valeurs de l'app (les champs Discogs associés ne sont pas répétés dans les colonnes personnalisées). 6 : plus d'association automatique d'un champ à l'ouverture de la page ; « Aucun » par défaut. 7 : sans champ associé, rien n'est envoyé à Discogs ; avec un champ associé, chaque saisie y part (mise en file hors ligne) et une valeur vidée n'efface rien sur Discogs. 8 : saisie possible en démo, rien n'est envoyé, tout disparaît en quittant la démo. Règles couvertes par CopyDetailsTests, BatchCompletionTests, MissingFieldFilterTests, PurchasePriceSetupTests.

- [ ] Passé — date / appareil / version :

### H36 — Importer prix et état depuis des champs Discogs (aperçu, conflits, annulation) `AUDIT` `AUTO`

**Conditions** : Compte avec des champs personnalisés Discogs remplis sur plusieurs albums : prix variés (« 12,50 », « 12.50 € », « $15 », « 20 GBP », « 1 234,56 », « environ 10 », vide) et états (« Mint (M) », « VG+ », « Excellent », vide) ; quelques albums déjà renseignés dans l'app avec une valeur différente.

**Étapes** :

1. Réglages > Suivi de plus-value > « Importer depuis Discogs ».
2. Choisir le champ du prix et celui de l'état, laisser « Compter en… » sur EUR, toucher « Analyser ».
3. Lire l'aperçu : décomptes, devises lues, exemples, valeurs illisibles.
4. Changer « Compter en… » : l'aperçu se met à jour sans relire la collection.
5. Importer sans « Remplacer » ; ouvrir un album qui avait déjà une valeur et un album vide.
6. Refaire une analyse, activer « Remplacer les valeurs existantes », confirmer.
7. Toucher « Annuler l'import » ; modifier avant un album importé pour vérifier qu'il garde sa saisie.
8. Mode avion avec cache de plus de 6 h, puis mode démo.
9. Filtre « À compléter » après import.

**Résultat attendu** : 2-3 : rien n'est modifié avant la confirmation ; « $15 » compté en USD, « 20 GBP » en GBP, sans devise comptés en EUR ; « environ 10 » et « Excellent » listés comme illisibles avec leur valeur brute. 4 : seuls les prix sans devise changent de devise. 5 : les valeurs de l'app ne sont pas écrasées, les albums vides sont remplis ; une valeur vide ou illisible n'efface rien. 6 : confirmation demandée, valeurs remplacées. 7 : l'état d'avant l'import est restauré, y compris après relance de l'app ; l'album modifié depuis garde sa saisie. 8 : refus avec message hors ligne si le cache est trop ancien ; en démo, import bloqué avec le message habituel. 9 : les albums aux valeurs illisibles y restent. Règles couvertes par CopyDetailsImportTests ; le déroulé sur compte réel est à confirmer ici.

- [ ] Passé — date / appareil / version :

### H37 — Envoyer prix et état vers Discogs (réglage et « Envoyer tout ») `AUDIT` `AUTO`

**Conditions** : Deux comptes : un compte neuf (aucun champ associé) et un compte déjà configuré avant cette version (champs prix et état associés) ; des albums dont prix et état sont gardés dans l'app, certains champs Discogs vides, d'autres déjà identiques, un rempli avec « Neuf ».

**Étapes** :

1. Compte neuf : Réglages > Suivi de plus-value > Champs Discogs ; associer un champ prix.
2. Vérifier l'interrupteur « Envoyer vers Discogs », saisir un prix sur un album, regarder le champ sur discogs.com.
3. Activer l'interrupteur, saisir un autre prix : vérifier sur discogs.com.
4. Compte déjà configuré : mettre à jour puis ouvrir la page ; saisir un prix.
5. « Envoyer tout vers Discogs » > Analyser : lire À envoyer / Déjà identiques / Ignorées.
6. Envoyer, observer la progression, interrompre à mi-parcours, relancer.
7. Mode avion pendant l'envoi ; mode démo.
8. Se déconnecter pendant un envoi.

**Résultat attendu** : 1-2 : l'interrupteur est coupé par défaut, rien ne part sur Discogs. 3 : après activation, chaque saisie part (mise en file hors ligne). 4 : l'interrupteur est déjà actif et l'envoi se fait comme avant. 5 : seules les valeurs vides ou différentes sont à envoyer ; « Neuf » reste intact (ignoré). 6 : progression « N sur M » au rythme de Discogs, l'interruption s'arrête proprement, la relance ne renvoie que le reste. 7 : hors ligne l'envoi s'arrête avec un message et la valeur en cours est mise en file ; en démo, envoi bloqué avec le message habituel. 8 : l'envoi s'arrête, rien n'est écrit sur l'autre compte. Règles couvertes par CopyDetailsDiscogsSyncTests ; l'envoi réel est à confirmer ici.

- [ ] Passé — date / appareil / version :

### H38 — Prix et état synchronisés par iCloud entre deux appareils (Premium) `AUDIT` `AUTO`

**Conditions** : Deux appareils réels (pas le Simulateur) connectés au même compte iCloud et au même compte Discogs, Premium actif, synchro iCloud activée ; schéma CloudKit déployé en Production si le build vient de TestFlight (type d'enregistrement CopyDetails).

**Étapes** :

1. Appareil A : saisir un prix et un état sur un album ; attendre quelques secondes.
2. Appareil B : ouvrir « Mon exemplaire » du même album.
3. Appareil B : modifier le prix ; vérifier sur A.
4. Hors ligne sur A, modifier l'état ; modifier le prix du même album sur B ; remettre A en ligne.
5. Importer des valeurs depuis Discogs sur A, puis « Annuler l'import » ; regarder B.
6. Activer « Envoyer vers Discogs » sur A ; vérifier le réglage sur B.
7. Compte non Premium : saisir un prix.
8. Réglages > Synchro iCloud (diagnostic) : vérifier qu'aucun enregistrement n'est refusé.

**Résultat attendu** : 1-2 : les valeurs apparaissent sur B sans relancer l'app. 3 : la modification de B arrive sur A. 4 : la saisie la plus récente l'emporte pour chaque champ de l'album, sans perte de l'autre exemplaire. 5 : l'import arrive sur B, l'annulation aussi. 6 : le réglage suit sur B. 7 : la saisie reste locale, rien n'est envoyé sur iCloud. 8 : aucune erreur de schéma. Règles couvertes par CopyDetailsCloudSyncTests ; la propagation réelle est à confirmer ici.

- [ ] Passé — date / appareil / version :

<a id="famille-i"></a>

## I — Statistiques

> PREMIUM

### I1 — Accès à l'onglet Stats — non premium `PREMIUM`

**Conditions** : Compte non premium.

**Étapes** :

1. Ouvrir l'onglet Stats.

**Résultat attendu** : Carte verrouillée / paywall affiché à la place des graphiques.

- [ ] Passé — date / appareil / version :

### I2 — Cartes résumé `PREMIUM`

**Conditions** : Compte premium.

**Étapes** :

1. Ouvrir l'onglet Stats.

**Résultat attendu** : Cartes Collection / Wantlist / Artistes affichent les bons totaux.

- [ ] Passé — date / appareil / version :

### I3 — Derniers ajouts `PREMIUM`

**Conditions** : Ajouts récents à la collection.

**Étapes** :

1. Observer la section « Derniers ajouts ».

**Résultat attendu** : Les ajouts les plus récents apparaissent en premier.

- [ ] Passé — date / appareil / version :

### I4 — Classement des artistes `PREMIUM`

**Conditions** : Collection avec plusieurs artistes.

**Étapes** :

1. Faire défiler verticalement le classement.

**Résultat attendu** : Défilement fluide, tous les artistes accessibles.

- [ ] Passé — date / appareil / version :

### I5 — Répartition par genre `PREMIUM`

**Conditions** : Collection avec genres variés.

**Étapes** :

1. Toucher une portion du camembert → « Voir ».

**Résultat attendu** : Filtre appliqué correctement vers la liste des albums de ce genre.

- [ ] Passé — date / appareil / version :

### I6 — Répartition par support (+ détail taille vinyle) `PREMIUM`

**Conditions** : Collection avec vinyles de tailles différentes.

**Étapes** :

1. Sélectionner « Vinyles » dans le camembert support.

**Résultat attendu** : Détail par taille de vinyle affiché en fondu sous le camembert.

- [ ] Passé — date / appareil / version :

### I7 — Répartition par label `PREMIUM`

**Conditions** : Collection avec plusieurs labels.

**Étapes** :

1. Toucher une portion → « Voir ».

**Résultat attendu** : Filtre vers la liste des albums du label correspondant.

- [ ] Passé — date / appareil / version :

### I8 — Sorties originales par année/décennie `PREMIUM`

**Conditions** : Collection avec dates de sortie variées.

**Étapes** :

1. Changer la granularité (Par année / Par décennie).

**Résultat attendu** : Le graphique se met à jour sans perte de données.

- [ ] Passé — date / appareil / version :

### I9 — Palmarès d'écoute & podiums `PREMIUM`

**Conditions** : Historique d'écoute enregistré (ListeningLogStore).

**Étapes** :

1. Consulter les podiums du mois et de l'année.

**Résultat attendu** : Classements cohérents avec le journal d'écoute réel.

- [ ] Passé — date / appareil / version :

### I10 — Collection vide `LIMITE` `PREMIUM`

**Conditions** : Compte premium avec une collection à 0 élément.

**Étapes** :

1. Ouvrir l'onglet Stats.

**Résultat attendu** : État vide adapté pour chaque section (pas de camembert à 0 portion ni de division par zéro visible).

- [ ] Passé — date / appareil / version :

### I11 — Un seul genre / un seul artiste `LIMITE` `PREMIUM`

**Conditions** : Collection dont tous les exemplaires partagent le même genre.

**Étapes** :

1. Ouvrir la répartition par genre.

**Résultat attendu** : Camembert à une seule portion (100%) affiché correctement, pas de légende vide à côté.

- [ ] Passé — date / appareil / version :

### I12 — Changement d'année pendant l'affichage des podiums `LIMITE` `PREMIUM`

**Conditions** : App ouverte sur les podiums à cheval sur le passage à minuit le 31/12.

**Étapes** :

1. Laisser l'app ouverte sur cet écran au moment du changement d'année.

**Résultat attendu** : Pas de plantage ni d'affichage incohérent ; au pire, un rafraîchissement manuel suffit à remettre les podiums à jour.

- [ ] Passé — date / appareil / version :

### I13 — Classement « Les plus écoutés » — bascule Albums/Artistes `PREMIUM`

**Conditions** : Compte premium, au moins 5 écoutes enregistrées pour les deux classements.

**Étapes** :

1. Dans Tops & Palmarès, basculer le sélecteur segmenté entre « Albums » et « Artistes ».

**Résultat attendu** : Le contenu de la carte change instantanément entre les deux classements, sans changer d'emplacement sur l'écran (même carte, pas deux cartes empilées).

- [ ] Passé — date / appareil / version :

### I14 — Classement artistes — défilement 5→20 `PREMIUM`

**Conditions** : Au moins 6 artistes distincts dans le palmarès d'écoute.

**Étapes** :

1. Ouvrir l'onglet « Artistes » du classement.
2. Faire défiler verticalement à l'intérieur de la carte.

**Résultat attendu** : 5 artistes visibles par défaut ; le défilement interne en révèle jusqu'à 20 ; l'indice « Faire défiler... » n'apparaît que s'il y a plus de 5 résultats.

- [ ] Passé — date / appareil / version :

### I15 — Vignette d'artiste Apple Music dans le classement `LIMITE` `PREMIUM`

**Conditions** : Au moins un artiste du palmarès reconnu par Apple Music, au moins un non reconnu.

**Étapes** :

1. Ouvrir l'onglet « Artistes » du classement et observer les vignettes.

**Résultat attendu** : Photo carrée (coins arrondis, même taille que les pochettes album) pour les artistes reconnus ; icône micro grisée pour les autres — jamais d'erreur visible, jamais de vignette qui reste bloquée en chargement.

- [ ] Passé — date / appareil / version :

### I16 — Ouverture de Stats sur une grosse collection `AUDIT` `PREMIUM`

**Conditions** : Collection de 1000+ disques en cache.

**Étapes** :

1. Ouvrir l'onglet Stats à plusieurs reprises.

**Résultat attendu** : Affichage rapide des répartitions, sans gel à l'ouverture ni pendant la résolution des années (rendu fluide toutes les 1,5 s).

- [ ] Passé — date / appareil / version :

### I17 — Total investi avec service de change indisponible `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Prix d'achat dans plusieurs devises, dont SEK ou AUD ; api.frankfurter.dev bloqué (proxy) ou réseau dégradé.

**Étapes** :

1. Ouvrir Stats et observer le total investi.

**Résultat attendu** : Total affiché en quelques secondes (pas d'attente longue) ; les montants SEK/AUD sont convertis approximativement, jamais comptés à 1:1 dans la devise par défaut.

- [ ] Passé — date / appareil / version :

### I18 — Progression de la résolution des années `AUDIT` `RÉGRESSION` `PREMIUM`

**Conditions** : Nombreux masters non résolus.

**Étapes** :

1. Ouvrir Stats (sorties originales).
2. Naviguer vers la Collection en tri « Rangement » puis revenir sur Stats.

**Résultat attendu** : La barre de progression avance jusqu'à 100 % ; elle ne se fige plus lorsqu'un autre écran demande aussi des années.

- [ ] Passé — date / appareil / version :

### I19 — Démo : suivi de cote préconfiguré `AUDIT` `PREMIUM`

**Conditions** : Mode démo actif.

**Étapes** :

1. Ouvrir Stats et une fiche de la collection de démo.

**Résultat attendu** : Valeur de la collection, total investi et plus-value affichés sans aucun réglage ; Réglages → Prix d'achat et état montre les champs « Prix d'achat » et « Media Condition » déjà associés, devise EUR.

- [ ] Passé — date / appareil / version :

### I20 — Historique de valeur propre à chaque compte `AUDIT` `LIMITE`

**Conditions** : Deux comptes Discogs sur le même iPhone, chacun avec un historique de valeur (Stats ouvertes plusieurs jours).

**Étapes** :

1. Compte A : ouvrir Stats → évolution de la valeur.
2. Se déconnecter, se connecter au compte B, ouvrir Stats.
3. Supprimer le compte B (Réglages → Supprimer mon compte), revenir au compte A.

**Résultat attendu** : Chaque compte ne voit que son propre historique ; supprimer le compte B ne touche pas à l'historique du compte A. Après la mise à jour, l'historique existant est rattaché au premier compte qui ouvre ses Stats.

- [ ] Passé — date / appareil / version :

### I21 — Démo : palmarès d'écoute rempli `AUDIT` `AUTO`

**Conditions** : Mode démo démarré depuis l'écran de connexion.

**Étapes** :

1. Ouvrir Stats → Tops & Palmarès (albums, artistes, podiums du mois et de l'année).
2. Quitter la démo puis la relancer.
3. Se connecter à un vrai compte.

**Résultat attendu** : Classements et podiums du mois et de l'année sont remplis dès l'entrée en démo, avec des écarts nets entre les disques ; la relance de la démo donne le même journal. Le vrai compte ne contient aucune de ces écoutes et rien n'est envoyé vers iCloud.

- [ ] Passé — date / appareil / version :

### I22 — Lancer une écoute depuis une fiche album ou artiste `AUDIT` `RÉGRESSION`

**Conditions** : Compte avec une collection ; Live Activities autorisées.

**Étapes** :

1. Ouvrir la fiche d'un album de la collection, faire défiler, toucher « J'écoute ».
2. Recommencer depuis la Collection, puis depuis la fiche d'un artiste (après avoir fait défiler).
3. Ouvrir les Stats et toucher un secteur des camemberts.

**Résultat attendu** : Aucun plantage. Le mini-lecteur apparaît et la Live Activity démarre AVEC la jaquette (plus d'erreur « Payload maximum size exceeded »). Les camemberts s'affichent (secteurs sans arrondi).

- [ ] Passé — date / appareil / version :

### I23 — Tops & Palmarès : 5 lignes visibles en albums comme en artistes `AUDIT` `PREMIUM` `AUTO`

**Conditions** : Compte premium avec au moins 6 albums et 6 artistes écoutés (ou mode démo).

**Étapes** :

1. Stats → Tops & Palmarès → Les plus écoutés : basculer plusieurs fois Albums / Artistes.
2. Recommencer avec une grande taille de texte (Réglages iOS → Luminosité et affichage → Taille du texte).

**Résultat attendu** : Dans les deux onglets, exactement 5 lignes entières sont visibles, la 5ᵉ n'est jamais coupée ni masquée ; les suivantes s'affichent en faisant défiler la liste.

- [ ] Passé — date / appareil / version :

### I24 — Histogrammes : sélection et fermeture de la feuille fluides `AUDIT` `AUTO`

**Conditions** : Grosse collection (plus de 1 000 disques), onglet Stats chargé ; histogrammes « Sorties originales » (décennies puis années) et « Exemplaires ajoutés par année ».

**Étapes** :

1. Toucher une barre : observer l'estompage des autres barres.
2. Toucher rapidement une autre barre, puis revenir à la première.
3. Fermer la feuille en la glissant vers le bas, puis avec la croix.
4. Retoucher la barre sélectionnée pour la désélectionner.
5. Basculer Décennie / Année avec une barre sélectionnée.

**Résultat attendu** : Les autres barres s'estompent immédiatement au toucher (environ 0,15 s), avant l'ouverture de la feuille ; la liste de la feuille correspond à la dernière barre touchée (jamais à une barre précédente). À la fermeture, toutes les barres retrouvent leur aspect normal dès que la feuille commence à descendre, sans attendre la fin de l'animation. Aucun saccade de l'écran pendant l'ouverture. Le titre de l'histogramme défile en haut de l'écran à l'ouverture de la feuille.

- [ ] Passé — date / appareil / version :

### I25 — Camemberts et classement des artistes : sélection fluide, titre en haut `AUDIT` `AUTO`

**Conditions** : Collection avec plusieurs genres, supports et labels (ou mode démo).

**Étapes** :

1. Camembert Genre : toucher une part (les autres s'estompent), la retoucher (ou toucher « Voir » ou le centre) pour ouvrir la feuille.
2. Fermer la feuille en la glissant vers le bas, puis avec la croix.
3. Mêmes gestes sur Support (toucher « Vinyles », puis une puce de taille) et sur Label.
4. Genre : toucher une puce de style sous le camembert.
5. Classement des artistes : toucher une barre (les autres s'estompent), fermer la feuille par glissé puis par la croix, retoucher la même barre pour la désélectionner.
6. Toucher à l'extérieur d'un anneau pour désélectionner.

**Résultat attendu** : Au premier toucher d'une part (sans feuille), les autres parts s'estompent immédiatement ET le titre du camembert défile en haut de l'écran. À l'ouverture de n'importe quelle feuille (y compris puces de style/taille et artistes), le titre du graphique défile en haut de l'écran, au-dessus de la feuille. Au glissé ou à la croix, la part sélectionnée de Genre, Support ou Label se remet à zéro dès que la feuille commence à descendre, sans saccade. Dans le classement des artistes, toucher une barre estompe les autres, comme sur les histogrammes ; elles reprennent leur aspect dès que la feuille commence à descendre ; retoucher la barre ouverte la désélectionne. Les puces de style et de taille de vinyle laissent leur camembert sélectionné. Aucune part ne reste sélectionnée après la fermeture d'une feuille ouverte depuis Support ou Label.

- [ ] Passé — date / appareil / version :

### I26 — Histogrammes par année : échelle verticale lisible et marge `AUDIT` `AUTO`

**Conditions** : Collection où la plupart des années comptent 1 ou 2 disques (ou mode démo).

**Étapes** :

1. Stats → Sorties originales, choisir « Par année ».
2. Regarder la hauteur des barres, puis toucher la plus haute barre.
3. Faire défiler le graphique latéralement.
4. Repasser sur « Par décennie », puis refaire de même sur « Exemplaires ajoutés » (histogramme des ajouts).
5. Toucher une barre après avoir fait défiler, puis la retoucher.

**Résultat attendu** : Les valeurs de l'échelle verticale (nombres entiers) sont affichées à gauche et restent en place pendant le défilement ; la barre touchée après défilement est bien celle qui est ouverte (et le second toucher la désélectionne). En vue par année, la plus haute barre ne touche pas le haut du graphique : il reste une marge au-dessus, et la pastille du nombre de disques de la barre sélectionnée est entièrement visible. Les barres à 1 disque ne paraissent plus « pleines » quand une autre année en compte 2 ou plus. La vue par décennie reste inchangée.

- [ ] Passé — date / appareil / version :

### I27 — Fiche : carte « Mes écoutes sur platine » animée pendant une écoute `AUDIT`

**Conditions** : Une fiche de disque possédé en collection (la carte n'apparaît pas pour un disque non possédé) ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir la fiche et regarder la carte « Mes écoutes sur platine » au repos.
2. Toucher le bouton disque pour démarrer une écoute.
3. Observer la carte pendant 10 secondes, puis toucher stop.
4. Refaire avec Réduire les animations activé.
5. Faire défiler la fiche pendant l'écoute.

**Résultat attendu** : Au démarrage : le compteur « Écouté N fois » passe à N+1 en faisant défiler le chiffre, la pastille « Écoute en cours » apparaît avec son point rose entouré d'un halo qui pulse, l'icône du disque tourne en continu (environ 33 tours par minute) sur son fond rose et un halo rose discret respire derrière la carte. À l'arrêt : le disque se remet droit, le halo et la pastille disparaissent, la date de dernière écoute réapparaît. Jamais écouté : le premier démarrage affiche « Écouté 1 fois ». Avec Réduire les animations : plus de rotation ni de pulsation ni de respiration, l'état « en cours » reste lisible par la pastille et la couleur. Le défilement de la fiche reste fluide.

- [ ] Passé — date / appareil / version :

### I28 — Statistiques : compteurs qui défilent, graphiques qui se dessinent `AUDIT`

**Conditions** : Compte avec une collection fournie ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir l'onglet Statistiques.
2. Observer les trois compteurs du haut.
3. Faire défiler : histogrammes, classement des artistes, camemberts.
4. Revenir en haut puis redescendre.
5. Refaire avec Réduire les animations activé.

**Résultat attendu** : Les compteurs défilent de 0 à leur valeur. Chaque graphique se dessine (barres qui montent, barres des artistes qui s'allongent, anneau qui grossit) la première fois qu'il devient visible, pas avant, et ne se rejoue pas ensuite. La sélection d'une barre ou d'une part reste instantanée. Avec Réduire les animations : valeurs et graphiques immédiats.

- [ ] Passé — date / appareil / version :

### I29 — Statistiques : « Derniers ajouts » et compteurs suivent les ajouts et retraits `AUDIT` `AUTO`

**Conditions** : Compte connecté avec une collection fournie ; onglet Statistiques déjà ouvert une première fois.

**Étapes** :

1. Ouvrir Statistiques et noter les « Derniers ajouts » et les compteurs.
2. Aller en Collection, supprimer l'un des derniers disques ajoutés (liste, menu contextuel ou fiche), puis revenir à Statistiques.
3. Ajouter un disque depuis la recherche, puis revenir à Statistiques.
4. Déplacer un disque récent dans un autre dossier, puis revenir.
5. Tirer pour actualiser ou relancer l'app après un retrait.

**Résultat attendu** : Sans recharger l'écran : le disque supprimé a disparu de « Derniers ajouts » (la liste se complète avec le disque suivant le plus récent), le compteur Collection baisse de 1 et les répartitions se mettent à jour ; un disque ajouté apparaît en tête et le compteur monte de 1 ; un disque déplacé reste affiché. Après actualisation, un disque supprimé ne réapparaît pas, même si Discogs le renvoie encore brièvement (règles couvertes par RecentAdditionsLogicTests).

- [ ] Passé — date / appareil / version :

### I30 — Évolution de la cote : la courbe se dessine à l'apparition `AUDIT`

**Conditions** : Compte Premium avec au moins deux relevés de cote ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir l'onglet Stats et défiler jusqu'à « Évolution de la cote ».
2. Remonter puis redescendre sur la section.
3. Refaire avec Réduire les animations activé.

**Résultat attendu** : La fourchette (zone claire) et la médiane (ligne) se dessinent de gauche à droite la première fois que le graphique apparaît à l'écran, sans saut des axes ni de la carte ; elles ne se redessinent pas quand on revient sur la section. Avec Réduire les animations : graphique affiché directement.

- [ ] Passé — date / appareil / version :

### I31 — Collection vide : l'onglet Stats affiche son contenu, pas le squelette `AUDIT`

**Conditions** : Compte Discogs sans aucun disque en collection (wantlist vide ou non) ; réseau actif.

**Étapes** :

1. Se connecter avec ce compte (ou retirer tous les disques de la collection).
2. Ouvrir l'onglet Stats.
3. Attendre une vingtaine de secondes.
4. Aller sur un autre onglet puis revenir sur Stats.
5. Ajouter un disque à la wantlist (depuis Recherche), puis revenir sur Stats sans attendre.
6. Ajouter un disque à la collection (depuis Recherche), ouvrir Stats (le graphique « Sorties originales » s'alimente), puis retirer ce disque et revenir sur Stats.

**Résultat attendu** : Les compteurs affichent 0 (collection) et la valeur de la wantlist ; chaque section montre son message « Pas encore assez de données… » ; le squelette gris ne reste jamais affiché, y compris avec un élément en wantlist 4 : au retour, aucun spinner de rechargement (la collection vide est considérée à jour pendant 6 h). 5 : le compteur « Wantlist » passe tout de suite à 1 (puis revient à 0 si on retire le disque), sans attendre le rechargement des compteurs ; les graphiques de collection restent vides, ils ne portent pas sur la wantlist. 6 : tous les graphiques repassent à « Pas encore assez de données », y compris « Sorties originales » (par décennie et par année), sans barre résiduelle.

- [ ] Passé — date / appareil / version :

<a id="famille-j"></a>

## J — Réglages — Général

### J1 — Profil utilisateur

**Conditions** : Connecté.

**Étapes** :

1. Réglages → toucher la fiche profil.

**Résultat attendu** : Nom d'utilisateur, avatar et infos de compte affichés correctement.

- [ ] Passé — date / appareil / version :

### J2 — Gestion des tags `PREMIUM`

**Conditions** : Au moins un tag existant.

**Étapes** :

1. Réglages → Gestion des tags → créer, renommer, fusionner, supprimer un tag.

**Résultat attendu** : Chaque opération se reflète immédiatement sur les exemplaires concernés, sans doublon après fusion.

- [ ] Passé — date / appareil / version :

### J3 — Dossier d'ajout par défaut

**Conditions** : Plusieurs dossiers Discogs.

**Étapes** :

1. Réglages → changer le dossier d'ajout par défaut.

**Résultat attendu** : Les prochains ajouts (recherche, scan) proposent ce dossier par défaut.

- [ ] Passé — date / appareil / version :

### J4 — Règle de rangement—

**Étapes** :

1. Réglages → modifier la règle de rangement.

**Résultat attendu** : Le guide de rangement (famille D) reflète la nouvelle règle.

- [ ] Passé — date / appareil / version :

### J5 — Trier par nom de famille (toggle)

**Conditions** : Collection avec artistes à particule/article.

**Étapes** :

1. Activer puis désactiver l'option.

**Résultat attendu** : Le tri de la collection et le guide de rangement basculent cohéremment entre les deux conventions.

- [ ] Passé — date / appareil / version :

### J6 — Arrêt automatique de l'écoute

**Conditions** : —

**Étapes** :

1. Réglages → « Arrêt automatique de l'écoute » : choisir une durée.
2. Lancer une écoute sur platine (bouton « J'écoute » d'une fiche album).

**Résultat attendu** : L'écoute sur platine (et sa Live Activity) s'arrête automatiquement après la durée choisie. Une lecture Apple Music n'est pas concernée par ce réglage.

- [ ] Passé — date / appareil / version :

### J7 — Mode d'affichage par défaut

**Conditions** : —

**Étapes** :

1. Changer le mode d'affichage par défaut → relancer l'app ou changer d'onglet et revenir.

**Résultat attendu** : Le mode choisi est bien celui utilisé à la prochaine ouverture de la Collection.

- [ ] Passé — date / appareil / version :

### J8 — Couleur du thème `PREMIUM`

**Conditions** : Compte premium.

**Étapes** :

1. Réglages → Couleur du thème → tester les 9 palettes.

**Résultat attendu** : Chaque palette s'applique immédiatement à toute l'app (accent, icônes, etc.).

- [ ] Passé — date / appareil / version :

### J9 — Thème — perte du premium `PREMIUM` `RÉGRESSION`

**Conditions** : Palette premium active, puis perte du statut premium.

**Étapes** :

1. Désactiver le compte premium (option développeur ou expiration réelle).

**Résultat attendu** : L'app revient automatiquement au thème par défaut (ThemeManager.revertToDefaultIfNeeded).

- [ ] Passé — date / appareil / version :

### J10 — Devise par défaut—

**Étapes** :

1. Changer la devise par défaut.

**Résultat attendu** : Tous les montants affichés (prix d'achat, cote, marketplace) utilisent la nouvelle devise, avec conversion correcte.

- [ ] Passé — date / appareil / version :

### J11 — Champs personnalisés (prix d'achat / état)

**Conditions** : —

**Étapes** :

1. Modifier les champs personnalisés associés au prix d'achat et à l'état du disque.

**Résultat attendu** : Les champs choisis sont bien ceux utilisés lors de l'édition d'un exemplaire.

- [ ] Passé — date / appareil / version :

### J12 — Renommer un tag avec un nom vide `LIMITE` `PREMIUM`

**Conditions** : Au moins un tag existant.

**Étapes** :

1. Ouvrir la gestion des tags → vider complètement le nom d'un tag → valider.

**Résultat attendu** : Validation refusée ou nom inchangé ; aucun tag à nom vide créé.

- [ ] Passé — date / appareil / version :

### J13 — Renommer un tag vers un nom déjà existant `LIMITE`

**Conditions** : Deux tags distincts existants (ex. « Rock » et « Pop »).

**Étapes** :

1. Renommer « Pop » en « Rock ».

**Résultat attendu** : Comportement explicite et cohérent : soit fusion automatique des deux tags, soit refus avec message clair — jamais deux tags distincts avec le même nom affiché.

- [ ] Passé — date / appareil / version :

### J14 — Fusionner deux tags appliqués aux mêmes exemplaires `LIMITE`

**Conditions** : Un exemplaire portant à la fois les tags « A » et « B ».

**Étapes** :

1. Fusionner le tag « A » dans le tag « B ».

**Résultat attendu** : L'exemplaire ne porte plus qu'un seul tag « B » (pas de doublon du même tag sur un exemplaire).

- [ ] Passé — date / appareil / version :

### J15 — Dossier par défaut supprimé sur Discogs.com `LIMITE`

**Conditions** : Dossier configuré comme dossier d'ajout par défaut, supprimé via le site Discogs.

**Étapes** :

1. Rafraîchir l'app.
2. Tenter un nouvel ajout.

**Résultat attendu** : L'app retombe sur un dossier valide (ex. « Uncategorized ») sans crash ni ajout silencieusement perdu.

- [ ] Passé — date / appareil / version :

### J16 — Connexion Apple Music depuis Réglages

**Conditions** : Compte Apple Music non encore autorisé pour cette app.

**Étapes** :

1. Réglages → section « Apple Music » → toucher « Connecter Apple Music ».

**Résultat attendu** : Invite système d'autorisation Apple Music affichée ; après acceptation, le statut passe à « Apple Music connecté » si un abonnement actif est détecté, sinon un message explicite indique l'absence d'abonnement.

- [ ] Passé — date / appareil / version :

### J17 — Statut Apple Music déjà connecté

**Conditions** : Autorisation déjà accordée et abonnement actif.

**Étapes** :

1. Rouvrir Réglages → section « Apple Music ».

**Résultat attendu** : Ligne « Apple Music connecté » avec coche verte, sans redemander l'autorisation ni relancer de vérification visible.

- [ ] Passé — date / appareil / version :

### J18 — Autorisé mais sans abonnement actif `LIMITE`

**Conditions** : Autorisation Apple Music accordée, mais aucun abonnement actif sur le compte Apple.

**Étapes** :

1. Ouvrir Réglages → section « Apple Music » après avoir accordé l'autorisation sans être abonné.

**Résultat attendu** : Message explicite sous le bouton (« Autorisation accordée, mais aucun abonnement Apple Music actif détecté ») plutôt qu'un simple échec silencieux.

- [ ] Passé — date / appareil / version :

### J19 — Changement de devise reçu d'un autre appareil `AUDIT` `PREMIUM` `2 APPAREILS`

**Conditions** : Synchro iCloud active sur 2 appareils, collection volumineuse.

**Étapes** :

1. Changer la devise par défaut sur l'appareil 1.
2. Observer l'appareil 2 (collection ouverte).

**Résultat attendu** : La devise change sur l'appareil 2 ; la collection n'est rechargée qu'une fois (pas 4) et sa synchro de fond va au bout.

- [ ] Passé — date / appareil / version :

### J20 — Gestion des dossiers : créer, renommer, dossier par défaut `AUDIT`

**Conditions** : Compte connecté, réseau disponible.

**Étapes** :

1. Réglages → Gestion des dossiers → Créer un dossier.
2. Le renommer (balayage ou appui long).
3. En faire le dossier d'ajout par défaut, puis ajouter un disque.

**Résultat attendu** : Le dossier apparaît aussitôt dans l'onglet Collection et sur discogs.com ; un nom déjà utilisé est refusé ; le disque ajouté arrive dans le dossier par défaut.

- [ ] Passé — date / appareil / version :

### J21 — Gestion des dossiers : suppression d'un dossier non vide `AUDIT`

**Conditions** : Dossier personnel contenant plusieurs exemplaires.

**Étapes** :

1. Supprimer le dossier et confirmer.

**Résultat attendu** : Progression « Déplacement vers Uncategorized : n/N » puis suppression ; tous les exemplaires se retrouvent dans Uncategorized. Si c'était le dossier par défaut, le réglage revient à « Toujours demander ».

- [ ] Passé — date / appareil / version :

### J22 — Gestion des dossiers : dossiers système protégés `AUDIT` `LIMITE`

**Conditions** : Écran Gestion des dossiers ouvert.

**Étapes** :

1. Tenter de renommer ou supprimer All et Uncategorized.

**Résultat attendu** : Aucune action proposée sur ces deux dossiers (badge « Système ») ; l'explication est affichée en bas de l'écran.

- [ ] Passé — date / appareil / version :

### J23 — Re-tap sur l'onglet actif `AUDIT`

**Conditions** : Barre d'onglets non réduite.

**Étapes** :

1. Dans chaque onglet, faire défiler puis toucher de nouveau son icône.
2. Ouvrir une fiche puis toucher l'icône de l'onglet.

**Résultat attendu** : Sans fiche ouverte : retour tout en haut. Avec une fiche ouverte : retour à la racine de l'onglet.

- [ ] Passé — date / appareil / version :

### J24 — Suppression d'un dossier avec des actions en attente `AUDIT` `LIMITE`

**Conditions** : Dossier personnel « Test » ; Discogs injoignable (Network Link Conditioner « 100% Loss ») puis ajout d'un disque dans « Test » et changement de dossier d'un exemplaire vers « Test ».

**Étapes** :

1. Rétablir le réseau sans laisser la file repartir (couper aussitôt l'app), puis supprimer le dossier « Test » depuis Gestion des dossiers.
2. Laisser la file hors ligne se vider.

**Résultat attendu** : Les actions en attente aboutissent dans Uncategorized (aucun « Échec définitif de synchronisation ») ; « Test » n'apparaît plus nulle part, même hors ligne.

- [ ] Passé — date / appareil / version :

### J25 — Dossier par défaut supprimé sur discogs.com `AUDIT` `LIMITE`

**Conditions** : Dossier par défaut réglé sur « Test » dans l'app.

**Étapes** :

1. Supprimer « Test » sur discogs.com.
2. Rouvrir l'app (Collection), puis ajouter un disque.

**Résultat attendu** : Le dossier par défaut repasse à « Toujours demander » et l'ajout aboutit, au lieu d'échouer sur un dossier inexistant.

- [ ] Passé — date / appareil / version :

### J26 — Bannière Premium : prix réel de la boutique `AUDIT`

**Conditions** : Compte sans abonnement, compte Sandbox d'un pays hors zone euro si possible.

**Étapes** :

1. Ouvrir Réglages et lire la bannière dorée.
2. Recommencer en mode avion au lancement.

**Résultat attendu** : « À partir de X / mois » avec le prix StoreKit le plus bas (équivalent mensuel de l'annuel : « 1,50 € » en France) dans la devise de la boutique. Sans réponse StoreKit, la ligne de prix est masquée (aucun prix codé en dur).

- [ ] Passé — date / appareil / version :

### J27 — Plus-value dans la devise choisie `AUDIT` `PREMIUM`

**Conditions** : Prix d'achat renseigné sur un exemplaire, devise d'affichage réglée sur USD (Réglages → Prix d'achat et état).

**Étapes** :

1. Ouvrir « Mon exemplaire » et lire la plus-value.
2. Repasser la devise en EUR et rouvrir.

**Résultat attendu** : Prix d'achat, cote et plus-value sont affichés et convertis dans la devise choisie (USD puis EUR), et non plus toujours en euros.

- [ ] Passé — date / appareil / version :

### J28 — Re-tap sur l'onglet Réglages `AUDIT`

**Conditions** : Réglages ouvert.

**Étapes** :

1. Ouvrir un sous-écran (Tags, Dossiers, Thème, Mode hors ligne…).
2. Toucher l'onglet Réglages.
3. Toucher encore l'onglet.

**Résultat attendu** : Premier toucher : retour à la racine de Réglages. Second toucher : remontée en haut de la liste. « Modifier » depuis le guide de rangement ouvre bien la section Collection & Rangement même si un sous-écran était ouvert.

- [ ] Passé — date / appareil / version :

### J29 — Dossier supprimé sur discogs.com avec actions en attente `AUDIT` `LIMITE` `AUTO`

**Conditions** : Mode avion : ajouter un disque dans le dossier « Test ».

**Étapes** :

1. Sur discogs.com (autre appareil), supprimer le dossier « Test ».
2. Désactiver le mode avion et ouvrir la Collection.

**Résultat attendu** : L'ajout en attente part dans Uncategorized au lieu d'échouer puis d'être abandonné ; le disque apparaît sur discogs.com.

- [ ] Passé — date / appareil / version :

### J30 — Règle de rangement mise en évidence `AUDIT` `PREMIUM`

**Conditions** : Compte premium, collection chargée.

**Étapes** :

1. Ouvrir le guide de rangement d'un disque (« Où ranger »).
2. Toucher « Modifier » à côté de la méthode de classement.
3. Recommencer en thème sombre et avec Réduire les animations.
4. Après un lancement à froid de l'app, sans avoir ouvert Réglages de la session, refaire les étapes 1 et 2 (premier essai).

**Résultat attendu** : Réglages s'ouvre sur la section Collection & Rangement ; la ligne « Règle de rangement dans le meuble » prend la teinte du thème pendant environ 2 s puis revient à la normale, sans décalage de mise en page. Le menu reste utilisable pendant la mise en évidence. Ouvrir Réglages normalement ne met rien en évidence.

- [ ] Passé — date / appareil / version :

### J31 — Guide de rangement : toucher le disque central ou « ICI » `AUDIT`

**Conditions** : Une fiche de disque de la Collection, rangement configuré.

**Étapes** :

1. Ouvrir le guide de rangement depuis la fiche.
2. Toucher la pochette centrale, puis le repère « ICI », plusieurs fois de suite.
3. Toucher un disque voisin (gauche ou droite).
4. Activer Réglages iOS → Accessibilité → Mouvement → Réduire les animations et refaire l'étape 2. Essayer aussi avec VoiceOver.

**Résultat attendu** : Le repère « ICI » est à plat (texte rose sans fond ni ombre, il ne ressemble plus à un bouton). Toucher le centre fait rebondir la pochette, sa bordure rose s'épaissit un instant, avec un léger retour haptique, sans rien ouvrir ni fermer. Un voisin ouvre toujours sa fiche. Avec Réduire les animations : seule la bordure change, sans mouvement. VoiceOver lit le centre d'un seul bloc, sans le présenter comme un bouton.

- [ ] Passé — date / appareil / version :

### J32 — Choix d'un dossier (exemplaire, ajout depuis la fiche) : « All » n'est pas proposé `AUDIT`

**Conditions** : Compte avec au moins deux dossiers en plus de « All ».

**Étapes** :

1. Ouvrir la fiche d'un disque de la Collection, puis « Mon exemplaire ».
2. Toucher le sélecteur « Dossier ».
3. Choisir un autre dossier et enregistrer.
4. Sur la fiche d'un disque, faire un appui long sur le bouton « Collection » (disque pas encore possédé, réglage « Toujours demander » ou plusieurs dossiers), puis ouvrir le menu « Ajouter un autre exemplaire » d'un disque déjà possédé.

**Résultat attendu** : Aucune de ces listes ne contient « All » : elles ne contiennent que les vrais dossiers (Uncategorized et ceux créés par l'utilisateur). Le déplacement fonctionne et l'exemplaire apparaît dans le dossier choisi.

- [ ] Passé — date / appareil / version :

### J33 — Aide « Comment ça fonctionne ? » du suivi de plus-value sans Premium `AUDIT`

**Conditions** : Compte sans abonnement (puis avec abonnement).

**Étapes** :

1. Réglages → section « Suivi de plus-value ».
2. Toucher « Comment ça fonctionne ? ».
3. Refaire avec un abonnement actif.

**Résultat attendu** : Sans Premium, la carte d'offre s'affiche et, juste en dessous, l'entrée « Comment ça fonctionne ? » reste accessible : elle ouvre l'aide sur le prix d'achat et l'état de la pochette, sans paywall. Avec Premium, l'entrée est la même et la carte d'offre disparaît.

- [ ] Passé — date / appareil / version :

### J34 — Guide de rangement : entrée animée, compteur, jauge et halo du disque cible `AUDIT` `PREMIUM`

**Conditions** : Compte Premium, collection chargée ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir le guide de rangement d'un disque.
2. Observer l'ouverture pendant 2 secondes puis le disque cible pendant 10 secondes.
3. Toucher un disque voisin (fiche), revenir en arrière.
4. Fermer et rouvrir le guide ; essayer sur un disque en début ou en fin de meuble.
5. Refaire avec Réduire les animations activé.

**Résultat attendu** : À l'ouverture : le numéro « N° … » défile depuis 0 jusqu'à la position du disque pendant que la jauge se remplit ; les deux voisins (ou les colonnes « Début / Fin du meuble ») glissent depuis les côtés, puis le disque cible descend entre eux avec un léger rebond ; une fois tout en place, la pochette centrale se met à grossir puis reprendre sa taille lentement (environ 2,4 s par aller-retour, en continu tant que le guide est ouvert), un halo rose discret respire derrière elle et le repère « ICI » bat doucement (le repère ne fait pas de zoom d'accent). Le texte reste lisible dès le début. Revenir d'une fiche voisine ne rejoue pas l'entrée. Rouvrir le guide la rejoue. Le toucher sur le disque central garde son rebond et son retour haptique. Avec Réduire les animations : tout est affiché directement, sans halo ni battement.

- [ ] Passé — date / appareil / version :

### J35 — Réglages : écran d'accueil organisé par pages `AUDIT`

**Conditions** : Compte connecté ; Premium puis non Premium ; mode démo ; thème clair et sombre.

**Étapes** :

1. Ouvrir l'onglet Réglages.
2. Parcourir l'accueil : carte compte (avatar, nom, badges de grades, « Mes grades »), bannière Premium si non abonné, puis les groupes Ma collection, Écoute, Synchronisation, Aide & personnalisation, et en bas la déconnexion.
3. Ouvrir chaque ligne : Organisation, Rangement, Suivi de plus-value, Export, Écoute et Apple Music, Synchronisation iCloud, Données hors ligne, Apparence, Guide, À propos.
4. Revenir en arrière puis re-toucher l'onglet Réglages.

**Résultat attendu** : L'accueil tient en une quinzaine de lignes, chacune avec son icône, son titre et un résumé en gris (règle de rangement, thème, version, état d'iCloud…). Chaque ligne ouvre sa page, qui contient les réglages auparavant empilés sur une seule liste, inchangés dans leur comportement. La page « Rangement » ne contient que la règle de rangement dans le meuble et « Limiter au dossier Discogs » ; la page « Organisation » a deux sections : « Organisation » (tags, dossiers) et « Personnalisation du tri par artiste » (« Ignorer les articles », « Trier par nom de famille », puis « Personnaliser le tri des artistes » quand le tri par nom de famille est actif). Les lignes Premium portent la pastille de la démo ; sans abonnement, iCloud, Export, Suivi de plus-value et Données hors ligne affichent leur carte Premium. Le re-tap sur l'onglet revient à la racine puis en haut de page.

- [ ] Passé — date / appareil / version :

### J36 — Réglages : recherche d'un réglage `AUDIT` `AUTO`

**Conditions** : Réglages ouvert à la racine ; compte connecté puis déconnecté ; app en français puis en anglais.

**Étapes** :

1. Tirer l'écran vers le bas ou toucher le champ « Rechercher un réglage ».
2. Taper « icloud », « tag », « etat », « dark », « csv », « prix achat », puis un mot sans rapport.
3. Toucher un résultat, puis revenir.
4. Se déconnecter et chercher « dossier » et « devise ».

**Résultat attendu** : Les résultats s'affichent à la place de la liste : chaque ligne montre le réglage et sa page (ex. « Devise par défaut — Suivi de plus-value ») ; un toucher ouvre la page concernée. La recherche ignore la casse et les accents, accepte plusieurs mots, et trouve aussi par mots-clés en français et en anglais quelle que soit la langue de l'app. Sans résultat, un message l'indique. Déconnecté, les réglages qui exigent un compte (dossiers, champs de prix, devise) n'apparaissent pas (règles couvertes par SettingsSearchTests).

- [ ] Passé — date / appareil / version :

### J37 — Réglages : liens profonds vers les sous-pages `AUDIT`

**Conditions** : Compte connecté avec une collection ; pastille « Utilisé pour la plus-value » visible dans « Mon exemplaire » ; guide de rangement ouvert.

**Étapes** :

1. Dans « Mon exemplaire », toucher la pastille « Utilisé pour la plus-value » d'un champ.
2. Revenir, puis dans le guide de rangement toucher « Modifier » sur la méthode de classement.
3. Dans l'aide « Comment ça fonctionne ? » du suivi de plus-value, toucher « Choisir mes champs dans Réglages ».
4. Refaire 1 et 2 à la toute première ouverture de Réglages après le lancement.

**Résultat attendu** : 1 ouvre Réglages > Suivi de plus-value, centré sur la section « Prix d'achat et état », la ligne du champ concerné mise en évidence environ 2 s dans la teinte du champ. 2 ouvre Réglages > Rangement avec la règle de rangement mise en évidence 2 s. 3 ouvre la page « Suivi de plus-value ». Même comportement à la toute première visite de Réglages. Le retour ramène à la racine propre, sans pile résiduelle.

- [ ] Passé — date / appareil / version :

### J38 — Réglages : « Mode Hors Ligne » et « Couleur du thème » comme les autres pages `AUDIT`

**Conditions** : Compte Premium ; thème clair puis sombre ; texte en taille standard puis très grande ; Mode Hors Ligne avec et sans archive locale.

**Étapes** :

1. Ouvrir Réglages > Données hors ligne > Mode Hors Ligne, et comparer avec Apparence ou Rangement.
2. Lancer une synchronisation, activer puis désactiver « Synchro auto en Wi-Fi », ouvrir « Vider le cache d'images ».
3. Ouvrir Réglages > Apparence > Couleur du thème, choisir un thème, toucher un thème verrouillé (compte non Premium).
4. Refaire avec le thème sombre et une très grande taille de texte.

**Résultat attendu** : Les deux pages ont le même habillage que les autres sous-pages : sections en cartes groupées sur le fond de l'app, titres de section en rose avec icône, lignes à pastille colorée. La carte « Archive locale » (Mode Hors Ligne) et l'aperçu du thème restent en tête de page, dans une carte au même fond que les lignes. Toutes les actions fonctionnent comme avant ; rien n'est coupé ni superposé en très grande taille de texte.

- [ ] Passé — date / appareil / version :

### J39 — Réglages : les lignes qui apparaissent ou changent d'état se fondent `AUDIT`

**Conditions** : Compte Premium connecté ; Réduire les animations désactivé puis activé ; compte Apple Music disponible.

**Étapes** :

1. Réglages > Organisation : activer puis désactiver « Trier par nom de famille ».
2. Réglages > Écoute et Apple Music : activer « Connecter mon compte Apple Music » et observer « Connexion en cours… » puis l'éventuel avertissement d'abonnement.
3. Réglages > Export : lancer l'export CSV puis la déclaration PDF.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : La ligne « Personnaliser le tri des artistes » apparaît et disparaît en fondu avec le réglage ; « Connexion en cours… » et l'avertissement d'abonnement apparaissent en fondu ; dans Export, l'icône de partage et l'indicateur d'avancement se remplacent en fondu. Avec Réduire les animations : tout change sans mouvement. Aucune autre ligne de la page ne bouge.

- [ ] Passé — date / appareil / version :

### J40 — Assistance : lien du paywall et ligne de « À propos » `AUDIT`

**Conditions** : Réseau disponible ; compte sans Premium pour voir le paywall (ou option développeur « Afficher le paywall »). La page https://auralabsapp.github.io/Spinfolio/support.html doit répondre.

**Étapes** :

1. Ouvrir le paywall (Réglages > bannière Premium) et regarder la ligne de liens tout en bas.
2. Toucher « Assistance ».
3. Revenir à l'app, puis Réglages > À propos : toucher « Assistance » (sous « Site web Discogs »).
4. Recommencer l'étape 1 sur un iPhone de petite taille (13 mini) et avec une taille de texte agrandie.
5. Passer l'iPhone en anglais et regarder le libellé.
6. Mode avion : toucher « Assistance » dans « À propos ».

**Résultat attendu** : Le paywall affiche trois liens, « Conditions d'utilisation », « Confidentialité » et « Assistance », sans coupure de mot ni débordement (à défaut, ils passent proprement sur deux lignes). « Assistance » ouvre la page d'assistance du site (français et anglais, avec un lien de retour vers le site) ; depuis « À propos », elle s'ouvre dans la feuille Safari de l'app. En anglais, le libellé est « Support ». Sans réseau, la feuille s'ouvre sans planter, avec la page d'erreur de Safari ; aucune autre fonction de l'app n'est affectée.

- [ ] Passé — date / appareil / version :

### J41 — Tags réservés au Premium : lecture et filtre seuls sans abonnement `AUDIT` `PREMIUM`

**Conditions** : Compte Premium avec quelques tags posés sur des albums (version de développement : Réglages > Options développeur pour simuler la perte du Premium) ; puis un compte sans Premium qui n'a jamais eu de tags.

**Étapes** :

1. Avec Premium : fiche d'un exemplaire > Modifier > « Tags de l'exemplaire » : ajouter, retirer, créer un tag ; Réglages > Organisation > Gestion des tags : créer, renommer, supprimer ; Collection > Sélectionner > icône tag.
2. Passer sans Premium (perte de l'abonnement ou forçage développeur).
3. Reprendre chacun des écrans du point 1.
4. Collection > ··· > Filtres : filtrer par tag.
5. Revenir en Premium.
6. Compte sans Premium sans aucun tag : ouvrir « Tags de l'exemplaire » et « Gestion des tags ».

**Résultat attendu** : 3 : les tags déjà posés restent affichés sans croix de retrait ni bouton « Ajouter » ; une carte « Tags » (Premium) mène au paywall ; dans « Gestion des tags », la liste reste consultable et filtrable par la recherche, sans création, renommage ni suppression (ni balayage, ni appui long), avec la carte Premium en tête ; dans Collection, l'icône tag de la sélection ouvre le paywall. 4 : le filtre par tag fonctionne comme avant. 5 : tout redevient modifiable, rien n'a été perdu. 6 : la carte « Tags » seule, aucune liste. En démo : la section porte l'étiquette Premium.

- [ ] Passé — date / appareil / version :

### J42 — À propos : ligne « Donner mon avis » `AUDIT`

**Conditions** : Réseau disponible ; app App Store installée sur l'iPhone ; fiche de l'app publiée (sur un build de test, la page peut afficher « indisponible »).

**Étapes** :

1. Réglages > À propos : repérer la ligne « Donner mon avis » (étoile jaune), sous « Assistance ».
2. La toucher.
3. Revenir à l'app.
4. Passer l'iPhone en anglais et regarder le libellé.
5. Activer VoiceOver et se placer sur la ligne.

**Résultat attendu** : La ligne affiche une étoile jaune et une flèche, comme « Assistance ». Elle ouvre l'App Store directement sur l'écran « Écrire un avis » de Spinfolio (pas une vue Safari dans l'app) ; en revenant, l'app est comme avant. En anglais, le libellé est « Rate Spinfolio ». VoiceOver annonce « Donner mon avis », bouton, lien. Aucun plafond : la ligne ouvre toujours l'écran, y compris si l'utilisateur a déjà donné son avis (il peut alors le modifier).

- [ ] Passé — date / appareil / version :

### J43 — Demande d'avis App Store après des actions faites dans l'app `AUDIT` `AUTO`

**Conditions** : Build de développement (la demande s'affiche toujours) puis TestFlight (elle ne s'affiche jamais : vérifier seulement l'absence de blocage). Compte réel ; iPhone en français puis en anglais. Pour retester : Réglages > Supprimer mes données remet les compteurs à zéro, et la date de dernière demande se réinitialise en réinstallant l'app.

**Étapes** :

1. Écoute sur platine : lancer « J'écoute », attendre plus d'une minute, toucher « Arrêter l'écoute ».
2. Recommencer avec une écoute de moins d'une minute (nouveau compte ou après réinitialisation).
3. Laisser une écoute atteindre l'arrêt automatique (durée maximale réglée à la plus courte).
4. Ajouter 10 albums depuis les fiches, le scan ou le scan par lot (compte de test à zéro) ; observer au 10e ajout, y compris à la fin d'un scan par lot.
5. Connecter un compte Discogs qui possède déjà plus de 10 albums, ajouter des albums sur discogs.com, puis rouvrir l'app.
6. Ouvrir une feuille (paywall, fiche en feuille) juste après le palier.
7. Passer en mode démo et refaire les étapes 1 et 4.
8. Se reconnecter à un autre compte.

**Résultat attendu** : 1 : environ 2 s après le retour à l'écran normal (la feuille d'écoute fermée), la demande d'avis du système apparaît, une seule fois. 2 : rien ne s'affiche. 3 : l'arrêt automatique ne compte pas. 4 : la demande apparaît au 10e album ajouté (et au 50e, si plus de 60 jours se sont écoulés et que la version de l'app a changé) ; avec un scan par lot, elle n'apparaît qu'après la fermeture du scan. 5 : l'import et les ajouts faits sur Discogs ne déclenchent rien, et les grades obtenus à l'import non plus. 6 : si une feuille ou une alerte est ouverte, la demande attend (jusqu'à 30 s) puis est abandonnée sans rien consigner ; elle n'apparaît jamais par-dessus. 7 : rien n'est compté ni demandé en démo. 8 : chaque compte a ses propres compteurs. Aucune demande plus d'une fois par version de l'app ni moins de 60 jours après la précédente (règles couvertes par ReviewPromptTests). Les ajouts à la wantlist ne comptent pas ; passer un album de la wantlist à la collection compte comme un ajout.

- [ ] Passé — date / appareil / version :

### J44 — Export : sauvegarde JSON cachée (7 touchers sur la version) `AUDIT` `AUTO`

**Conditions** : Build TestFlight (Release) ou Xcode ; compte Discogs avec quelques tags posés ; un second compte pour l'étape 6. Sur un build App Store, le geste ne fait rien (comme les diagnostics).

**Étapes** :

1. Réglages > Export : vérifier qu'aucune section « Sauvegarde interne (JSON) » n'apparaît.
2. Réglages > À propos : toucher 7 fois de suite la ligne « Version » (moins d'une seconde entre deux touchers), puis revenir sur « Export ».
3. Toucher « Exporter une sauvegarde JSON », enregistrer le fichier dans Fichiers.
4. Supprimer un tag, puis « Restaurer une sauvegarde JSON », choisir le fichier, confirmer « Remplacer les données locales ».
5. Refaire 4 en choisissant « Annuler ».
6. Se connecter avec un autre compte et tenter de restaurer le fichier du premier.
7. Retoucher 7 fois la version, puis revenir sur « Export ».
8. Passer en mode démo et ouvrir la section.

**Résultat attendu** : 1 : Export n'affiche que le CSV et le PDF. 2 : la section « Sauvegarde interne (JSON) » apparaît sous les exports (même geste que les diagnostics : ils apparaissent aussi dans l'accueil de Réglages). 3 : le fichier est enregistré, avec une alerte de confirmation. 4 : une alerte résume le fichier (date, compte, nombre de tags) ; après confirmation, le tag supprimé revient. 5 : rien ne change. 6 : la restauration est refusée, avec le nom des deux comptes. 7 : la section disparaît (et les diagnostics aussi). 8 : les deux lignes sont grisées (« Connexion à Discogs requise »). Textes non traduits, voulu (outil de test). La vérification du fichier (compte, fichier illisible, nom) est couverte par UserDataBackupServiceTests.

- [ ] Passé — date / appareil / version :

<a id="famille-k"></a>

## K — Réglages — Export & sauvegarde

### K1 — Export CSV complet `PREMIUM`

**Conditions** : Compte premium, collection non vide, réseau disponible.

**Étapes** :

1. Réglages → Export → Export CSV.

**Résultat attendu** : Fichier CSV généré avec toutes les métadonnées, notes et tags ; partage/enregistrement fonctionnel.

- [ ] Passé — date / appareil / version :

### K2 — Export PDF « Déclaration de collection » `PREMIUM`

**Conditions** : Compte premium, collection non vide.

**Étapes** :

1. Réglages → Export → Déclaration de collection (PDF).

**Résultat attendu** : PDF généré avec : page de garde (compte, date, nombre d'exemplaires, total investi, valeur Discogs) sous le nom « Spinfolio » ; tableau paginé (album / format-année / état / prix d'achat) avec miniatures de pochettes ; texte non inversé/mirroité.

- [ ] Passé — date / appareil / version :

### K3 — Tentative d'export — non premium `PREMIUM`

**Conditions** : Compte non premium.

**Étapes** :

1. Essayer d'exporter en CSV ou PDF.

**Résultat attendu** : Carte verrouillée / paywall affiché, aucun fichier généré.

- [ ] Passé — date / appareil / version :

### K4 — Export avec collection vide

**Conditions** : Dossier filtré vide ou collection vide.

**Étapes** :

1. Lancer un export.

**Résultat attendu** : Message d'erreur « Collection vide », pas de fichier corrompu généré.

- [ ] Passé — date / appareil / version :

### K5 — Export sans connexion

**Conditions** : Mode avion activé.

**Étapes** :

1. Lancer un export nécessitant les pochettes/cote à jour.

**Résultat attendu** : Message d'erreur réseau clair, pas de crash.

- [ ] Passé — date / appareil / version :

### K6 — Perte du premium pendant un export en cours `LIMITE` `PREMIUM`

**Conditions** : Export CSV/PDF lancé, premium désactivé juste après (option développeur).

**Étapes** :

1. Désactiver le premium pendant la génération.

**Résultat attendu** : L'export en cours se termine normalement (pas interrompu brutalement), ou échoue avec message clair si vraiment coupé à mi-chemin.

- [ ] Passé — date / appareil / version :

### K7 — Caractères spéciaux dans les tags/notes exportés `LIMITE` `PREMIUM`

**Conditions** : Un exemplaire avec guillemets, virgules et retours à la ligne dans ses notes/tags.

**Étapes** :

1. Exporter en CSV.
2. Ouvrir le fichier dans Numbers/Excel.

**Résultat attendu** : Le CSV reste valide (échappement correct des guillemets/virgules/retours ligne), aucune colonne décalée.

- [ ] Passé — date / appareil / version :

### K8 — Export d'une collection à exactement 1 exemplaire `LIMITE` `PREMIUM`

**Conditions** : Dossier filtré à 1 seul exemplaire.

**Étapes** :

1. Exporter en CSV puis en PDF.

**Résultat attendu** : Les deux fichiers se génèrent normalement avec une seule ligne/page de contenu, pas de division par zéro sur les totaux/moyennes.

- [ ] Passé — date / appareil / version :

### K9 — Restauration d'une sauvegarde propagée à iCloud `AUDIT` `DEV` `PREMIUM` `2 APPAREILS`

**Conditions** : Build Debug, synchro iCloud active sur 2 appareils, sauvegarde JSON exportée auparavant.

**Étapes** :

1. Modifier quelques tags et sessions d'écoute.
2. Options développeur › restaurer la sauvegarde sur l'appareil 1.
3. Observer l'appareil 2.

**Résultat attendu** : L'appareil 2 reflète l'état restauré : tags et sessions de la sauvegarde présents, tags absents de la sauvegarde retirés.

- [ ] Passé — date / appareil / version :

### K10 — Sauvegarde contenant un tag en double `AUDIT` `DEV` `LIMITE`

**Conditions** : Fichier de sauvegarde édité à la main : un exemplaire avec deux fois le même tag.

**Étapes** :

1. Restaurer ce fichier.
2. Ajouter puis retirer un tag sur cet exemplaire.

**Résultat attendu** : Aucun crash ; le tag n'apparaît qu'une fois sur l'exemplaire.

- [ ] Passé — date / appareil / version :

### K13 — Diagnostic de la synchro iCloud (hors App Store) `AUDIT` `PREMIUM`

**Conditions** : Build TestFlight, connecté à Discogs, Premium actif, interrupteur iCloud allumé ; diagnostic d'abonnement déverrouillé (7 touchers sur « Version » dans À propos).

**Étapes** :

1. Ouvrir Réglages : lire la section « Diagnostic synchro iCloud (test) ».
2. Modifier un tag, toucher « Actualiser ».
3. Toucher « Relancer la fusion et la poussée initiales », puis « Actualiser » après quelques secondes.
4. Couper le Premium (compte sans abonnement) et rouvrir la section.

**Résultat attendu** : 1 : moteur démarré, accès Premium, interrupteur, compte iCloud « connecté », compte Discogs synchronisé, drapeaux de fusion et de poussée initiales. 2 : « Dernier envoi » indique un enregistrement sauvé et « En attente » retombe à 0. 3 : la poussée repart, « Dernier envoi » se met à jour. 4 : moteur non démarré. Toute erreur d'envoi ou de récupération apparaît sous « Dernière erreur » avec son code CloudKit. Section absente sur un build de l'App Store.

- [ ] Passé — date / appareil / version :

### K14 — Mode d'affichage et tri de la Collection et de la Wantlist synchronisés entre appareils `AUDIT` `PREMIUM` `2 APPAREILS`

**Conditions** : 2 appareils sur le même compte iCloud et le même compte Discogs, Premium actif, interrupteur « Synchroniser avec iCloud » allumé sur les deux.

**Étapes** :

1. Appareil 1 : passer la Collection en Mosaïque et la trier par Année (sens décroissant).
2. Appareil 1 : passer la Wantlist en Carrousel et la trier par Artiste.
3. Appareil 2 : ouvrir l'app (ou la remettre au premier plan) et attendre quelques secondes.
4. Appareil 2 : changer le tri de la Collection (Date d'ajout) et le mode de la Wantlist (Liste), observer l'appareil 1.
5. Relancer l'app sur l'appareil 2 : le tri de la Wantlist est-il conservé ?

**Résultat attendu** : 3 : la Collection s'affiche en Mosaïque triée par Année (décroissant) et la Wantlist en Carrousel triée par Artiste, sans action de l'utilisateur et sans retour à la liste initiale. 4 : l'appareil 1 reflète ces changements à son tour, sans boucle d'envois (« Dernier envoi » du diagnostic iCloud stable). 5 : le tri de la Wantlist est mémorisé d'un lancement à l'autre (il ne l'était pas avant). Le filtre actif et le dossier consulté ne sont pas synchronisés.

- [ ] Passé — date / appareil / version :

### K15 — Affichage synchronisé : version précédente de l'app et compte gratuit `AUDIT` `LIMITE`

**Conditions** : Un appareil sur une ancienne version de l'app (TestFlight précédent) et un sur la nouvelle ; ou un compte gratuit.

**Étapes** :

1. Changer la devise par défaut sur l'ancienne version, observer la nouvelle.
2. Changer le mode d'affichage sur la nouvelle version, observer l'ancienne.
3. Compte gratuit : changer le mode d'affichage et le tri.

**Résultat attendu** : 1 : la nouvelle version reçoit la devise sans perdre son mode d'affichage ni son tri. 2 : l'ancienne version ignore ces réglages sans erreur, les autres préférences restent synchronisées. 3 : rien n'est envoyé à iCloud (pas de synchro hors Premium) ; les choix restent mémorisés sur l'appareil.

- [ ] Passé — date / appareil / version :

<a id="famille-l"></a>

## L — Premium — Paywall, achat, restauration, dégradation

### L1 — Ouverture de la paywall — tous les points d'entrée

**Conditions** : Compte non premium.

**Étapes** :

1. Ouvrir la paywall depuis : Réglages, une carte verrouillée (ex. Suivi de plus-value dans Stats), une fonctionnalité premium en fiche détail, et le lancement initial si applicable.

**Résultat attendu** : Dans tous les cas, la même `SubscriptionStoreView` s'affiche avec bannière, liste de fonctionnalités et forfaits natifs.

- [ ] Passé — date / appareil / version :

### L2 — Achat de l'abonnement annuel

**Conditions** : Scheme Xcode avec `Spinlog.storekit`, ou sandbox après validation Apple.

**Étapes** :

1. Sélectionner le forfait annuel dans le picker natif → confirmer l'achat.

**Résultat attendu** : Achat validé, statut premium activé immédiatement, fermeture automatique de la paywall avec retour haptique de succès.

- [ ] Passé — date / appareil / version :

### L3 — Achat de l'abonnement mensuel

**Conditions** : Idem L2.

**Étapes** :

1. Sélectionner le forfait mensuel → confirmer l'achat.

**Résultat attendu** : Idem L2 pour le forfait mensuel.

- [ ] Passé — date / appareil / version :

### L4 — Annulation d'un achat en cours

**Conditions** : Feuille d'achat StoreKit affichée.

**Étapes** :

1. Annuler avant confirmation (Face ID/Touch ID annulé ou bouton Annuler).

**Résultat attendu** : Retour à la paywall sans erreur affichée, statut premium inchangé.

- [ ] Passé — date / appareil / version :

### L5 — Restauration des achats (bouton natif)

**Conditions** : Abonnement déjà actif sur le compte Apple.

**Étapes** :

1. Paywall → bouton natif « Restaurer les achats ».

**Résultat attendu** : Le statut premium est restauré sans nouvel achat, via `AppStore.sync()` déclenché par le composant natif.

- [ ] Passé — date / appareil / version :

### L6 — Liens CGU / Confidentialité natifs

**Conditions** : Paywall affichée.

**Étapes** :

1. Toucher les boutons natifs de mentions légales (`storeButton(.policies)`).

**Résultat attendu** : Les deux pages s'ouvrent correctement (CLUF standard Apple et page de confidentialité Spinfolio) via `subscriptionStorePolicyDestination`.

- [ ] Passé — date / appareil / version :

### L7 — Fermeture de la paywall (bouton natif)

**Conditions** : Paywall affichée.

**Étapes** :

1. Toucher le bouton de fermeture automatique fourni par `SubscriptionStoreView`.

**Résultat attendu** : Retour à l'écran précédent sans achat.

- [ ] Passé — date / appareil / version :

### L8 — Perte du statut premium — coupure de toutes les fonctions `RÉGRESSION`

**Conditions** : Compte premium actif utilisant iCloud sync, mode hors ligne et au moins une alerte wantlist.

**Étapes** :

1. Désactiver le premium (option développeur ou expiration réelle de l'abonnement).

**Résultat attendu** : Toutes les fonctions premium se coupent : synchro iCloud stoppée, auto-sync hors ligne stoppé, vérification/notifications d'alertes wantlist stoppées, thème repassé par défaut.

- [ ] Passé — date / appareil / version :

### L9 — Reprise automatique après ré-abonnement `RÉGRESSION`

**Conditions** : Suite à L8, avec des alertes wantlist existantes.

**Étapes** :

1. Réactiver le premium sans relancer l'app.

**Résultat attendu** : La synchro iCloud et les vérifications d'alertes reprennent immédiatement (écoute de `.premiumStatusChanged`), sans relancer l'app.

- [ ] Passé — date / appareil / version :

### L10 — Option développeur « Compte Premium » `DEV`

**Conditions** : Build Debug.

**Étapes** :

1. Réglages → Options développeur → basculer le compte premium.

**Résultat attendu** : Le statut bascule immédiatement dans toute l'app ; ne force jamais un retour à `false` si un vrai abonnement StoreKit est actif.

- [ ] Passé — date / appareil / version :

### L11 — Identifiants de produit différents de ceux de l'App Store `AUDIT` `LIMITE`

**Conditions** : Build sandbox/production pointant vers le vrai App Store (pas `Spinlog.storekit`).

**Étapes** :

1. Ouvrir la paywall.

**Résultat attendu** : Le paywall charge les abonnements par leurs identifiants de produit (annuel, mensuel) et l'achat à vie par le sien, plus par l'identifiant du groupe. Si l'un diffère de celui d'App Store Connect, il manque à l'écran : à vérifier avant chaque soumission, ce n'est pas détectable avec le fichier `.storekit`.

- [ ] Passé — date / appareil / version :

### L12 — Achat avec restriction parentale active (Ask to Buy) `LIMITE`

**Conditions** : Compte enfant avec autorisation parentale requise.

**Étapes** :

1. Lancer un achat depuis ce compte.

**Résultat attendu** : L'achat passe en état « en attente » (`.pending`) sans erreur ni fermeture prématurée de la paywall ; le statut premium s'active automatiquement si le parent approuve plus tard.

- [ ] Passé — date / appareil / version :

### L13 — Restauration sans aucun achat existant `LIMITE`

**Conditions** : Compte Apple n'ayant jamais souscrit.

**Étapes** :

1. Toucher « Restaurer les achats ».

**Résultat attendu** : Aucune erreur bloquante ; le statut premium reste simplement inactif, message neutre si le composant natif en affiche un.

- [ ] Passé — date / appareil / version :

### L14 — Essai gratuit déjà utilisé précédemment `LIMITE`

**Conditions** : Compte Apple ayant déjà consommé l'essai gratuit de l'abonnement annuel.

**Étapes** :

1. Rouvrir la paywall et sélectionner l'abonnement annuel.

**Résultat attendu** : Le prix plein est proposé directement, sans ré-afficher la mention d'essai gratuit (comportement géré nativement par StoreKit, à vérifier visuellement).

- [ ] Passé — date / appareil / version :

### L15 — Achat interrompu par un appel/notification système `LIMITE`

**Conditions** : Achat en cours de confirmation (Face ID).

**Étapes** :

1. Recevoir un appel ou une notification système pendant la confirmation.

**Résultat attendu** : L'achat reprend ou peut être relancé proprement au retour dans l'app ; pas de double facturation ni d'état bloqué.

- [ ] Passé — date / appareil / version :

### L16 — Family Sharing — abonnement déjà actif via un autre membre `LIMITE`

**Conditions** : Abonnement familial partagé, achat déjà fait par un autre membre du groupe familial.

**Étapes** :

1. Ouvrir la paywall sur un appareil d'un autre membre de la famille.

**Résultat attendu** : Le statut premium est reconnu comme actif sans nouvel achat, si le partage familial est activé pour ce produit.

- [ ] Passé — date / appareil / version :

### L17 — Paywall après la connexion : au plus une fois par semaine `AUDIT` `AUTO`

**Conditions** : Compte non premium, app fraîchement installée.

**Étapes** :

1. Lancer l'app : l'écran de connexion s'affiche, SANS paywall.
2. Se connecter à Discogs (ou lancer la démo) : la paywall s'affiche juste après la connexion ; la fermer.
3. Relancer l'app plusieurs fois.
4. Avancer la date de l'appareil de 7 jours et relancer.

**Résultat attendu** : Aucune paywall avant la connexion ; paywall à la première connexion (compte ou démo), plus aux relances suivantes, de nouveau après 7 jours (une fois connecté). Toujours accessible depuis Réglages et les cartes verrouillées. Jamais affichée pour un abonné, ni pendant une déconnexion.

- [ ] Passé — date / appareil / version :

### L18 — Achat : Premium actif immédiatement `AUDIT` `PREMIUM`

**Conditions** : Compte sandbox, non premium.

**Étapes** :

1. Acheter un forfait depuis la paywall.

**Résultat attendu** : La paywall se ferme et les fonctions Premium sont débloquées immédiatement, sans relancer l'app.

- [ ] Passé — date / appareil / version :

### L19 — Abonnement revérifié au retour au premier plan `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Abonnement sandbox à renouvellement accéléré, ou remboursement depuis un autre appareil.

**Étapes** :

1. Mettre l'app en arrière-plan jusqu'à l'expiration ou au remboursement.
2. La ramener au premier plan.

**Résultat attendu** : Le statut Premium est mis à jour au retour au premier plan, sans relancement.

- [ ] Passé — date / appareil / version :

### L20 — Démo : aperçu Premium et offre toujours proposée `AUDIT` `PREMIUM`

**Conditions** : Appareil NON premium, mode démo actif.

**Étapes** :

1. Ouvrir Stats, export, thèmes, suivi de cote.
2. Regarder Réglages, puis quitter la démo.

**Résultat attendu** : Les fonctions Premium sont accessibles pendant la démo ; la bannière Premium de Réglages reste affichée. Après la sortie, tout est de nouveau verrouillé et un thème Premium revient au thème par défaut. Réglages → Compte Discogs affiche « Aperçu Premium (mode démo) » avec son explication ; la ligne disparaît en quittant la démo (et n'apparaît pas avec un abonnement réel).

- [ ] Passé — date / appareil / version :

### L21 — Démo : fonctions Premium étiquetées `AUDIT` `PREMIUM`

**Conditions** : Appareil SANS abonnement, mode démo actif.

**Étapes** :

1. Ouvrir une fiche disque de la collection (Emplacement de cet album), Mon exemplaire (Plus-value), Stats (Tops & Palmarès, Investi vs Cote actuelle), le rangement, une alerte de prix, le scan par lot (icône de la barre de recherche et titre de l'écran).
2. Réglages : Suivi de plus-value, Données hors ligne, Synchronisation iCloud, Couleur du thème, export CSV.
3. Recommencer avec un abonnement actif, puis hors démo.

**Résultat attendu** : Chaque fonction Premium reste utilisable et porte l'étiquette dorée « ✨ PREMIUM » (VoiceOver : « Fonction Premium, offerte pendant la démo ») ; l'écran des thèmes rappelle quels thèmes sont Premium. L'icône du scan par lot porte une pastille dorée à étincelles (VoiceOver : « Scan par lot (Premium) »). En démo, l'interrupteur « Synchroniser avec iCloud » est visible mais coupé et grisé, avec la mention « Désactivée pendant la démo ». Aucune étiquette avec un abonnement réel ni hors démo.

- [ ] Passé — date / appareil / version :

### L30 — Liste des fonctions Premium : paywall et feuille des palettes identiques `AUDIT` `AUTO`

**Conditions** : Compte sans abonnement.

**Étapes** :

1. Ouvrir le paywall (bannière Premium de Réglages).
2. Déplier « et N fonctionnalités supplémentaires ».
3. Dans Réglages > Apparence > « Couleur du thème », toucher une palette verrouillée pour ouvrir la feuille « Fonctionnalités premium ».
4. Comparer les deux listes.

**Résultat attendu** : Les deux listes ont les mêmes 9 fonctions avec les mêmes textes (en particulier « Mode hors ligne » : « …pour fouiner en brocante sans aucun réseau »). Les icônes « Palmarès d'écoute » et « Thèmes » sont dorées dans le paywall et roses dans la feuille, comme avant.

- [ ] Passé — date / appareil / version :

### L31 — Diagnostic d'abonnement masqué, déverrouillé par 7 touchers sur la version `AUDIT`

**Conditions** : Build TestFlight (ou sandbox), puis la version App Store une fois publiée.

**Étapes** :

1. Ouvrir Réglages : vérifier l'absence de la section de diagnostic.
2. Réglages > À propos : toucher 7 fois rapidement la ligne « Version », puis revenir aux Réglages.
3. Relancer l'app, puis refaire les 7 touchers.
4. Sur la version App Store : 7 touchers sur la version.

**Résultat attendu** : 1 : section absente par défaut. 2 : vibration de succès, la section de diagnostic apparaît dans Réglages. 3 : elle reste affichée après relance, puis disparaît après 7 nouveaux touchers. Un toucher isolé ou des touchers espacés de plus d'une seconde ne font rien. 4 : rien ne se passe, jamais de diagnostic.

- [ ] Passé — date / appareil / version :

### L32 — Grille tarifaire France : 1,99 / 17,99 / 39,99 € et partage familial `AUDIT` `PREMIUM`

**Conditions** : Boutique France ; fichier `Spinlog.storekit` puis sandbox.

**Étapes** :

1. Ouvrir le paywall.
2. Lire le sélecteur d'abonnements (annuel d'abord, puis mensuel) et la ligne sous le sélecteur.
3. Lire la bannière de Réglages (compte gratuit).
4. Contrôler dans App Store Connect (ou dans l'éditeur StoreKit) le partage familial de chaque produit.

**Résultat attendu** : 2 : annuel 17,99 € / an avec la mention d'essai d'1 semaine, mensuel 1,99 € / mois sans essai ; dessous, lien « Ou achat unique à 39,99 € » (sous-titre « Premium pour toujours », prix lu chez StoreKit, jamais écrit dans l'app). 3 : « À partir de 1,50 € / mois ». 4 : partage familial activé pour l'annuel et le mensuel, désactivé pour l'achat à vie. Les prix de la page web (docs/index.html) sont les mêmes.

- [ ] Passé — date / appareil / version :

### L33 — Achat de l'abonnement annuel avec essai d'une semaine `AUDIT` `PREMIUM`

**Conditions** : Compte sans abonnement ni essai passé ; fichier `Spinlog.storekit` puis sandbox (l'essai d'une semaine est accéléré en sandbox : quelques minutes).

**Étapes** :

1. Ouvrir le paywall, choisir l'annuel : lire la mention d'essai gratuit avant de confirmer.
2. Confirmer l'achat.
3. Vérifier que le Premium est actif et que le paywall se ferme.
4. Attendre la fin de l'essai (ou avancer dans Xcode > Debug > StoreKit > Manage Transactions).

**Résultat attendu** : 1 : « 7 jours d'essai gratuit » annoncé par StoreKit (aucun texte d'essai écrit dans l'app). 3 : Premium actif immédiatement, retour haptique de succès. 4 : le prix de 17,99 € est débité à la fin de l'essai et le Premium continue.

- [ ] Passé — date / appareil / version :

### L34 — Résiliation pendant l'essai : Premium actif jusqu'à la fin, puis retiré `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Essai annuel en cours (L33).

**Étapes** :

1. Réglages > À propos > « Gérer mon abonnement » : résilier.
2. Revenir dans l'app : le Premium est-il encore actif ?
3. Attendre la fin de l'essai, relancer l'app.

**Résultat attendu** : 2 : encore actif jusqu'à la fin de la période d'essai. 3 : Premium retiré (thème, fonctions réservées, synchro iCloud) sans plantage, le paywall est de nouveau proposé.

- [ ] Passé — date / appareil / version :

### L35 — Personne déjà abonnée par le passé qui revient : aucun essai `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Compte Apple ayant déjà eu l'essai (ou un abonnement) puis résilié ; sandbox.

**Étapes** :

1. Ouvrir le paywall et choisir l'annuel.
2. Confirmer l'achat.

**Résultat attendu** : 1 : aucune mention d'essai gratuit (prix plein 17,99 €). 2 : l'achat est débité sans période d'essai. Le mensuel et l'achat à vie n'affichent jamais d'essai.

- [ ] Passé — date / appareil / version :

### L36 — Achat à vie `AUDIT` `PREMIUM`

**Conditions** : Compte sans abonnement ; fichier `Spinlog.storekit` puis sandbox.

**Étapes** :

1. Ouvrir le paywall, toucher le lien « Ou achat unique à … ».
2. Confirmer l'achat.
3. Relancer l'app, rouvrir Réglages.

**Résultat attendu** : 1 : le lien n'a pas de mention d'essai. 2 : Premium actif immédiatement, retour haptique, le paywall se ferme. 3 : Premium toujours actif (sans date de fin) ; le paywall ne reproposera plus l'achat à vie ; Réglages > À propos n'a plus « Gérer mon abonnement » ni « Utiliser un code » ; la bannière Premium de Réglages a disparu.

- [ ] Passé — date / appareil / version :

### L37 — Abonné (ou en essai) qui passe à l'achat à vie : message de résiliation `AUDIT` `PREMIUM`

**Conditions** : Abonnement annuel ou essai en cours.

**Étapes** :

1. Ouvrir le paywall (depuis un point d'entrée accessible), toucher le lien « Ou achat unique à … » et confirmer.
2. Dans l'alerte, toucher « Gérer mon abonnement ».
3. Refaire en touchant « Plus tard ».

**Résultat attendu** : 1 : alerte « Premium pour toujours » : l'abonnement n'est pas résilié automatiquement. 2 : la feuille système de gestion des abonnements s'ouvre ; à sa fermeture le paywall se ferme. 3 : le paywall se ferme ; Réglages garde « Gérer mon abonnement » tant que l'abonnement est actif.

- [ ] Passé — date / appareil / version :

### L38 — Restauration de l'achat à vie sur un second appareil `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Achat à vie fait sur l'appareil A ; même identifiant Apple sur l'appareil B (Premium inactif).

**Étapes** :

1. Sur B, ouvrir le paywall et toucher « Restaurer les achats » (bouton natif).

**Résultat attendu** : Premium actif sur B, sans nouvel achat ; plus d'offre à vie proposée. Le partage familial n'est pas actif pour ce produit : un autre membre de la famille ne l'obtient pas.

- [ ] Passé — date / appareil / version :

### L39 — Remboursement ou révocation : Premium retiré `AUDIT` `PREMIUM` `AUTO`

**Conditions** : Achat à vie, puis annuel, faits dans Xcode (fichier `Spinlog.storekit`).

**Étapes** :

1. Xcode > Debug > StoreKit > Manage Transactions : rembourser (Refund) l'achat à vie.
2. Revenir dans l'app (premier plan) ou relancer.
3. Refaire avec l'abonnement annuel.

**Résultat attendu** : Premium retiré à chaque fois, sans plantage ; le thème Premium revient au thème par défaut ; l'offre à vie est de nouveau proposée. Règle d'activité couverte par PremiumEntitlementTests.

- [ ] Passé — date / appareil / version :

### L40 — Produit à vie indisponible : offre masquée sans erreur `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Mode avion au lancement du paywall, ou produit à vie absent de App Store Connect (non approuvé).

**Étapes** :

1. Ouvrir le paywall.

**Résultat attendu** : Aucun lien « Ou achat unique », aucun espace vide ni message d'erreur ; les deux abonnements restent proposés quand StoreKit répond. L'offre apparaît d'elle-même au retour du réseau.

- [ ] Passé — date / appareil / version :

### L41 — Code d'offre : depuis le paywall et depuis Réglages (annuel et achat à vie) `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Codes d'offre de test ou sandbox pour l'annuel et pour l'achat à vie (App Store Connect ; seuls les codes sandbox existent avant la mise en distribution).

**Étapes** :

1. Paywall : toucher « Utiliser un code » (lien « Utiliser un code » du paywall) et saisir le code annuel.
2. Réglages > À propos > « Utiliser un code » : saisir le code de l'achat à vie.
3. Fermer la feuille sans saisir de code.
4. Saisir un code invalide.
5. Utiliser un code depuis un lien de rachat ou l'App Store (hors de l'app).

**Résultat attendu** : 1 : Premium actif, paywall refermé. 2 : message « Code utilisé : ton Premium est activé. » et Premium à vie actif. 3 : aucun message. 4 : message d'erreur sur le code. 5 : le Premium s'active à l'ouverture de l'app (écouteur de transactions). La ligne n'est plus proposée à qui a Premium pour toujours.

- [ ] Passé — date / appareil / version :

### L42 — Mode démo : pas de ligne « Utiliser un code » `AUDIT`

**Conditions** : Mode démo actif.

**Étapes** :

1. Réglages > À propos.
2. Chercher « code » dans la recherche de Réglages.

**Résultat attendu** : Pas de ligne « Utiliser un code » ni de résultat de recherche ; texte de l'aperçu Premium : « … sans abonnement ni achat ». Sortie de la démo : la ligne revient (compte sans Premium à vie).

- [ ] Passé — date / appareil / version :

### L43 — Paywall sur mesure : disposition, forfaits, achat, restauration, code, mentions légales `AUDIT` `PREMIUM`

**Conditions** : iPhone (petit modèle inclus) ; thèmes clair et sombre ; compte sandbox/TestFlight avec produits servis (annuel, mensuel, à vie) ; une fois éligible à l'essai, une fois non éligible.

**Étapes** :

1. Ouvrir le paywall et observer l'écran sans faire défiler.
2. Toucher la carte Mensuel puis Annuel.
3. Lire la ligne de renouvellement sous le bouton, pour chaque forfait.
4. Acheter l'annuel (essai ou non) puis annuler la feuille de paiement ; recommencer et valider.
5. Toucher « Ou achat unique à … », « Restaurer un achat » (avec puis sans achat) et « Utiliser un code ».
6. Toucher « Conditions d'utilisation » et « Confidentialité ».
7. Passer en texte agrandi (Accessibilité) et rouvrir le paywall ; essayer sans réseau.
8. Changer le compte (ou la boutique) de test dans Réglages, puis rouvrir le paywall sans quitter l'app.

**Résultat attendu** : 1 : illustration dorée avec la croix de fermeture sur son coin, titre, essai gratuit (si éligible) et avantages dans une zone qui défile ; en bas, panneau épinglé avec deux cartes sans cadre gris (Annuel avec badge « −N % » et « soit X par mois » ; Mensuel « sans engagement »), bouton, mentions, lien d'achat à vie, « Restaurer un achat · Utiliser un code », liens légaux. Les forfaits et le bouton sont visibles sans défiler. 2 : la carte choisie a un contour doré et une coche. 3 : annuel avec essai : « 1 semaine d'essai gratuit, puis X par an. Renouvelé automatiquement jusqu'à ce que tu l'annules. » ; annuel sans essai : « Renouvelé automatiquement à X par an… » ; mensuel : « …par mois… ». Le bouton dit « Commencer l'essai gratuit » seulement pour l'annuel éligible, sinon « S'abonner ». Les prix suivent le format de nombres du système. 4 : annuler ne change rien et ne montre pas d'erreur ; valider active Premium et ferme le paywall. 5 : l'achat à vie fonctionne (alerte pour résilier l'abonnement s'il y en a un) ; la restauration ferme le paywall si un achat existe, sinon « Aucun achat à restaurer pour ce compte Apple. » ; le code ouvre la feuille système. 6 : les pages s'ouvrent. 7 : rien n'est coupé, le contenu défile derrière le panneau ; sans réseau ou produits non servis : « Les abonnements ne sont pas disponibles pour le moment. » et « Réessayer ». 8 : les prix suivent la nouvelle boutique (devise comprise) et correspondent à ceux de la feuille de confirmation d'achat d'Apple.

- [ ] Passé — date / appareil / version :

### L44 — Sortie de démo puis connexion : aucune fiche restante, titre de Collection intact `AUDIT` `AUTO`

**Conditions** : Écran de connexion ; compte Discogs réel disponible.

**Étapes** :

1. Entrer en mode démo, ouvrir une fiche disque dans Collection.
2. Quitter la démo (pastille) pendant que la fiche est ouverte.
3. Se connecter à son compte Discogs.
4. Faire défiler Collection vers le bas puis vers le haut.
5. Refaire avec une fiche ouverte dans Wantlist, Recherche et Réglages.

**Résultat attendu** : 3 : Collection s'affiche sur sa liste, sans fiche ouverte (idem pour les autres onglets). Le titre « Collection » est en New York. 4 : le grand titre se réduit en titre de barre au défilement, la barre reste opaque, rien ne se superpose à la liste.

- [ ] Passé — date / appareil / version :

### L45 — Première connexion sur installation neuve : grand titre de Collection qui se réduit `AUDIT`

**Conditions** : Installation neuve (app supprimée puis réinstallée), compte Discogs jamais connecté sur l'appareil, réseau actif, sans passer par la démo.

**Étapes** :

1. Se connecter à Discogs depuis l'écran d'accueil.
2. Fermer le paywall et la célébration de grade.
3. Dès que Collection est visible, faire défiler la liste vers le bas de plusieurs écrans.
4. Répéter 1 à 3 deux ou trois fois (réinstaller à chaque fois) : le défaut dépendait d'une course entre deux chargements.

**Résultat attendu** : Aucun écran « Collection vide » ne s'affiche entre le squelette et la liste. Au défilement, le grand titre se réduit en petit titre centré et la barre de navigation prend son fond flouté ; les lignes ne passent pas nettes derrière le titre. Même résultat en changeant d'onglet puis en revenant.

- [ ] Passé — date / appareil / version :

### L46 — Déconnexion puis reconnexion : titre de Collection en New York `AUDIT`

**Conditions** : Compte connecté ; faire le test depuis l'onglet Réglages, puis depuis un autre onglet.

**Étapes** :

1. Réglages > Se déconnecter, confirmer.
2. Se reconnecter (même compte, puis un autre compte).
3. Ouvrir l'onglet Collection (ou y arriver directement).
4. Faire défiler la liste, remonter, changer d'onglet et revenir.

**Résultat attendu** : 3 : le gros titre « Collection » est en New York (serif) dès l'arrivée, sans changer d'onglet. 4 : le grand titre se réduit en petit titre au défilement, la barre reste opaque et la police du gros titre ne change pas.

- [ ] Passé — date / appareil / version :

<a id="famille-m"></a>

## M — Synchronisation iCloud

> PREMIUM — nécessite 2 appareils physiques pour la majorité des cas (le Simulateur et le mode « Designed for iPad » sont peu fiables pour les push CloudKit).

### M1 — Activation de la synchro (1er appareil) `PREMIUM`

**Conditions** : Compte premium, iCloud activé sur l'appareil.

**Étapes** :

1. Réglages → vérifier que la synchro iCloud est active.

**Résultat attendu** : Aucune erreur, synchro démarrée.

- [ ] Passé — date / appareil / version :

### M2 — Réception sur un 2e appareil `PREMIUM` `2 APPAREILS`

**Conditions** : Même compte Discogs et même compte iCloud sur 2 appareils réels, appareil 1 avec des tags/sessions existants.

**Étapes** :

1. Connecter l'appareil 2 avec le même compte.

**Résultat attendu** : Tags, journal d'écoute, préférences de tri/affichage et alertes wantlist de l'appareil 1 apparaissent sur l'appareil 2.

- [ ] Passé — date / appareil / version :

### M3 — Propagation appareil 1 → appareil 2 `PREMIUM` `2 APPAREILS`

**Conditions** : Suite à M2.

**Étapes** :

1. Ajouter un tag sur l'appareil 1.

**Résultat attendu** : Le tag apparaît sur l'appareil 2 en quelques secondes.

- [ ] Passé — date / appareil / version :

### M4 — Propagation appareil 2 → appareil 1 `PREMIUM` `2 APPAREILS`

**Conditions** : Suite à M2.

**Étapes** :

1. Changer une préférence de tri sur l'appareil 2.

**Résultat attendu** : La préférence se reflète sur l'appareil 1.

- [ ] Passé — date / appareil / version :

### M5 — Propagation d'une suppression d'alerte `PREMIUM` `2 APPAREILS`

**Conditions** : Alerte wantlist créée et synchronisée sur les 2 appareils.

**Étapes** :

1. Supprimer l'alerte sur l'appareil 1.

**Résultat attendu** : L'alerte disparaît aussi sur l'appareil 2.

- [ ] Passé — date / appareil / version :

### M6 — Premium activé après usage prolongé en gratuit `PREMIUM` `RÉGRESSION`

**Conditions** : Compte utilisé en gratuit avec des tags/sessions/préférences locales existantes, PUIS passage au premium.

**Étapes** :

1. Souscrire au premium alors que des données locales préexistent.
2. Vérifier dans un 2e appareil (ou après réinstallation) que ces données sont bien présentes.

**Résultat attendu** : Les données locales préexistantes sont poussées vers iCloud lors de l'activation du premium (régression « push initial jamais déclenché » corrigée — garde ` syncEngine != nil`dans`hydrateActiveZone()`).

- [ ] Passé — date / appareil / version :

### M7 — Option développeur « Forcer une nouvelle poussée initiale » `DEV` `PREMIUM`

**Conditions** : Compte potentiellement affecté par un ancien ` pushDoneKey`resté à`true` par erreur.

**Étapes** :

1. Options développeur → Forcer une nouvelle poussée initiale.

**Résultat attendu** : Resynchronisation complète déclenchée, toutes les données locales repoussées vers iCloud.

- [ ] Passé — date / appareil / version :

### M8 — Isolation des données entre comptes `PREMIUM` `2 APPAREILS`

**Conditions** : iCloud actif, changement de compte Discogs (voir A4).

**Étapes** :

1. Changer de compte Discogs sur un appareil avec iCloud actif.

**Résultat attendu** : Chaque compte Discogs a sa propre zone CloudKit (`account-<username>`) ; aucune fuite de données entre comptes.

- [ ] Passé — date / appareil / version :

### M9 — Arrêt de la synchro à la perte du premium `RÉGRESSION`

**Conditions** : Voir L8.

**Étapes** :

1. Perdre le statut premium.

**Résultat attendu** : Plus aucun appel CloudKit déclenché ; les données restent disponibles en local en lecture.

- [ ] Passé — date / appareil / version :

### M10 — Coupure réseau pendant une synchro `PREMIUM`

**Conditions** : Synchro en cours.

**Étapes** :

1. Activer le mode avion pendant une modification, puis le désactiver.

**Résultat attendu** : Reprise automatique de la synchro au retour du réseau, sans perte ni duplication de données.

- [ ] Passé — date / appareil / version :

### M11 — Poussée massive ne bloque pas l'interface au démarrage `RÉGRESSION` `LIMITE` `PREMIUM`

**Conditions** : Backlog important en attente (ex. 150+ enregistrements après une poussée initiale forcée).

**Étapes** :

1. Relancer l'app alors qu'un gros backlog reste à envoyer.
2. Observer la fluidité de l'interface pendant les premières ~20 secondes.

**Résultat attendu** : L'envoi se fait par lots de 25 enregistrements (pas 1 par 1) ; l'interface reste utilisable (scroll, navigation) pendant que le lot se vide en arrière-plan.

- [ ] Passé — date / appareil / version :

### M12 — App fermée en plein milieu du drainage de la file `LIMITE` `PREMIUM`

**Conditions** : Backlog partiellement envoyé, app forcée à quitter avant la fin.

**Étapes** :

1. Forcer la fermeture de l'app pendant l'envoi d'un lot.
2. Relancer l'app.

**Résultat attendu** : La synchro reprend au prochain lancement exactement où elle s'était arrêtée (état persisté par `CKSyncEngine`), sans doublon ni perte de changement.

- [ ] Passé — date / appareil / version :

### M13 — Quota iCloud dépassé pendant un envoi `LIMITE` `PREMIUM`

**Conditions** : Compte iCloud avec un espace de stockage saturé (ou simulé).

**Étapes** :

1. Déclencher un envoi de changements alors que le quota est dépassé.

**Résultat attendu** : Erreur définitive : l'envoi de cet enregistrement est abandonné (log « abandonné (erreur définitive) »), sans nouvel essai toutes les 5 s ni crash. La prochaine modification locale le renverra une fois de l'espace libéré ; aucune perte des données locales.

- [ ] Passé — date / appareil / version :

### M14 — Compte iCloud déconnecté en cours de synchro `LIMITE` `PREMIUM`

**Conditions** : Synchro en cours ; déconnexion du compte iCloud dans Réglages système pendant ce temps.

**Étapes** :

1. Déconnecter le compte iCloud de l'appareil pendant un envoi en cours.

**Résultat attendu** : L'évènement `accountChange` est capté : le moteur de synchro est recréé à neuf (ancien état effacé) et l'app conserve ses données locales, sans crash. À la reconnexion iCloud, la synchro reprend sans relancer l'app et repousse les données locales (voir M18).

- [ ] Passé — date / appareil / version :

### M15 — Déconnexion Discogs avec changements iCloud en attente `AUDIT` `RÉGRESSION` `PREMIUM` `2 APPAREILS`

**Conditions** : Compte A sur 2 appareils, synchro active.

**Étapes** :

1. Appareil 1 en mode avion : modifier les tags de plusieurs disques.
2. Se déconnecter du compte A, désactiver le mode avion, se connecter au compte B.
3. Attendre quelques minutes, observer l'appareil 2 (compte A).
4. Sur l'appareil 1, revenir au compte A.

**Résultat attendu** : Étape 3 : les tags du compte A sont intacts sur l'appareil 2 (jamais vidés). Étape 4 : les modifications faites hors ligne partent alors et apparaissent sur l'appareil 2.

- [ ] Passé — date / appareil / version :

### M16 — Préférences non mélangées entre comptes Discogs `AUDIT` `PREMIUM` `2 APPAREILS`

**Conditions** : Comptes A et B avec règles de rangement différentes.

**Étapes** :

1. Sur l'appareil 1, passer du compte A au compte B puis modifier une préférence.
2. Observer l'appareil 2 resté sur le compte A.

**Résultat attendu** : Les préférences du compte A sur l'appareil 2 ne changent pas.

- [ ] Passé — date / appareil / version :

### M17 — Modification simultanée du même disque `AUDIT` `PREMIUM` `2 APPAREILS` `LIMITE`

**Conditions** : Synchro active sur 2 appareils.

**Étapes** :

1. Mettre les deux appareils en mode avion.
2. Modifier différemment les tags du même disque sur chacun.
3. Rétablir le réseau sur les deux.

**Résultat attendu** : Les deux appareils convergent vers le même état en moins d'une minute ; pas d'erreurs répétées en boucle dans la console ; aucun autre disque affecté.

- [ ] Passé — date / appareil / version :

### M18 — Déconnexion puis reconnexion iCloud `AUDIT` `PREMIUM`

**Conditions** : Synchro active.

**Étapes** :

1. Réglages iOS : se déconnecter d'iCloud.
2. Se reconnecter au même compte iCloud, sans relancer l'app.
3. Modifier un tag.

**Résultat attendu** : La synchro reprend d'elle-même ; les données locales sont repoussées ; la modification apparaît sur un autre appareil du même compte.

- [ ] Passé — date / appareil / version :

### M19 — Changement de compte iCloud `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Deux identifiants Apple disponibles.

**Étapes** :

1. Se déconnecter d'iCloud et se connecter avec un autre identifiant Apple.
2. Ouvrir l'app.

**Résultat attendu** : Les données locales sont conservées et poussées vers le nouveau compte iCloud ; rien de l'ancien compte iCloud n'est mélangé ; pas de boucle d'erreurs.

- [ ] Passé — date / appareil / version :

### M20 — Pas d'enregistrements parasites dans CloudKit `AUDIT` `PREMIUM` `DEV`

**Conditions** : Accès au CloudKit Dashboard (environnement de développement).

**Étapes** :

1. Hors ligne, ajouter un disque et le taguer.
2. Rétablir le réseau et attendre la synchro.
3. Inspecter les enregistrements TagAssignment de la zone account-<username>.

**Résultat attendu** : Aucun enregistrement nommé « tags_- » (identifiant négatif temporaire) ; le tag est présent sous l'identifiant définitif de l'exemplaire.

- [ ] Passé — date / appareil / version :

### M21 — Première synchro d'un gros volume `AUDIT` `PREMIUM` `2 APPAREILS` `LIMITE`

**Conditions** : Appareil 1 avec 500+ disques tagués ; appareil 2 jamais synchronisé.

**Étapes** :

1. Activer la synchro sur l'appareil 2 et faire défiler la Collection pendant la réception.

**Résultat attendu** : Tous les tags arrivent ; l'interface reste fluide pendant la réception (pas de saccades à chaque lot reçu).

- [ ] Passé — date / appareil / version :

### M22 — Démo : aucune synchronisation iCloud `AUDIT` `PREMIUM`

**Conditions** : Compte iCloud connecté sur l'appareil, mode démo actif.

**Étapes** :

1. Ajouter des tags et des écoutes en démo.
2. Vérifier un second appareil connecté au même iCloud.

**Résultat attendu** : Aucune donnée de démo n'apparaît sur l'autre appareil ; aucune zone iCloud « spinfolio_demo » n'est créée.

- [ ] Passé — date / appareil / version :

### M23 — Conflit : la modification la plus récente l'emporte `AUDIT` `PREMIUM` `2 APPAREILS` `AUTO`

**Conditions** : Deux appareils synchronisés sur le même compte premium.

**Étapes** :

1. Appareil A en mode avion : modifier les tags d'un exemplaire.
2. Une minute plus tard, sur l'appareil B (en ligne) : modifier différemment les tags du même exemplaire.
3. Désactiver le mode avion sur A et attendre la synchro.

**Résultat attendu** : Les deux appareils affichent les tags saisis sur B (la modification la plus récente) ; la modification plus ancienne de A ne les écrase pas. Inversement, si A modifie après B, c'est la version de A qui reste.

- [ ] Passé — date / appareil / version :

### M24 — Couper puis réactiver la synchro iCloud `AUDIT` `PREMIUM` `2 APPAREILS`

**Conditions** : Compte premium connecté sur 2 appareils, synchro active.

**Étapes** :

1. Appareil A : Réglages → Synchronisation iCloud → couper l'interrupteur.
2. Sur A, ajouter un tag et une écoute ; sur B, ajouter un autre tag.
3. Attendre, relancer A : vérifier qu'aucun échange n'a lieu.
4. Sur A, réactiver l'interrupteur.

**Résultat attendu** : Pendant la coupure, A n'envoie ni ne reçoit rien et l'interrupteur reste coupé après relancement ; aucune donnée n'est effacée. À la réactivation, les modifications des deux appareils sont fusionnées : A récupère le tag de B, B reçoit le tag et l'écoute de A, sans doublon.

- [ ] Passé — date / appareil / version :

### M25 — Synchro iCloud sans Premium, puis au passage Premium `AUDIT` `PREMIUM` `AUTO`

**Conditions** : Compte sans abonnement.

**Étapes** :

1. Ouvrir Réglages → Synchronisation iCloud.
2. Toucher la carte.

**Résultat attendu** : Carte verrouillée « Synchronisation iCloud » à la place de l'interrupteur ; le toucher ouvre l'offre Premium. Après un abonnement, l'interrupteur apparaît, activé. Si la synchro avait été coupée à la main avant la perte du Premium, elle est réactivée automatiquement au réabonnement, et les modifications faites sans Premium sont fusionnées avec iCloud. À la perte du Premium, la synchro s'arrête.

- [ ] Passé — date / appareil / version :

### M26 — Achat Premium : la synchro iCloud démarre sans plantage `AUDIT`

**Conditions** : Compte sandbox ou TestFlight, connecté à Discogs, non Premium, connecté à iCloud (sur deux appareils si possible).

**Étapes** :

1. Ouvrir le paywall et s'abonner (idéalement avec une validation lente de l'achat).
2. Observer l'app pendant et juste après la validation, sans la quitter.
3. Fermer l'app et la rouvrir.
4. Sur un second appareil, activer le Premium et vérifier que les tags et écoutes se rejoignent.

**Résultat attendu** : Aucun plantage pendant ou après l'achat, ni au premier lancement suivant ; le statut Premium est actif tout de suite. La synchro iCloud démarre (tags, écoutes et préférences retrouvés sur l'autre appareil).

- [ ] Passé — date / appareil / version :

### M27 — Grades connus d'un seul appareil renvoyés sur iCloud `AUDIT` `AUTO`

**Conditions** : Deux appareils A et B, même compte iCloud et même compte Discogs Premium ; synchro iCloud activée.

**Étapes** :

1. Sur A, franchir un grade (ajouter un disque ou une écoute qui passe un palier).
2. Avant que B l'ait reçu, franchir sur B un autre grade (autre parcours).
3. Ramener chaque appareil au premier plan, attendre 1 min, puis ouvrir Réglages > Mes grades sur A et sur B.

**Résultat attendu** : Les deux appareils affichent les deux grades, chacun avec sa date d'origine. Aucun arrêt de l'app (build Debug comprise). Règle de fusion couverte par GradeRulesTests.

- [ ] Passé — date / appareil / version :

### M28 — Thème Premium conservé à la perte de l'abonnement `AUDIT` `AUTO`

**Conditions** : Deux appareils A et B, même compte ; abonnement sandbox ; thème Cobalt choisi sur A et reçu par B.

**Étapes** :

1. Laisser l'abonnement expirer (ou le résilier en sandbox) sur A.
2. Vérifier le thème de A, puis celui de B.
3. Se réabonner sur A.

**Résultat attendu** : 1 : A revient au thème Signature. 2 : B n'est pas basculé en Signature par A. 3 : A retrouve Cobalt sans le resélectionner. Règle d'affichage couverte par ThemeManagerTests.

- [ ] Passé — date / appareil / version :

### M29 — Première synchro sans réseau : pas de poussée qui écrase l'autre appareil `AUDIT`

**Conditions** : Appareil A déjà synchronisé avec des tags ; appareil B avec d'autres tags locaux, jamais synchronisé pour ce compte (ou option développeur « Forcer une nouvelle poussée initiale »).

**Étapes** :

1. Sur B, couper le réseau puis activer la synchro iCloud (ou devenir Premium).
2. Rétablir le réseau, fermer et relancer B.
3. Comparer les tags d'un même disque sur A et B après 1 min.

**Résultat attendu** : Les tags de A et de B sont fusionnés sur les deux appareils : rien n'est écrasé. La poussée initiale n'a lieu qu'après une récupération réussie.

- [ ] Passé — date / appareil / version :

### M30 — Suppression des données sur un appareil appliquée aux autres `AUDIT` `AUTO`

**Conditions** : Deux appareils A et B, même compte iCloud et même compte Discogs Premium ; tags, écoutes sur platine et alertes de prix déjà synchronisés.

**Étapes** :

1. Sur A : Réglages > Supprimer mes données, confirmer.
2. Ramener B au premier plan et attendre 1 min (ou relancer B).
3. Sur B, vérifier tags, écoutes, alertes de prix et grades ; puis ajouter un tag à un disque.
4. Variante : sur un iPhone, Réglages iOS > [nom] > iCloud > Gérer le stockage > Spinfolio > Supprimer les données, puis ouvrir l'app.

**Résultat attendu** : 2-3 : B a vidé tags, écoutes, alertes et préférences de collection de ce compte ; les grades sont recalculés d'après la collection ; le rangement, le thème et le cache Discogs sont conservés. Les données effacées ne réapparaissent ni sur B ni sur A ; le nouveau tag se synchronise normalement. 4 : même résultat. Règles couvertes par CloudSyncZoneDeletionTests.

- [ ] Passé — date / appareil / version :

### M31 — Première synchro de deux appareils divergents : tags, tags autonomes, rangement `AUDIT` `PREMIUM` `2 APPAREILS` `AUTO`

**Conditions** : Deux appareils A et B, même compte Discogs Premium, synchro iCloud coupée sur B. Sur A : tag « Jazz » sur un disque, tag autonome « Live », personnalisation de tri pour un artiste. Sur B (avant d'activer la synchro) : tag « Rare » sur le même disque, tag autonome « Soul », personnalisation pour un autre artiste.

**Étapes** :

1. Activer la synchro iCloud sur B.
2. Attendre la fin de la synchro, puis comparer A et B.
3. Sur A, supprimer le tag « Jazz » du disque ; attendre, puis regarder B.

**Résultat attendu** : 2 : A et B ont les tags « Jazz » et « Rare » sur le disque, les tags autonomes « Live » et « Soul », et les deux personnalisations de tri (si les deux appareils ont réglé le même artiste, c'est la valeur de A, déjà sur le serveur, qui l'emporte). 3 : la suppression se propage à B, qui garde « Rare » et ne ré-ajoute pas « Jazz ». Règles couvertes par CloudMergeRulesTests.

- [ ] Passé — date / appareil / version :

<a id="famille-n"></a>

## N — Mode hors ligne

> PREMIUM

### N1 — Téléchargement initial complet `PREMIUM`

**Conditions** : Compte premium, réseau disponible.

**Étapes** :

1. Réglages → Mode hors ligne → « Télécharger toute ma collection ».

**Résultat attendu** : Téléchargement de la collection et des pochettes haute résolution, barre de progression cohérente.

- [ ] Passé — date / appareil / version :

### N2 — Consultation hors ligne après téléchargement `PREMIUM`

**Conditions** : Téléchargement N1 terminé.

**Étapes** :

1. Activer le mode avion.
2. Parcourir Collection, fiches détail, prix.

**Résultat attendu** : Toutes les données et pochettes restent consultables sans réseau.

- [ ] Passé — date / appareil / version :

### N3 — Synchronisation manuelle `PREMIUM`

**Conditions** : Archive locale déjà présente.

**Étapes** :

1. « Synchroniser maintenant ».

**Résultat attendu** : Mise à jour incrémentale sans tout retélécharger.

- [ ] Passé — date / appareil / version :

### N4 — Actualisation automatique `PREMIUM`

**Conditions** : Modification de la collection faite sur Discogs.com.

**Étapes** :

1. Rouvrir l'app après un délai raisonnable.

**Résultat attendu** : L'auto-sync se déclenche et reflète les changements faits sur Discogs.com.

- [ ] Passé — date / appareil / version :

### N5 — Vider le cache d'images `PREMIUM`

**Conditions** : Pochettes en cache.

**Étapes** :

1. Réglages → Mode hors ligne → Vider le cache d'images.

**Résultat attendu** : Espace de stockage libéré, confirmation affichée, pochettes rechargées à la demande ensuite.

- [ ] Passé — date / appareil / version :

### N6 — Affichage de l'espace de stockage `PREMIUM`

**Conditions** : Archive locale présente.

**Étapes** :

1. Observer la section Espace de stockage.

**Résultat attendu** : Taille affichée cohérente avec le volume réellement téléchargé.

- [ ] Passé — date / appareil / version :

### N7 — Option grisée — non premium `PREMIUM`

**Conditions** : Compte non premium.

**Étapes** :

1. Réglages → Mode hors ligne.

**Résultat attendu** : Option verrouillée / renvoi vers la paywall, aucun téléchargement possible.

- [ ] Passé — date / appareil / version :

### N8 — Perte du premium pendant mode hors ligne actif `RÉGRESSION`

**Conditions** : Voir L8, avec mode hors ligne actif.

**Étapes** :

1. Perdre le statut premium.

**Résultat attendu** : L'auto-sync hors ligne s'arrête (`OfflineDownloadManager.autoSyncIfNeeded` gate) ; l'archive déjà téléchargée reste consultable en lecture.

- [ ] Passé — date / appareil / version :

### N9 — Stockage de l'appareil plein pendant le téléchargement `LIMITE` `PREMIUM`

**Conditions** : Appareil avec très peu d'espace disponible.

**Étapes** :

1. Lancer le téléchargement complet dans ces conditions.

**Résultat attendu** : Erreur claire dès que l'espace est insuffisant ; pas de téléchargement partiel silencieusement corrompu.

- [ ] Passé — date / appareil / version :

### N10 — App mise en arrière-plan pendant le téléchargement `LIMITE` `PREMIUM`

**Conditions** : Téléchargement complet en cours.

**Étapes** :

1. Mettre l'app en arrière-plan (bouton Accueil) pendant le téléchargement.

**Résultat attendu** : Reprise propre au retour au premier plan, ou reprise à la prochaine ouverture si le système a coupé la tâche — jamais un état « à moitié téléchargé » signalé comme complet.

- [ ] Passé — date / appareil / version :

### N11 — Archive locale périmée `LIMITE` `PREMIUM`

**Conditions** : Dernière synchronisation hors ligne très ancienne (plusieurs semaines).

**Étapes** :

1. Consulter la collection hors ligne avec une archive très ancienne.

**Résultat attendu** : Bannière/indication claire que les données peuvent être obsolètes (voir `OfflineBannerView`), pas présenté comme à jour.

- [ ] Passé — date / appareil / version :

### N12 — Ajout hors ligne puis retrait avant synchro `AUDIT` `RÉGRESSION`

**Conditions** : Mode avion, cache récent.

**Étapes** :

1. Ajouter un disque à la collection.
2. Le retirer (fiche ou liste).
3. Rétablir le réseau.

**Résultat attendu** : Le disque n'apparaît jamais sur discogs.com ; aucun message d'erreur de synchronisation.

- [ ] Passé — date / appareil / version :

### N13 — Ajout hors ligne puis déplacement avant synchro `AUDIT`

**Conditions** : Mode avion, plusieurs dossiers.

**Étapes** :

1. Ajouter un disque (dossier X).
2. Le déplacer vers le dossier Y.
3. Rétablir le réseau.

**Résultat attendu** : Le disque est ajouté directement dans le dossier Y sur discogs.com ; aucun message d'erreur.

- [ ] Passé — date / appareil / version :

### N14 — Tags d'un disque ajouté hors ligne `AUDIT` `RÉGRESSION`

**Conditions** : Mode avion.

**Étapes** :

1. Ajouter un disque et lui appliquer deux tags.
2. Rétablir le réseau, attendre la synchro, puis rafraîchir la collection.

**Résultat attendu** : Le disque apparaît avec ses deux tags après le rafraîchissement (ils ne sont plus perdus à la synchro).

- [ ] Passé — date / appareil / version :

### N15 — File hors ligne et changement de compte `AUDIT` `RÉGRESSION` `AUTO`

**Conditions** : Comptes A et B ; mode avion.

**Étapes** :

1. Avec le compte A, ajouter un disque et en retirer un autre.
2. Se déconnecter, se connecter au compte B, rétablir le réseau.
3. Plus tard, se reconnecter au compte A.

**Résultat attendu** : Étape 2 : rien n'est appliqué au compte B. Étape 3 : les deux actions sont appliquées au compte A.

- [ ] Passé — date / appareil / version :

### N16 — Pas de faux « hors ligne » au lancement `AUDIT`

**Conditions** : Réseau disponible, app fermée.

**Étapes** :

1. Lancer l'app et observer les premières secondes.

**Résultat attendu** : Aucun bandeau hors ligne furtif ; la collection se rafraîchit depuis Discogs dès le lancement.

- [ ] Passé — date / appareil / version :

### N17 — Synchro auto sur Wi-Fi uniquement `PREMIUM`

**Conditions** : Synchro automatique Wi-Fi activée, dernière synchro de plus de 6 h.

**Étapes** :

1. Ouvrir l'app en données cellulaires (Wi-Fi coupé).
2. Passer en Wi-Fi et revenir au premier plan.

**Résultat attendu** : Aucun téléchargement automatique en cellulaire ni en Mode données réduites ; il démarre en Wi-Fi.

- [ ] Passé — date / appareil / version :

### N18 — Téléchargement hors ligne et wantlist modifiée ailleurs `AUDIT` `PREMIUM`

**Conditions** : Archive hors ligne présente ; un élément retiré de la wantlist sur discogs.com depuis.

**Étapes** :

1. Relancer « Télécharger toute ma collection ».
2. Passer en mode avion et ouvrir la Wantlist.

**Résultat attendu** : L'élément retiré ailleurs n'apparaît plus hors ligne.

- [ ] Passé — date / appareil / version :

### N19 — File hors ligne : coupure prolongée sans perte `AUDIT` `RÉGRESSION` `AUTO`

**Conditions** : Compte connecté.

**Étapes** :

1. En mode avion, ajouter un disque et en retirer un autre.
2. Attendre plusieurs minutes, réseau toujours coupé.
3. Rétablir le réseau.

**Résultat attendu** : Les deux actions arrivent sur Discogs dans l'ordre. Avant correction, une coupure de quelques secondes suffisait à les abandonner (« Échec définitif de synchronisation »).

- [ ] Passé — date / appareil / version :

### N20 — File hors ligne : reprise au retour au premier plan `AUDIT`

**Conditions** : Une action en attente (Discogs indisponible ou réseau instable).

**Étapes** :

1. Mettre l'app en arrière-plan, rétablir le réseau.
2. Ramener l'app au premier plan.

**Résultat attendu** : L'action en attente part dès le retour au premier plan.

- [ ] Passé — date / appareil / version :

### N21 — Pas de doublon quand un ajout est rejoué `AUDIT` `LIMITE` `AUTO`

**Conditions** : Network Link Conditioner avec une forte latence (ou couper le réseau juste après avoir touché « Collection »).

**Étapes** :

1. Ajouter un disque à la collection pendant que la réponse de Discogs n'arrive pas (message « Discogs ne répond pas »).
2. Rétablir le réseau et laisser la file se vider.
3. Ajouter volontairement deux exemplaires d'un autre disque hors ligne, puis revenir en ligne.

**Résultat attendu** : Premier disque : un seul exemplaire sur discogs.com, même si le premier envoi avait abouti. Second disque : bien deux exemplaires.

- [ ] Passé — date / appareil / version :

### N22 — Ajout ou retrait hors ligne annoncé `AUDIT`

**Conditions** : Mode avion, données de moins de 6 h.

**Étapes** :

1. Depuis une fiche release : ajouter à la collection, puis à la wantlist.
2. Retirer un disque de la Collection (balayage) et de la Wantlist.
3. Wantlist → déplacer un disque vers la collection.

**Résultat attendu** : Chaque action affiche sa bulle habituelle (« Ajouté à la collection », « Supprimé de la wantlist »…) avec une deuxième ligne « Hors ligne : synchronisé au retour du réseau », qui disparaît seule — plus d'alerte à fermer. Un retrait par balayage affiche aussi cette bulle. Les actions partent bien à la reconnexion.

- [ ] Passé — date / appareil / version :

### N23 — Cote de plus de 6 h datée hors ligne `AUDIT` `PREMIUM` `AUTO`

**Conditions** : Compte premium, exemplaire avec prix d'achat renseigné.

**Étapes** :

1. En ligne, ouvrir la fiche du disque (la cote se charge), puis la feuille d'édition de l'exemplaire.
2. Attendre plus de 6 h (ou avancer l'heure de l'iPhone de 7 h), activer le mode avion.
3. Rouvrir la fiche (section « Mon exemplaire ») et la feuille d'édition.
4. Désactiver le mode avion et rouvrir la fiche.

**Résultat attendu** : Étape 3 : à côté de la plus-value, « Cote du <date> » ; dans la feuille, le libellé « Cote actuelle » devient « Cote du <date> » (en anglais : « Value as of <date> »). Étape 4 : la cote est rechargée et la date disparaît. En ligne ou hors ligne avec une cote de moins de 6 h : aucune date affichée.

- [ ] Passé — date / appareil / version :

### N24 — Pochettes : au plus 7 jours après le téléchargement `AUDIT` `PREMIUM` `LIMITE`

**Conditions** : Compte premium, collection téléchargée en mode hors ligne, synchro automatique en Wi-Fi désactivée.

**Étapes** :

1. Télécharger la collection, consulter régulièrement quelques pochettes pendant la semaine.
2. Avancer la date de l'iPhone de plus de 7 jours, fermer puis relancer l'app.
3. Passer en mode avion et ouvrir la collection.
4. Rétablir le réseau (ou « Synchroniser maintenant ») et ré-ouvrir la collection.

**Résultat attendu** : Au bout de 7 jours après le téléchargement, même pour les pochettes consultées entre-temps, les pochettes ne sont plus affichées hors ligne (les albums et leurs informations restent). Elles reviennent après une nouvelle synchronisation. Avant correction, la consultation prolongeait leur durée de conservation. Réglages → Mode hors ligne : la taille du cache d'images retombe, et le texte sous « Pochettes en cache » annonce « 7 jours au plus après leur téléchargement » (en anglais : « up to 7 days after download »).

- [ ] Passé — date / appareil / version :

### N25 — Page Mode Hors Ligne : transitions de la synchronisation `AUDIT`

**Conditions** : Compte Premium Discogs connecté (hors démo), Wi-Fi ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Ouvrir Réglages > Données hors ligne > Mode Hors Ligne et lancer la synchronisation.
2. Observer le bouton, la barre de progression et le pourcentage jusqu'à la fin.
3. Vider le cache d'images et observer la taille affichée.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : Au lancement, le bouton de synchro laisse la place au bloc de progression en fondu ; le pourcentage et la barre avancent en douceur (chiffres qui roulent) ; le nombre de disques archivés et la taille du cache changent de la même façon. À la fin d'une synchro réussie, l'icône de la carte « Archive locale » rebondit avec un léger retour haptique de succès. Avec Réduire les animations : tout change sans mouvement.

- [ ] Passé — date / appareil / version :

### N26 — Mode Hors Ligne : date de synchro et disques archivés propres à chaque compte `AUDIT` `AUTO`

**Conditions** : Deux comptes Premium A et B ; Wi-Fi ; « Synchro auto en Wi-Fi » activée ; mise à jour depuis une version précédente où A avait déjà synchronisé.

**Étapes** :

1. Après la mise à jour, ouvrir Réglages > Mode Hors Ligne avec A.
2. Se déconnecter, se connecter avec B, ouvrir Mode Hors Ligne et Réglages ; attendre la synchro auto.
3. Se reconnecter avec A.
4. Lancer une synchro et toucher Annuler pendant le téléchargement des pochettes.
5. Entrer en démo, synchroniser, quitter la démo et y revenir.

**Résultat attendu** : 1 : A retrouve sa date et son nombre de disques d'avant la mise à jour. 2 : B voit « Aucune synchronisation effectuée » (pas la date ni le compteur de A), et sa synchro auto en Wi-Fi démarre. 3 : A retrouve ses propres valeurs. 4 : une synchro annulée n'est pas enregistrée comme terminée (date inchangée). 5 : à la nouvelle démo, aucune date de la démo précédente. Les bannières hors ligne de Collection, Wantlist et Artiste montrent les valeurs du compte connecté (règles couvertes par OfflineSyncRecordStoreTests).

- [ ] Passé — date / appareil / version :

### N27 — Action hors ligne refusée par Discogs : alerte et liste corrigée `AUDIT` `AUTO`

**Conditions** : Compte réel ; un disque de la collection que tu peux supprimer sur discogs.com depuis un ordinateur.

**Étapes** :

1. Couper le réseau, changer le dossier de ce disque dans l'app (l'action part en file).
2. Sur discogs.com, supprimer ce disque de la collection.
3. Rétablir le réseau dans l'app et attendre l'envoi (jusqu'à 3 essais).

**Résultat attendu** : Une alerte « Échec définitif de synchronisation : Changement de dossier… » s'affiche, quel que soit l'onglet, et reste jusqu'à OK. La Collection se recharge et ne montre plus le disque dans le dossier choisi hors ligne. Plusieurs échecs avant OK : listés ligne par ligne (règle couverte par AccountLeftoversTests).

- [ ] Passé — date / appareil / version :

### N28 — Note et prix d'achat hors ligne : gardés et envoyés au retour du réseau `AUDIT`

**Conditions** : Compte réel, un disque de la collection avec un champ « prix d'achat » configuré ; mode avion.

**Étapes** :

1. En mode avion, ouvrir la fiche du disque, changer sa note (étoiles) puis son prix d'achat.
2. Fermer et rouvrir la fiche.
3. Couper le mode avion et attendre l'envoi, puis vérifier sur discogs.com.

**Résultat attendu** : 1-2 : la note et le prix restent affichés (plus de message d'échec, plus de retour à l'ancienne valeur). 3 : les deux valeurs arrivent sur Discogs. Un refus définitif de Discogs déclenche l'alerte « Échec définitif de synchronisation ».

- [ ] Passé — date / appareil / version :

### N29 — Quota Discogs dépassé : la file et les tâches de fond se mettent en pause `AUDIT` `AUTO`

**Conditions** : Compte réel avec beaucoup d'artistes ; plusieurs modifications hors ligne en attente ; provoquer un dépassement du quota (scan par lot de 20 disques ou plus d'affilée).

**Étapes** :

1. Rétablir le réseau pendant que le quota est dépassé.
2. Observer la Collection et la page d'un artiste pendant 1 minute.
3. Exporter la collection en CSV juste après une synchro complète.

**Résultat attendu** : 1-2 : l'app reste fluide, les modifications en attente repartent plus tard (après 30 s, puis espacées), le classement des œuvres et les années originales reprennent à la prochaine ouverture au lieu de continuer à échouer. 3 : l'export utilise le cache à jour sans relancer une lecture complète. Règles du limiteur et des erreurs réseau couvertes par DiscogsRateLimiterTests.

- [ ] Passé — date / appareil / version :

<a id="famille-o"></a>

## O — Widgets & Live Activity

### O1 — Ajout du widget « Album aléatoire »

**Conditions** : App installée.

**Étapes** :

1. Ajouter le widget sur l'écran d'accueil.

**Résultat attendu** : Le widget s'affiche avec une pochette aléatoire de la collection.

- [ ] Passé — date / appareil / version :

### O2 — Widget reflète le statut premium

**Conditions** : Basculer premium / non premium.

**Étapes** :

1. Observer le widget après un changement de statut premium.

**Résultat attendu** : Le widget adapte son affichage (verrouillé/débloqué) selon le statut premium réel, après rechargement.

- [ ] Passé — date / appareil / version :

### O3 — Rafraîchissement après changement de collection

**Conditions** : Widget installé.

**Étapes** :

1. Ajouter un album à la collection.

**Résultat attendu** : Le widget se met à jour avec un nouveau tirage incluant potentiellement le nouvel album.

- [ ] Passé — date / appareil / version :

### O4 — Live Activity « Écoute en cours sur la platine »

**Conditions** : Fonction de suivi d'écoute déclenchée.

**Étapes** :

1. Démarrer une écoute sur platine (« J'écoute »).
2. Observer l'île dynamique / écran verrouillé.
3. Terminer la session.

**Résultat attendu** : La Live Activity démarre, se met à jour en temps réel et se termine correctement (affiche « Écoute en cours sur la platine » et respecte le réglage « Arrêt automatique de l'écoute »).

- [ ] Passé — date / appareil / version :

### O5 — Option développeur « Recharger les widgets » `DEV`

**Conditions** : Build Debug.

**Étapes** :

1. Options développeur → Recharger les widgets.

**Résultat attendu** : Les widgets affichent immédiatement les données à jour sans attendre le cycle système.

- [ ] Passé — date / appareil / version :

### O6 — Widget ajouté avant toute connexion `LIMITE`

**Conditions** : App jamais ouverte/connectée, widget ajouté directement depuis l'écran d'accueil.

**Étapes** :

1. Ajouter le widget sans s'être jamais connecté à Discogs.

**Résultat attendu** : État neutre affiché (pas de pochette, message d'invite), pas de crash de l'extension widget.

- [ ] Passé — date / appareil / version :

### O7 — Live Activity écartée puis une nouvelle déclenchée `LIMITE`

**Conditions** : Live Activity active.

**Étapes** :

1. Écarter manuellement la Live Activity depuis l'écran verrouillé.
2. Déclencher une nouvelle session d'écoute juste après.

**Résultat attendu** : La nouvelle Live Activity démarre proprement sans conflit avec l'ancienne instance écartée.

- [ ] Passé — date / appareil / version :

### O8 — Plusieurs widgets identiques ajoutés `LIMITE`

**Conditions** : Deux widgets « Album aléatoire » ajoutés sur le même écran d'accueil.

**Étapes** :

1. Observer les deux instances.

**Résultat attendu** : Chaque instance se comporte indépendamment (pas de donnée partagée incohérente entre les deux).

- [ ] Passé — date / appareil / version :

### O9 — Widget avec réseau lent ou absent `AUDIT` `LIMITE`

**Conditions** : Network Link Conditioner « Very Bad Network » ou mode avion.

**Étapes** :

1. Forcer un rechargement du widget (Options développeur ou changement de jour).

**Résultat attendu** : Le widget s'affiche en moins de 10 s, avec pochette si elle a pu être téléchargée, sinon sans ; jamais de widget vide ou figé.

- [ ] Passé — date / appareil / version :

### O10 — Album du jour après la mise à jour `AUDIT`

**Conditions** : Mise à jour depuis la version précédente.

**Étapes** :

1. Observer le widget juste après la mise à jour puis au fil de la journée.

**Résultat attendu** : L'album du jour peut changer UNE fois juste après la mise à jour (nouveau calcul du tirage) ; il reste ensuite stable toute la journée et identique entre plusieurs widgets.

- [ ] Passé — date / appareil / version :

### O11 — Fin d'écoute depuis l'écran verrouillé `AUDIT` `RÉGRESSION`

**Conditions** : Session d'écoute (Live Activity) active, app ouverte en arrière-plan.

**Étapes** :

1. Terminer la session depuis la Live Activity (écran verrouillé ou Dynamic Island).
2. Revenir dans l'app.

**Résultat attendu** : Le mini-lecteur de la session a disparu et les pastilles « Écoute en cours » des fiches sont revenues à l'état normal.

- [ ] Passé — date / appareil / version :

### O12 — Ouverture d'un disque depuis le widget

**Conditions** : Widget « Album aléatoire » affichant un disque.

**Étapes** :

1. Toucher le widget, app fermée puis app en arrière-plan.

**Résultat attendu** : L'app s'ouvre directement sur la fiche du disque affiché.

- [ ] Passé — date / appareil / version :

### O13 — Déconnexion vide le widget

**Conditions** : Widget affichant un disque.

**Étapes** :

1. Se déconnecter de Discogs dans l'app.

**Résultat attendu** : Le widget n'affiche plus de disque du compte déconnecté (état vide ou invitation à se connecter).

- [ ] Passé — date / appareil / version :

### O14 — Live Activity terminée alors que l'app est suspendue `AUDIT`

**Conditions** : Durée maximale d'écoute réglée sur 30 minutes.

**Étapes** :

1. Lancer une écoute, verrouiller l'iPhone sans rouvrir l'app.
2. Regarder l'écran verrouillé après 30 minutes.

**Résultat attendu** : La Live Activity passe en « Écoute terminée » (grisée) ou disparaît ; elle n'affiche plus « Écoute en cours » pendant des heures.

- [ ] Passé — date / appareil / version :

### O15 — Widget après changement d'identifiant `AUDIT` `DEV`

**Conditions** : Installation par-dessus une version au widget d'ancien identifiant.

**Étapes** :

1. Installer la nouvelle version.
2. Réajouter le widget « Album du jour ».

**Résultat attendu** : L'ancien widget peut disparaître (identifiant changé) ; le nouveau s'ajoute et affiche un disque.

- [ ] Passé — date / appareil / version :

### O16 — Widget accessible sans Premium `AUDIT`

**Conditions** : Compte non premium avec une collection.

**Étapes** :

1. Ajouter le widget « Album du jour ».

**Résultat attendu** : Le widget affiche un disque de la collection ; aucun écran « Fonctionnalité premium ».

- [ ] Passé — date / appareil / version :

### O17 — Live Activity aux couleurs du thème `AUDIT`

**Conditions** : Thème de couleur autre que Signature (ex. Vert Émeraude).

**Étapes** :

1. Lancer une écoute sur platine.
2. Observer l'écran verrouillé et la Dynamic Island.
3. Changer de thème, lancer une nouvelle écoute.

**Résultat attendu** : Macaron du vinyle, libellé et contour de la Dynamic Island suivent le thème choisi (plus le rose fixe).

- [ ] Passé — date / appareil / version :

### O18 — Widget : aperçu de la galerie et premier lancement `AUDIT`

**Conditions** : App installée mais jamais ouverte (ou App Group vide).

**Étapes** :

1. Ajouter le widget « Album du jour » depuis la galerie.
2. Observer le widget posé avant d'ouvrir l'app.

**Résultat attendu** : Galerie : aperçu avec une pochette d'exemple (Kind of Blue). Widget posé : « Ouvre Spinfolio » au lieu d'un message technique ; une fois l'app ouverte, un disque de la collection apparaît.

- [ ] Passé — date / appareil / version :

### O19 — Lien profond sans perte de la recherche `AUDIT`

**Conditions** : Une recherche en cours dans l'onglet Recherche, Collection affichée.

**Étapes** :

1. Toucher le widget « Album du jour » (ou la Live Activity).
2. Revenir à l'onglet Recherche.

**Résultat attendu** : La fiche s'ouvre sur l'onglet courant (Collection si on était dans Réglages) ; la recherche en cours et ses résultats sont toujours là.

- [ ] Passé — date / appareil / version :

### O20 — Siri : un disque au hasard `AUDIT`

**Conditions** : Compte connecté, collection déjà ouverte au moins une fois dans l'app.

**Étapes** :

1. Dire « Dis Siri, un disque au hasard avec Spinfolio » (en anglais : « Pick a random record with Spinfolio »).
2. Recommencer depuis Spotlight (taper « disque au hasard ») et depuis l'app Raccourcis.

**Résultat attendu** : L'app s'ouvre sur la fiche d'un disque de la collection tiré au sort, et Siri annonce son titre et son artiste. Collection jamais chargée : message « Aucun disque disponible… ».

- [ ] Passé — date / appareil / version :

### O21 — Siri : démarrer une écoute `AUDIT` `LIMITE`

**Conditions** : Compte connecté, app fermée (balayée).

**Étapes** :

1. Dire « Dis Siri, démarre une écoute dans Spinfolio ».
2. Répondre au « Quel disque écoutes-tu ? » par un titre ou un artiste de la collection (ex. « Kind of Blue »), puis choisir parmi les propositions si plusieurs disques correspondent.
3. Rouvrir l'app.

**Résultat attendu** : La Live Activity démarre sans ouvrir l'app, avec la pochette ; l'écoute apparaît dans l'historique (Stats → écoutes sur platine) et dans le mini-lecteur à l'ouverture. Déconnecté : message invitant à se connecter.

- [ ] Passé — date / appareil / version :

### O22 — Siri : arrêter l'écoute `AUDIT`

**Conditions** : Une écoute sur platine en cours (Live Activity affichée), app fermée.

**Étapes** :

1. Dire « Dis Siri, arrête l'écoute dans Spinfolio ».
2. Redire la phrase alors qu'aucune écoute n'est en cours.

**Résultat attendu** : La Live Activity disparaît et Siri confirme « Écoute arrêtée » ; la seconde fois, « Aucune écoute en cours ».

- [ ] Passé — date / appareil / version :

### O23 — Widget « Album du jour » aux couleurs du thème `AUDIT`

**Conditions** : Widget posé sur l'écran d'accueil, thème autre que Signature.

**Étapes** :

1. Changer de thème dans l'app.
2. Revenir à l'écran d'accueil (avec une pochette claire puis sombre si possible).

**Résultat attendu** : La mention « ALBUM DU JOUR » et les icônes du widget prennent la couleur du thème dès le retour à l'accueil (teinte foncée sur pochette claire) ; plus de rose fixe.

- [ ] Passé — date / appareil / version :

### O24 — Bouton Stop de la Live Activity toujours actif ; lien externe sans effet `AUDIT` `AUTO`

**Conditions** : Une écoute sur platine en cours avec sa Live Activity ; une note ou une page web contenant le lien spinlog://end-session/123 (et spinlog://end-session).

**Étapes** :

1. Toucher le lien dans la note ou la page web.
2. Toucher Stop sur la Live Activity (écran verrouillé et Dynamic Island).

**Résultat attendu** : 1 : l'app s'ouvre mais l'écoute continue. 2 : l'écoute s'arrête comme avant. Une Live Activity démarrée avant la mise à jour s'arrête aussi avec son bouton. Couvert par SecurityHardeningTests.

- [ ] Passé — date / appareil / version :

<a id="famille-p"></a>

## P — Cas transverses / non-fonctionnel

### P1 — iPad vs iPhone

**Conditions** : Un iPad et un iPhone (ou simulateurs équivalents).

**Étapes** :

1. Ouvrir la paywall et les feuilles principales sur les deux formats.

**Résultat attendu** : Mise en page correcte sur iPad (pas de sheet tronquée), identique en substance à l'iPhone.

- [ ] Passé — date / appareil / version :

### P2 — Mode sombre / mode clair

**Conditions** : Écrans modifiés cette session : filtres, barre d'action groupée Liquid Glass, paywall, mini-lecteur.

**Étapes** :

1. Basculer entre mode clair et sombre sur chaque écran.

**Résultat attendu** : Contrastes et lisibilité corrects dans les deux modes, pas d'élément invisible.

- [ ] Passé — date / appareil / version :

### P3 — VoiceOver sur les boutons icône seule

**Conditions** : VoiceOver activé.

**Étapes** :

1. Naviguer au doigt sur les boutons de sélection, filtres, alertes wantlist, lecture Apple Music.

**Résultat attendu** : Chaque bouton annonce un libellé clair et pertinent (` accessibilityLabel`).

- [ ] Passé — date / appareil / version :

### P4 — Dynamic Type (texte agrandi)

**Conditions** : Taille de texte système au maximum.

**Étapes** :

1. Parcourir Collection, Wantlist, paywall, mini-lecteur.

**Résultat attendu** : Aucun texte tronqué de façon illisible, mise en page qui s'adapte raisonnablement.

- [ ] Passé — date / appareil / version :

### P5 — Changements de filtres répétés et rapides

**Conditions** : Collection avec plusieurs tags.

**Étapes** :

1. Appliquer puis retirer des filtres très rapidement, plusieurs fois de suite.

**Résultat attendu** : Pas de crash, pas de barre de recherche décrochée, pas de ralentissement visible.

- [ ] Passé — date / appareil / version :

### P6 — Suppression puis réinstallation de l'app

**Conditions** : App installée avec données locales.

**Étapes** :

1. Supprimer l'app.
2. Réinstaller et se reconnecter.

**Résultat attendu** : Les données locales sont perdues comme attendu, mais tout revient via Discogs (collection/wantlist) et iCloud (tags/préférences/alertes) si premium. Le Keychain survivant à la suppression de l'app, il est normal qu'elle redémarre déjà connectée : la collection doit alors se recharger entièrement, sans état incohérent (connecté sans nom d'utilisateur, listes vides bloquées).

- [ ] Passé — date / appareil / version :

### P7 — Date/heure système modifiée manuellement

**Conditions** : Alertes wantlist actives.

**Étapes** :

1. Modifier manuellement la date de l'appareil (avance ou retard important).

**Résultat attendu** : Aucun comportement erratique sur les vérifications planifiées ou les notifications déjà programmées.

- [ ] Passé — date / appareil / version :

### P8 — Barre de défilement système masquée sur les listes à index `RÉGRESSION`

**Conditions** : Collection et Wantlist en affichage Liste avec `SectionIndexBar` visible.

**Étapes** :

1. Filtrer la liste pour qu'elle tienne presque entièrement à l'écran.

**Résultat attendu** : Plus de longue barre grise native superposée à la barre de navigation rapide personnalisée (voir aussi B18).

- [ ] Passé — date / appareil / version :

### P9 — Batterie faible / Réduire les animations `LIMITE`

**Conditions** : Mode Batterie faible activé, ou « Réduire les animations » activé dans Accessibilité.

**Étapes** :

1. Parcourir les écrans avec animations (sélection, carrousel, paywall, mini-lecteur).

**Résultat attendu** : Les animations se simplifient/ralentissent sans casser l'affichage ni bloquer une interaction.

- [ ] Passé — date / appareil / version :

### P10 — Réseau très lent (Edge/3G simulé) `LIMITE`

**Conditions** : Simulateur de réseau Xcode réglé sur « Edge » ou équivalent très lent.

**Étapes** :

1. Parcourir les écrans chargeant des images et des données (Collection, fiche détail, recherche Apple Music).

**Résultat attendu** : Affichage progressif avec indicateurs de chargement, pas de blocage total de l'interface en attendant le réseau.

- [ ] Passé — date / appareil / version :

### P11 — Stockage de l'appareil presque plein au lancement `LIMITE`

**Conditions** : Appareil avec très peu d'espace disque libre.

**Étapes** :

1. Lancer l'app dans ces conditions.

**Résultat attendu** : L'app démarre et fonctionne en mode dégradé si besoin (ex. cache désactivé), sans crash au lancement.

- [ ] Passé — date / appareil / version :

### P12 — Défilement dans Collection/Wantlist sans lecture en cours `RÉGRESSION`

**Conditions** : Aucune lecture Apple Music ni session d'écoute manuelle active.

**Étapes** :

1. Faire défiler rapidement la liste Collection ou Wantlist.

**Résultat attendu** : Défilement fluide, sans saccade — le mini-lecteur ne doit monter son ` safeAreaInset` que lorsqu'une lecture est réellement active (régression corrigée).

- [ ] Passé — date / appareil / version :

### P13 — En-têtes Discogs envoyés uniquement à Discogs `AUDIT` `DEV`

**Conditions** : Proxy HTTP (Proxyman/Charles) avec certificat installé ; lecture Apple Music avec pochettes d'artistes (Stats).

**Étapes** :

1. Parcourir Collection, Stats (vignettes artistes), fiches.
2. Inspecter les requêtes d'images.

**Résultat attendu** : L'en-tête « Authorization: OAuth… » et le User-Agent Spinlog ne sont envoyés qu'aux hôtes discogs.com ; jamais à mzstatic.com ou à d'autres hôtes.

- [ ] Passé — date / appareil / version :

### P14 — iPad en Split View / Stage Manager `LIMITE`

**Conditions** : iPad.

**Étapes** :

1. Utiliser l'app en Split View 1/3, 1/2, puis redimensionner en Stage Manager.

**Résultat attendu** : Mise en page adaptée à chaque largeur ; feuilles, mini-lecteur et barre d'actions restent utilisables.

- [ ] Passé — date / appareil / version :

### P15 — Formats régionaux `LIMITE`

**Conditions** : Région iOS réglée successivement sur France, États-Unis, Royaume-Uni.

**Étapes** :

1. Saisir des prix d'achat (« 25,50 € », « $1,234.56 »).
2. Consulter Stats et la fiche détail.

**Résultat attendu** : Prix interprétés correctement quel que soit le format régional ; montants affichés avec le format de la région.

- [ ] Passé — date / appareil / version :

### P16 — Journaux de production sans données personnelles `AUDIT` `DEV`

**Conditions** : Console.app connectée à l'iPhone, build Release (TestFlight).

**Étapes** :

1. Ouvrir l'onglet Recherche plusieurs fois et filtrer la console sur l'app.

**Résultat attendu** : Les journaux indiquent des nombres (« REFRESH collection=… wantlist=… ») et non la liste des identifiants de la wantlist ; aucun token n'apparaît.

- [ ] Passé — date / appareil / version :

### P17 — VoiceOver : barres d'index A-Z `AUDIT`

**Conditions** : VoiceOver activé, Collection triée par artiste (Liste/Mosaïque) puis Carrousel.

**Étapes** :

1. Placer le curseur VoiceOver sur la barre d'index.
2. Balayer vers le haut et vers le bas.

**Résultat attendu** : VoiceOver annonce « Index des sections » et la section courante ; chaque balayage passe à la section suivante/précédente et la liste suit.

- [ ] Passé — date / appareil / version :

### P18 — VoiceOver : mode sélection `AUDIT`

**Conditions** : VoiceOver activé, mode sélection ouvert (Liste, Mosaïque, Carrousel).

**Étapes** :

1. Parcourir les disques et toucher deux fois.

**Résultat attendu** : Chaque disque est annoncé comme bouton avec son état « sélectionné » ; le double-tap coche/décoche sans ouvrir la fiche.

- [ ] Passé — date / appareil / version :

### P19 — iOS 26 : appui long à la place du balayage `AUDIT` `LIMITE`

**Conditions** : Appareil sous iOS 26.1.

**Étapes** :

1. Ouvrir Gestion des tags, Gestion des dossiers, l'éditeur de tags et « Mes exemplaires ».
2. Lire les textes d'aide, utiliser l'appui long.

**Résultat attendu** : Les textes disent « Maintiens le doigt… » (pas « Glisse vers la gauche ») et l'appui long propose les mêmes actions que le balayage d'iOS 27.

- [ ] Passé — date / appareil / version :

### P20 — Soumission : validation de l'archive `AUDIT` `DEV`

**Conditions** : Archive Release.

**Étapes** :

1. Archiver puis valider dans Xcode / App Store Connect.

**Résultat attendu** : Validation sans alerte sur les manifestes de confidentialité (app et widget) ; aucune question sur le chiffrement à l'envoi.

- [ ] Passé — date / appareil / version :

### P21 — Non-régression après réorganisation du code `AUDIT` `RÉGRESSION`

**Conditions** : Nouvelle version installée par-dessus l'ancienne.

**Étapes** :

1. Vérifier : synchro iCloud des tags/écoutes, cache hors ligne Collection/Wantlist, thèmes de couleur, édition d'un exemplaire (champs perso), tri des artistes, mini-lecteur (texte défilant), scan par lot.

**Résultat attendu** : Comportements identiques à la version précédente (code uniquement déplacé).

- [ ] Passé — date / appareil / version :

### P22 — Données locales partiellement illisibles `AUDIT` `DEV` `AUTO`

**Conditions** : Build Debug ; dans les préférences de l'app (débogueur ou outil), altérer une entrée du JSON des tags d'un compte.

**Étapes** :

1. Relancer l'app et ouvrir la Collection.

**Résultat attendu** : Seuls les tags de l'entrée altérée manquent ; tous les autres sont conservés. La donnée d'origine est copiée sous la clé `<clé>.unreadableBackup` ; rien n'est vidé.

- [ ] Passé — date / appareil / version :

### P23 — États vides et erreurs avec une action `AUDIT` `AUTO`

**Conditions** : Compte avec collection vide ; puis réseau coupé au chargement d'une fiche.

**Étapes** :

1. Collection vide / Wantlist vide : toucher « Rechercher un disque ».
2. Ouvrir une fiche artiste, master, label ou release en échec réseau, puis toucher « Réessayer ».
3. Provoquer une erreur Discogs (ex. release supprimée).

**Résultat attendu** : « Rechercher un disque » ouvre l'onglet Recherche ; « Réessayer » recharge la fiche. Les erreurs Discogs s'affichent dans la langue de l'appareil (plus de message anglais brut de l'API).

- [ ] Passé — date / appareil / version :

### P24 — VoiceOver : graphiques des Stats `AUDIT`

**Conditions** : VoiceOver activé, Stats chargées.

**Étapes** :

1. Placer le curseur sur chaque graphique (artistes, genres, supports, labels, années).
2. Balayer vers le haut/bas pour parcourir les actions, toucher deux fois.

**Résultat attendu** : Chaque graphique est lu comme un seul élément (titre + 5 premières valeurs) ; les actions listent ses éléments et ouvrent la liste de disques correspondante, comme un toucher.

- [ ] Passé — date / appareil / version :

### P25 — Réduire les animations `AUDIT`

**Conditions** : Réglages iOS → Accessibilité → Mouvement → Réduire les animations activé.

**Étapes** :

1. Ouvrir la Collection pendant un chargement (squelettes).
2. Faire défiler une fiche release et une fiche artiste.
3. Faire défiler le carrousel.

**Résultat attendu** : Squelettes fixes (plus de reflet tournant) ; la jaquette défile avec le contenu (pas de parallaxe) ; pochettes du carrousel sans effet de zoom (fondu conservé).

- [ ] Passé — date / appareil / version :

### P26 — Couleur du thème partout `AUDIT`

**Conditions** : Thème autre que Signature.

**Étapes** :

1. Parcourir : pastille de dossier d'une ligne Collection et de « Mon exemplaire », lettre active de la barre A-Z, avatar de Réglages et du profil, action de balayage de la Wantlist, pochette vinyle par défaut, encadré d'alerte de prix.

**Résultat attendu** : Tous ces éléments suivent le thème choisi (plus de violet fixe).

- [ ] Passé — date / appareil / version :

### P27 — Swift 6 : aucun arrêt dans les traitements de fond `AUDIT` `RÉGRESSION`

**Conditions** : Build installé depuis Xcode (pour voir un éventuel arrêt « Incorrect actor executor » dans la console), compte connecté.

**Étapes** :

1. Couper puis rétablir le réseau (mode avion) plusieurs fois.
2. Se déconnecter puis se reconnecter (OAuth Discogs).
3. Lancer une écoute sur platine (Live Activity avec pochette téléchargée).
4. Laisser l'app en arrière-plan et déclencher la tâche de fond des alertes (F13).
5. Recevoir une notification d'alerte, app ouverte puis fermée, et la toucher.
6. Modifier des tags et attendre la synchro iCloud (premium).

**Résultat attendu** : Aucun arrêt de l'app à aucune étape ; la bannière hors ligne, la connexion, la Live Activity, les alertes et la synchro fonctionnent comme avant.

- [ ] Passé — date / appareil / version :

### P28 — Webview limitée aux pages Discogs `AUDIT` `AUTO`

**Conditions** : Être connecté à discogs.com dans la webview de l'app (ex. via « Gérer les champs sur discogs.com »).

**Étapes** :

1. Depuis une page Discogs ouverte dans l'app, toucher un lien vers un autre site (site d'un label, lien externe d'une fiche).
2. Profil Discogs → toucher le site personnel indiqué.
3. Sur la page de connexion discogs.com, utiliser « Continuer avec Google » ou « avec Apple ».

**Résultat attendu** : Les liens vers d'autres sites s'ouvrent dans Safari ; la webview reste sur discogs.com. La connexion Google ou Apple à discogs.com fonctionne toujours dans la webview.

- [ ] Passé — date / appareil / version :

### P29 — Contraste du texte doré et du texte tertiaire `AUDIT`

**Conditions** : Compte sans abonnement (pour voir les éléments Premium).

**Étapes** :

1. Mode clair : Réglages (bannière « À partir de … / mois »), une carte Premium verrouillée (mention « PREMIUM »), le paywall (« et N fonctionnalités supplémentaires »).
2. Mode sombre : dates et mentions discrètes (fiche release, Stats, Réglages).

**Résultat attendu** : Mode clair : les textes dorés sont d'un or plus profond (bronze) et bien lisibles ; fonds et dégradés dorés inchangés. Mode sombre : les textes tertiaires restent plus discrets que les secondaires mais nettement lisibles.

- [ ] Passé — date / appareil / version :

### P30 — Changement de compte et démo : aucune donnée ne passe d'un compte à l'autre `AUDIT` `AUTO` `LIMITE`

**Conditions** : Deux comptes Discogs (A avec des champs personnalisés « Prix d'achat », B sans ou avec d'autres champs), wantlists de plus de 50 disques ; mode démo ; réseau lent (Conditionneur de liens réseau) pour les étapes 3 et 4.

**Étapes** :

1. Avec A : ouvrir « Mon exemplaire » d'un disque (champs de A affichés), puis se déconnecter et se connecter avec B ; rouvrir « Mon exemplaire ».
2. Avec B : faire défiler la Wantlist jusqu'en bas puis tirer pour actualiser, et refaire défiler.
3. Ouvrir l'onglet Stats de A sur réseau lent, se déconnecter pendant le chargement, se connecter avec B.
4. En démo, hors ligne : modifier un champ dans « Mon exemplaire » ; quitter la démo, revenir en démo.
5. En démo, créer une alerte de prix (si possible), quitter puis relancer la démo.

**Résultat attendu** : 1 : B voit ses propres champs (ou aucun), jamais ceux de A. 2 : aucun disque en double dans la Wantlist. 3 : les Stats de B n'affichent jamais la collection de A, et le chargement de A s'arrête. 4 : la modification est refusée avec le message du mode démo (rien n'est mis en file) ; à la nouvelle démo, aucune modification en attente. 5 : aucune alerte de la démo précédente. Aucune synchro iCloud ne démarre en démo (règles de cache et de fusion couvertes par AccountIsolationTests).

- [ ] Passé — date / appareil / version :

### P31 — Cohérence : menus par appui long, hors ligne, haptique et confirmations `AUDIT`

**Conditions** : Compte réel ; Collection et Wantlist en mode Liste puis Mosaïque ; un disque possédé dans les résultats de recherche ; un artiste personnalisé dans Tri des artistes.

**Étapes** :

1. Appui long sur une ligne de Collection et de Wantlist (mode Liste), puis sur une pochette de la mosaïque Wantlist.
2. Appui long sur un résultat de recherche possédé, puis sur un artiste personnalisé dans Tri des artistes.
3. Couper le réseau avec un cache de plus de 6 h : appui long sur un disque de Collection.
4. En mode avion, ouvrir un label et un master déjà ouverts, puis Recherche.
5. Retirer un disque depuis une liste, puis depuis une fiche ; ajouter un disque.
6. Sélection multiple > Tags : appui long sur un tag porté par une partie de la sélection > Retirer de toute la sélection.
7. Scan par lot avec la caméra refusée dans Réglages iOS.

**Résultat attendu** : 1 : menu avec les mêmes actions que le balayage (Vers la collection, Supprimer, Alerte pour la Wantlist ; écoute, rangement, modifier, supprimer pour la Collection). 2 : « J'écoute » / « Personnaliser le tri » et « Rétablir » ; texte d'aide sous la liste des artistes. 3 : ni Modifier ni Supprimer dans le menu. 4 : bandeau « Hors ligne : cette page ne se met plus à jour » sur le label et le master (ou « Cette fiche nécessite une connexion réseau » s'ils n'ont jamais été ouverts) ; Recherche n'affiche plus qu'un seul message hors ligne. 5 : même vibration légère au retrait quel que soit l'écran, vibration de succès à l'ajout ; un retrait en lot ne vibre qu'une fois. 6 : la confirmation s'ouvre (comme au toucher). 7 : un message explique le problème de caméra. Partout, retirer un disque de la collection ou de la wantlist se dit « Supprimer » (menus, confirmations, bulles), et les compteurs parlent d'« albums » (Collection, Wantlist, listes des Stats). Les alertes (fiche disque, scan par lot, export, achat) se ferment par OK sans réapparaître.

- [ ] Passé — date / appareil / version :

### P32 — Fluidité : tags, Collection et Tri des artistes `AUDIT`

**Conditions** : Compte réel avec une grande collection (500 disques ou plus) et une trentaine de tags.

**Étapes** :

1. Ouvrir Réglages > Tags et taper rapidement un nom dans la recherche ; ouvrir la gestion des tags d'un disque puis d'une sélection multiple.
2. Collection en Liste, Mosaïque et Carrousel : faire défiler vite d'un bout à l'autre ; ajouter un tag à un disque et vérifier sa ligne.
3. Réglages > Rangement > Tri des artistes : taper dans la recherche, personnaliser puis rétablir un artiste.
4. Stats : sélectionner un genre et faire défiler la page.

**Résultat attendu** : Aucune saccade ni latence de frappe ; compteurs d'exemplaires par tag exacts ; badges « Ex. 1/2 » et tags corrects après une modification ; la clé de tri affichée suit immédiatement la personnalisation ; le détail par style du genre reste juste après une synchro.

- [ ] Passé — date / appareil / version :

### P33 — VoiceOver : note, mini-lecteur, graphique de la cote et zones de toucher `AUDIT`

**Conditions** : VoiceOver activé ; un disque possédé ; une lecture Apple Music en cours ; Premium avec au moins deux points d'historique de cote ; Réduire les animations testé ensuite.

**Étapes** :

1. Fiche d'un disque possédé : placer le curseur sur « Ma note », balayer vers le haut puis vers le bas.
2. Mini-lecteur Apple Music agrandi : placer le curseur sur la barre de progression et balayer vers le haut ; toucher deux fois la zone titre.
3. Stats > Évolution de la cote : écouter l'annonce.
4. Sans VoiceOver : toucher juste à côté de la croix d'une feuille, des étoiles, des boutons ronds du carrousel et du bouton stop du mini-lecteur.
5. Activer Réduire les animations : faire apparaître une bulle, un badge, la pastille hors ligne.

**Résultat attendu** : 1 : un seul élément « Ma note », valeur « Aucune note » ou « N étoiles », qui change d'une étoile par balayage. 2 : « Position de lecture » avance de 15 s ; le double-toucher ouvre le lecteur, l'indice « Ouvre le lecteur » est lu à part. 3 : médiane de début et de fin avec leurs dates, puis « en hausse / en baisse de X % » ou « stable ». 4 : le toucher est pris un peu en dehors du dessin (zone de 44 pt), sans changement visuel. 5 : apparitions en simple fondu, sans déplacement ni zoom.

- [ ] Passé — date / appareil / version :

### P34 — Anglais : textes, nombres et vocabulaire `AUDIT`

**Conditions** : iPhone en anglais (Réglages iOS > Langue), puis en français.

**Étapes** :

1. Recherche : sélecteur de portée.
2. Profil Discogs (Réglages > compte) : rang, notes acheteur/vendeur ; fiche d'un disque : note de la communauté.
3. Export PDF avec des prix d'achat.
4. Stats et grades : textes mentionnant les écoutes sur platine.
5. Réglages > Hors ligne : télécharger la collection.

**Résultat attendu** : 1 : « All / Releases / Artists / Labels ». 2-3 : séparateur décimal et symbole de devise selon la langue (« 4.5 » en anglais, « 4,5 » en français ; « 99.5% » / « 99,5 % »). 4 : « listen(s) » pour la platine, « play(s) » seulement pour Apple Music. 5 : « 1 record » au singulier.

- [ ] Passé — date / appareil / version :

### P35 — Widget et Live Activity après la mise en commun des fichiers `AUDIT`

**Conditions** : Build installé par-dessus la version précédente (sans désinstaller) ; widget « Album du jour » sur l'écran d'accueil ; compte Premium.

**Étapes** :

1. Ouvrir l'app, laisser la Collection se charger, revenir à l'écran d'accueil.
2. Changer de thème dans l'app, puis revenir au widget.
3. Lancer une écoute sur platine : Live Activity et Dynamic Island ; l'arrêter depuis la Live Activity.
4. Laisser une Live Activity démarrée par l'ancienne version (si possible) et ouvrir le nouveau build.

**Résultat attendu** : Le widget affiche toujours un disque de la collection et la couleur du thème ; la Live Activity apparaît avec sa jaquette et se termine depuis son bouton ; une activité de l'ancienne version se termine normalement.

- [ ] Passé — date / appareil / version :

### P36 — Non-régression après le découpage de la Collection, des Stats et de la fiche disque `AUDIT`

**Conditions** : Compte réel avec plusieurs dossiers ; un disque en 2 exemplaires ; puis mode avion.

**Étapes** :

1. Collection : changer de dossier, de tri (y compris Rangement), filtrer par tag et format, chercher, tirer pour actualiser, faire défiler jusqu'au bout d'un grand dossier.
2. Sélection multiple : déplacer vers un dossier, gérer les tags, supprimer.
3. Fiche disque : ajouter à la collection (dossier par défaut puis « Toujours demander »), déplacer un exemplaire, noter, saisir un prix d'achat, supprimer un exemplaire puis tous ; ajouter puis retirer de la wantlist.
4. Refaire 3 en mode avion (moins de 6 h puis plus de 6 h de cache), puis revenir en ligne.
5. Stats : ouvrir chaque feuille (genre, style, label, support, artiste, année, décennie), lancer et arrêter une écoute.

**Résultat attendu** : Mêmes comportements qu'avant : listes, compteurs de dossiers et badges à jour sans rechargement ; hors ligne, bulle « Hors ligne : synchronisé au retour du réseau » puis envoi au retour ; blocage « données de plus de 6 h » ; sur refus de Discogs, l'état est restauré avec un message. Stats : chiffres, années originales et classements identiques ; les derniers ajouts suivent les ajouts et retraits faits ailleurs.

- [ ] Passé — date / appareil / version :

### P37 — Contraste sur la teinte du thème et palette des graphiques `AUDIT` `AUTO`

**Conditions** : Premium actif ; parcourir les 10 thèmes, en mode clair puis sombre.

**Étapes** :

1. Fiche disque : boutons « Dans ma collection » / « Dans ma wantlist » actifs, pastilles de genre, bouton du disque en écoute, lien vers le marketplace.
2. Collection : bulle et pastille de la barre A-Z pendant le glissé, compteur des en-têtes de section, bulle d'ajout.
3. Wantlist : pastille de prix sélectionnée. Artiste : onglet sélectionné. Boutons « Réessayer » / « Se connecter » (mode avion).
4. Stats : camemberts genres, styles, labels et supports.
5. Avertissements en mode clair : bandeau hors ligne, nom de dossier en double, limite de tags atteinte, tag déjà existant, Apple Music refusé.

**Résultat attendu** : 1-3 : texte et icônes toujours lisibles sur l'accent (presque-noir sur les teintes claires : or, émeraude, turquoise, orange, ardoise en sombre ; blanc ailleurs). 4 : aucune part voisine de la même teinte que l'accent (pas de bleu avec Bleu Électrique, de vert avec Émeraude, d'orange avec Orange Crépuscule, de rouge avec Signature) ; CD et cassette gardent une couleur distincte du vinyle. 5 : orange et sarcelle plus foncés et lisibles sur fond clair, inchangés en sombre. Ratios couverts par AccentContrastTests et ChartPaletteTests ; le rendu reste à vérifier à l'œil.

- [ ] Passé — date / appareil / version :

### P38 — Contraste des boutons pleins et jetons de couleur dans les 10 thèmes `AUDIT`

**Conditions** : Les 10 thèmes, en mode clair puis sombre ; un disque possédé et en wantlist ; un genre sur la fiche ; un résultat de recherche vide.

**Étapes** :

1. Pour chaque thème, en clair puis en sombre : fiche disque (boutons Collection/Wantlist, pastilles de genre, « Emplacement de cet album », bouton d'écoute en cours), écran vide de la Collection (« Rechercher un disque »), barre d'index, bulle d'ajout.
2. Mosaïque Collection : badges « Ex. 1/2 » et note.
3. Stats en thème Bleu, Vert puis Orange : camemberts genres et supports.
4. Réglages > Thème : étiquette PREMIUM ; compte non Premium, toucher un thème verrouillé ; paywall : étiquette PREMIUM de l'en-tête.
5. Messages d'avertissement (dossier en double, limite de tags), bandeau hors ligne.
6. Stats > Écoutes : podium (or, argent, bronze) ; paywall : en-tête doré.
7. Export PDF d'une collection dont beaucoup de titres tiennent sur deux lignes : lire les pages d'inventaire.

**Résultat attendu** : 1 : texte lisible sur chaque bouton plein — blanc en mode clair, foncé en mode sombre (pour les 10 thèmes). 2 : badges à 11 pt, lisibles, sans débordement. 3 : aucune part voisine de la même teinte que l'accent. 4 : étiquettes PREMIUM dorées, identiques ; le thème verrouillé ouvre le paywall en plein écran (avec achat), plus la simple liste des fonctions ; l'étiquette du paywall a un texte foncé lisible. 5 : orange foncé en clair, lisible ; orange vif en sombre. Thème Violet en clair : teinte à peine plus foncée qu'avant. 6 : couleurs identiques à avant. 7 : texte à 9 pt minimum, 13 albums par page, rien de coupé en bas de page ni sous le numéro de page.

- [ ] Passé — date / appareil / version :

### P39 — Pastille de position de la barre A-Z pendant le défilement `AUDIT`

**Conditions** : Collection d'au moins 200 albums triée par artiste, puis par année ; Wantlist avec plusieurs dizaines de disques.

**Étapes** :

1. Collection, mode Liste : faire défiler lentement puis vite de haut en bas.
2. Même chose en mode Mosaïque et en mode Carrousel.
3. Toucher une lettre de la barre pour y sauter, puis refaire défiler.
4. Répéter dans la Wantlist (Liste et Mosaïque).

**Résultat attendu** : La pastille de la barre suit la lettre (ou l'année) de la section affichée en haut, sans retard visible. Le défilement reste fluide, sans à-coups aux changements de section. Même comportement dans la Wantlist.

- [ ] Passé — date / appareil / version :

### P40 — Fiche disque et page artiste après découpage du code : comportement inchangé `AUDIT` `AUTO`

**Conditions** : Collection avec des disques d'un artiste (dont un homonyme proche, ex. Ghost et Ghostface Killah) ; un master dont un pressage est possédé ; une wantlist ; version de développement pour la dernière étape.

**Étapes** :

1. Ouvrir une fiche disque : jaquette plein bord, titre et artistes cliquables, défilement (parallaxe, flou), toucher la jaquette (visionneuse), ajouter à la collection (« pop » de la jaquette, encart « Ajouté à ta collection ! »).
2. Sur la fiche : ligne « Rangement physique » (Premium et non Premium), « Photos et vidéos », « Autres informations », Marketplace.
3. Ouvrir la page d'un artiste : compteurs possédés/wantlist, discographie (sections Albums, Singles & EP…, « Tri en cours »), badges possédé/wantlist sur les œuvres, toucher une œuvre possédée puis une œuvre non possédée.
4. Depuis cette page, ajouter puis retirer un disque de l'artiste dans la collection.
5. Version de développement : Réglages > Options développeur : les 8 sections, export puis restauration d'une sauvegarde JSON (même compte, puis autre compte).

**Résultat attendu** : 1-2 : rendu et gestes identiques à avant. 3 : seuls les disques crédités à cet artiste comptent (Ghostface Killah n'est pas rattaché à Ghost) ; un master est marqué possédé si l'un de ses pressages l'est ; la ligne ouvre l'exemplaire le plus récemment ajouté, sinon la fiche master. 4 : les compteurs et badges suivent sans recharger la page. 5 : sections et actions identiques ; la restauration d'un autre compte est refusée avec le même message. Règles couvertes par ArtistLibraryIndexTests.

- [ ] Passé — date / appareil / version :

### P41 — Boutons de validation « OK » dans les feuilles de saisie `AUDIT`

**Conditions** : VoiceOver activé pour la dernière étape ; langue du téléphone en français puis en anglais.

**Étapes** :

1. Fiche disque : feuille « Prix et état ».
2. Wantlist : feuille d'alerte de prix (clavier ouvert).
3. Réglages > Tags : « Renommer le tag ».
4. Rangement : « Éditer le tri » d'un artiste.
5. Réglages > Dossiers : « Nouveau dossier » puis « Renommer le dossier ».
6. Parcourir chaque bouton avec VoiceOver.

**Résultat attendu** : 1 à 4 : le bouton en haut à droite se nomme « OK » (« OK » aussi en anglais), à côté d'« Annuler » ; il enregistre comme avant. 2 : le bouton au-dessus du clavier se nomme « Terminé » et ne ferme que le clavier. 5 : « Créer » pour un nouveau dossier, « OK » pour un renommage. 6 : VoiceOver annonce « Enregistrer le prix et l'état », « Enregistrer l'alerte », « Enregistrer le nouveau nom du tag », « Enregistrer le tri », « Créer le dossier » ou « Enregistrer le nom du dossier ». Le bouton « Enregistrer » de la saisie rapide du scan par lot (G29) est inchangé.

- [ ] Passé — date / appareil / version :

<a id="famille-q"></a>

## Q — Lecture Apple Music (mini-lecteur & connexion de compte)

### Q1 — Bouton de lecture en face de chaque titre

**Conditions** : Fiche release avec tracklist, Apple Music jamais autorisé.

**Étapes** :

1. Ouvrir une fiche release ou master avec plusieurs titres.

**Résultat attendu** : Un bouton de lecture rond apparaît à droite de chaque titre jouable ; grisé par défaut jusqu'à résolution de la recherche de correspondance.

- [ ] Passé — date / appareil / version :

### Q2 — Première autorisation Apple Music au premier appui

**Conditions** : Autorisation Apple Music jamais demandée sur cet appareil (statut `.notDetermined`).

**Étapes** :

1. Toucher le bouton de lecture d'un titre.

**Résultat attendu** : L'invite système Apple Music apparaît ; après acceptation, la recherche de correspondance se poursuit et la lecture démarre sans qu'un second appui soit nécessaire (régression déjà corrigée).

- [ ] Passé — date / appareil / version :

### Q3 — Extrait de 30s sans abonnement actif

**Conditions** : Titre reconnu (bouton vert), pas d'abonnement Apple Music actif.

**Étapes** :

1. Toucher le bouton de lecture d'un titre reconnu.

**Résultat attendu** : Un extrait de 30s démarre via le lecteur intégré ; le bouton passe en pause ; l'extrait s'arrête automatiquement à la fin et le bouton redevient « lecture ».

- [ ] Passé — date / appareil / version :

### Q4 — Bascule lecture/pause sur le même titre

**Conditions** : Lecture en cours sur un titre.

**Étapes** :

1. Toucher à nouveau le même bouton.

**Résultat attendu** : La lecture se met en pause immédiatement ; un nouvel appui la relance.

- [ ] Passé — date / appareil / version :

### Q5 — Changement de titre pendant une lecture en cours

**Conditions** : Lecture en cours sur le titre A.

**Étapes** :

1. Toucher le bouton de lecture du titre B dans la même tracklist.

**Résultat attendu** : Le titre A s'arrête, le titre B démarre ; le mini-lecteur et le bouton du titre A reviennent à l'état neutre sans superposition de deux lectures.

- [ ] Passé — date / appareil / version :

### Q6 — Titre sans correspondance Apple Music

**Conditions** : Titre obscur/rare peu susceptible d'être dans le catalogue Apple Music.

**Étapes** :

1. Observer le bouton de ce titre après le chargement de la page.

**Résultat attendu** : Le bouton reste grisé et désactivé ; aucun son ne se déclenche au toucher.

- [ ] Passé — date / appareil / version :

### Q7 — Connexion Apple Music depuis Réglages

**Conditions** : Voir aussi J16-J18.

**Étapes** :

1. Réglages → section Apple Music → Connecter Apple Music.

**Résultat attendu** : Statut mis à jour selon autorisation + abonnement réel du compte Apple connecté sur l'appareil.

- [ ] Passé — date / appareil / version :

### Q8 — Lecture complète avec abonnement actif `LIMITE`

**Conditions** : Compte Apple Music connecté avec abonnement actif (voir Q7).

**Étapes** :

1. Toucher le bouton de lecture d'un titre reconnu.

**Résultat attendu** : Le morceau complet se lance via `ApplicationMusicPlayer` (pas seulement 30s) ; le mini-lecteur affiche la durée réelle du morceau.

- [ ] Passé — date / appareil / version :

### Q9 — Repli automatique sur l'extrait si la lecture complète échoue `LIMITE`

**Conditions** : Abonnement actif, mais le morceau ciblé échoue à démarrer en lecture complète (ex. restriction régionale).

**Étapes** :

1. Toucher le bouton de lecture de ce titre.

**Résultat attendu** : Bascule silencieuse vers l'extrait de 30s plutôt qu'une erreur visible ou une absence totale de son.

- [ ] Passé — date / appareil / version :

### Q10 — Mini-lecteur visible sur les 5 onglets pendant une lecture

**Conditions** : Lecture en cours (extrait ou complète).

**Étapes** :

1. Changer d'onglet successivement (Collection, Wantlist, Stats, Recherche, Réglages).

**Résultat attendu** : Le mini-lecteur Liquid Glass reste visible au-dessus de la barre d'onglets sur chaque onglet, sans interrompre la lecture.

- [ ] Passé — date / appareil / version :

### Q11 — Appui sur le mini-lecteur ouvre la fenêtre de lecture `AUDIT`

**Conditions** : Lecture en cours, navigation vers un autre onglet.

**Étapes** :

1. Toucher la zone pochette/titre du mini-lecteur.
2. Dans la fenêtre, toucher le bouton disque en haut à droite.

**Résultat attendu** : Le toucher ouvre la fenêtre de lecture plein écran (voir Q27), quel que soit l'onglet affiché. Le bouton disque la ferme et ramène directement à la fiche release/master d'où la lecture a été lancée.

- [ ] Passé — date / appareil / version :

### Q12 — Glissement sur la barre de progression (scrubbing)

**Conditions** : Lecture en cours, mini-lecteur visible.

**Étapes** :

1. Glisser le doigt le long de la barre de progression du mini-lecteur.

**Résultat attendu** : La tête de lecture se déplace immédiatement à la position relâchée ; le temps affiché se met à jour pendant le glissement ; retour haptique à la fin du geste.

- [ ] Passé — date / appareil / version :

### Q13 — Bouton pause du mini-lecteur

**Conditions** : Lecture en cours.

**Étapes** :

1. Toucher le bouton pause du mini-lecteur.

**Résultat attendu** : La lecture s'arrête et le mini-lecteur disparaît (plus rien à afficher une fois arrêté).

- [ ] Passé — date / appareil / version :

### Q14 — Mini-lecteur Apple Music vs lecture « platine » (journal manuel) `LIMITE`

**Conditions** : Une session d'écoute manuelle (platine) est en cours quand une lecture Apple Music est lancée.

**Étapes** :

1. Démarrer une session d'écoute manuelle (platine) sur un album.
2. Lancer une lecture Apple Music sur un titre d'un autre album.

**Résultat attendu** : Un seul des deux mini-lecteurs est visible à la fois (le plus récent prend le dessus) ; pas de superposition visuelle des deux barres.

- [ ] Passé — date / appareil / version :

### Q15 — Tracklist longue ne bloque pas l'interface à l'ouverture `RÉGRESSION`

**Conditions** : Release avec 10+ titres (ex. « Foreign Tongues »).

**Étapes** :

1. Ouvrir la fiche de ce release et observer la fluidité dès l'affichage de la tracklist.

**Résultat attendu** : Pas de gel ni de ralentissement perceptible à l'ouverture ; les recherches de correspondance s'enchaînent en arrière-plan une par une plutôt que toutes en même temps (régression corrigée).

- [ ] Passé — date / appareil / version :

### Q16 — Pas de gel pendant une lecture complète prolongée `RÉGRESSION`

**Conditions** : Lecture complète (abonnement actif) laissée en cours plusieurs minutes.

**Étapes** :

1. Laisser un morceau jouer en entier tout en naviguant dans l'app.

**Résultat attendu** : Aucun gel ponctuel de l'interface ; le suivi de progression interroge le lecteur toutes les 0,5s (pas 10×/seconde) et s'arrête si le lecteur n'a plus d'entrée valide.

- [ ] Passé — date / appareil / version :

### Q17 — Artiste avec featuring reconnu comme correspondance valide `LIMITE`

**Conditions** : Titre dont l'artiste Apple Music inclut un featuring (ex. « Daft Punk & Julian Casablancas » pour « Instant Crush »).

**Étapes** :

1. Ouvrir une fiche release contenant un tel titre et observer le statut du bouton.

**Résultat attendu** : Le titre est reconnu comme une correspondance valide (bouton vert) malgré la différence de nom d'artiste entre Discogs et Apple Music.

- [ ] Passé — date / appareil / version :

### Q18 — Appareil hors ligne `LIMITE`

**Conditions** : Mode avion activé.

**Étapes** :

1. Ouvrir une fiche release avec tracklist.

**Résultat attendu** : Les boutons restent grisés (recherche impossible), pas de crash ni de blocage de l'interface en attendant une réponse réseau qui ne viendra pas. Au retour du réseau, un appui relance la recherche : un titre n'est jamais marqué définitivement « sans correspondance » à cause d'une simple erreur réseau (voir Q22).

- [ ] Passé — date / appareil / version :

### Q19 — Abonnement Apple Music expiré pendant une lecture complète `LIMITE`

**Conditions** : Lecture complète en cours, abonnement qui expire/est révoqué en cours de lecture (test via compte développeur si possible).

**Étapes** :

1. Simuler ou attendre l'expiration de l'abonnement pendant une lecture complète.

**Résultat attendu** : La lecture s'arrête proprement ou bascule sur l'extrait, sans crash ni état de mini-lecteur incohérent.

- [ ] Passé — date / appareil / version :

### Q20 — Deux titres touchés très rapidement `AUDIT` `RÉGRESSION`

**Conditions** : Tracklist avec plusieurs titres reconnus.

**Étapes** :

1. Toucher le titre A puis immédiatement le titre B (moins d'une seconde).

**Résultat attendu** : Seul le titre B est lu ; le mini-lecteur affiche B ; aucun double son.

- [ ] Passé — date / appareil / version :

### Q21 — Fin d'un morceau complet `AUDIT` `RÉGRESSION`

**Conditions** : Abonnement Apple Music actif.

**Étapes** :

1. Laisser un morceau complet se terminer.

**Résultat attendu** : À la fin du morceau, le mini-lecteur disparaît et le bouton du titre revient à l'état lecture (il ne reste plus affiché « en lecture »).

- [ ] Passé — date / appareil / version :

### Q22 — Recherche en échec puis retour du réseau `AUDIT` `RÉGRESSION`

**Conditions** : Network Link Conditioner « 100% Loss ».

**Étapes** :

1. Toucher la lecture d'un titre (la recherche échoue).
2. Rétablir le réseau et toucher à nouveau ce titre.

**Résultat attendu** : Le second appui relance la recherche et lit le titre ; le bouton n'est pas resté grisé pour toute la session.

- [ ] Passé — date / appareil / version :

### Q23 — Arrêt pendant le démarrage d'un morceau complet `AUDIT` `LIMITE`

**Conditions** : Abonnement actif, réseau lent conseillé.

**Étapes** :

1. Toucher la lecture d'un titre puis, immédiatement, le même bouton pour arrêter.

**Résultat attendu** : Aucune musique ne continue de jouer sans interface pour l'arrêter.

- [ ] Passé — date / appareil / version :

### Q24 — Extraits enchaînés et audio des autres apps `AUDIT`

**Conditions** : Pas d'abonnement (extraits 30 s) ; un podcast en pause dans l'app Podcasts.

**Étapes** :

1. Enchaîner rapidement 5 extraits différents.
2. Arrêter la lecture, puis reprendre le podcast.

**Résultat attendu** : Chaque extrait produit bien du son (session audio jamais désactivée en cours de lecture) ; le podcast peut reprendre normalement après l'arrêt.

- [ ] Passé — date / appareil / version :

### Q25 — Appel entrant pendant la lecture `LIMITE`

**Conditions** : Extrait ou morceau complet en cours.

**Étapes** :

1. Recevoir un appel (ou déclencher Siri), puis raccrocher.

**Résultat attendu** : La lecture se met en pause pendant l'appel ; l'état du mini-lecteur reste cohérent avec ce qui est réellement joué.

- [ ] Passé — date / appareil / version :

### Q26 — Écouteurs débranchés pendant la lecture `LIMITE`

**Conditions** : Lecture via écouteurs filaires ou AirPods.

**Étapes** :

1. Débrancher / retirer les écouteurs pendant la lecture.

**Résultat attendu** : La lecture se met en pause (comportement iOS standard) ; le mini-lecteur reflète l'état réel, sans son sur le haut-parleur à l'insu de l'utilisateur.

- [ ] Passé — date / appareil / version :

### Q27 — Fenêtre de lecture plein écran (façon « Lecture en cours » d'Apple Music) `AUDIT` `AUTO`

**Conditions** : Disque avec tracklist dont plusieurs titres existent sur Apple Music ; connexion Apple Music facultative (extraits de 30 s sinon).

**Étapes** :

1. Lancer un titre depuis la fiche d'un disque, aller sur un autre onglet, puis toucher le mini-lecteur.
2. Observer l'écran : pochette en haut, titre et artiste à gauche, barre de progression, commandes, volume, AirPlay et liste.
3. Toucher suivant, précédent, puis déplacer la barre de progression et le curseur de volume.
4. Toucher le bouton liste : toucher une autre piste, puis la piste en cours.
5. Toucher le bouton disque à droite du titre.
6. Observer l'ouverture (la fenêtre sort du mini-lecteur en grandissant), puis glisser vers le bas lentement (elle suit le doigt et se rétracte dans le mini-lecteur, sans saccade en fin de course), relâcher à mi-course (elle revient), puis glisser franchement ; fermer aussi en touchant le repère en haut, avec la barre d'onglets normale puis réduite (mini-lecteur inline) ; rouvrir et toucher stop.
7. Lancer une écoute sur platine (voir Q28).
8. Mode avion, puis ouvrir la fenêtre ; essayer avec VoiceOver (geste Échappement pour fermer).

**Résultat attendu** : L'écran reprend la disposition d'Apple Music : pochette pleine largeur sur environ la moitié haute qui se fond dans un arrière-plan flouté, repère de glissé en haut, titre de la piste et artiste alignés à gauche avec le bouton disque (fiche du disque) à droite, barre de progression avec temps écoulé et temps restant, précédent / stop / suivant, curseur de volume, choix de la sortie audio (AirPlay) et bouton liste. Suivant et précédent changent de piste en sautant les intitulés de section et les titres sans correspondance ; le curseur de volume règle le volume de l'appareil (rien dans le Simulateur). La liste s'ouvre en feuille, la piste en cours repérée par une forme d'onde, et un toucher sur la piste en cours ne l'arrête pas. Le bouton disque ferme la fenêtre et ramène directement à la fiche d'origine, sans menu intermédiaire. Le glissé vers le bas, le repère ou l'Échappement VoiceOver ferment la fenêtre ; stop l'arrête et la ferme. Hors ligne, un message remplace la liste des pistes.

- [ ] Passé — date / appareil / version :

### Q28 — Écoute sur platine : petite feuille depuis le mini-lecteur `AUDIT`

**Conditions** : Écoute sur platine démarrée depuis une fiche (mini-lecteur « Écoute sur platine » visible).

**Étapes** :

1. Toucher le mini-lecteur (barre d'onglets normale, puis réduite).
2. Observer la feuille : jaquette entière devant un disque noir qui dépasse, dont l'étiquette (centre de la jaquette) tourne en continu, titre de l'album, artiste, bouton disque à droite du titre, bouton « Arrêter l'écoute ».
3. Toucher le bouton disque (retour à la fiche de l'album), puis rouvrir la feuille, la fermer en glissant vers le bas, la rouvrir et toucher « Arrêter l'écoute ».
4. Rouvrir la feuille, puis arrêter l'écoute depuis la Live Activity.
5. Essayer en police agrandie et avec VoiceOver.

**Résultat attendu** : Une petite feuille s'ouvre, avec la jaquette entière (jamais recadrée) devant un disque noir à sillons dont seule l'étiquette tourne, à environ 33 tours par minute et sans à-coup (avec « Réduire les animations » : disque immobile) ; à la hauteur de son contenu : pas d'espace vide en bas, pas de pistes, pas de barre de progression ni de volume, un seul bouton de lecture (stop), plus le bouton disque placé au même endroit que dans la fenêtre Apple Music : il ferme la feuille et ouvre la fiche de l'album. Elle se ferme au glissé. « Arrêter l'écoute » arrête l'écoute (mini-lecteur et Live Activity disparaissent) et ferme la feuille sans la vider d'un coup. Arrêter l'écoute ailleurs ferme la feuille. En police agrandie, la feuille grandit et tout reste lisible.

- [ ] Passé — date / appareil / version :

### Q29 — Écoute sur platine : le visuel suit le support (vinyle ou CD) `AUDIT` `AUTO`

**Conditions** : Un album en collection au format Vinyl, un au format CD, un « Box Set » de CD, un vinyle avec CD bonus, une cassette ; Réduire les animations désactivé puis activé ; thème clair et sombre.

**Étapes** :

1. Lancer une écoute sur platine d'un vinyle, toucher le mini-lecteur.
2. Arrêter, lancer l'écoute d'un CD, toucher le mini-lecteur.
3. Refaire avec le coffret de CD, le vinyle avec CD bonus et la cassette.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : Vinyle : pochette entière devant un disque noir à étiquette qui tourne, comme avant. CD (et coffret de CD, premier support reconnu) : même disposition, mais le disque est argenté, plus petit, sans rien d'imprimé dessus, avec un reflet irisé qui tourne, un moyeu translucide et un trou central transparent. Vinyle avec CD bonus : disque vinyle ; cassette avec CD : cassette (le premier support reconnu décide). Cassette : la pochette reste carrée et entière, et c'est une cassette (rectangle en paysage) qui dépasse derrière, sa coque en plastique teintée de la couleur moyenne de la pochette (lisible aussi pour une pochette presque blanche ou presque noire) avec biseau, reflet et ombre portée, quatre vis en croix aux coins, un bas de coque en trapèze avec deux trous de guidage et deux ouvertures, une fenêtre vitrée (reflet sur la vitre) laissant voir deux bobines métalliques à moyeu dentelé et des pelotes de ruban à spires, et sur l'étiquette en papier (bandeau de couleur, lignes d'écriture bleu pâle, pastille « A » dans le coin) le titre de l'album et le nom de l'artiste écrits à la main au stylo bleu (le texte court sur toute l'étiquette : le début des lignes disparaît derrière la pochette, c'est voulu ; un titre ou un artiste très long se réduit puis se tronque sans déborder de l'étiquette), deux bobines à dents qui tournent et un ruban qui passe lentement d'une bobine à l'autre (la pelote de gauche rétrécit, celle de droite grossit, puis l'inverse) ; la coque se teinte dès l'ouverture si la couleur est déjà connue, sinon dès le chargement de la pochette. Un disque absent de la collection et de la wantlist reste en vinyle. Disque, bobines et ruban fixes avec Réduire les animations ; lisible en clair et en sombre (règles de choix du support et de teinte couvertes par PhysicalMediaTests).

- [ ] Passé — date / appareil / version :

### Q30 — Écoute sur platine : démarrage progressif, bras de lecture et arrêt en douceur `AUDIT` `AUTO`

**Conditions** : Un album en vinyle, un en CD, un en cassette ; Réduire les animations désactivé puis activé ; écoute lancée depuis la fiche, puis feuille ouverte depuis le mini-lecteur.

**Étapes** :

1. Ouvrir la feuille d'écoute d'un vinyle et observer les 2 premières secondes.
2. Toucher « Arrêter l'écoute » et observer jusqu'à la fermeture.
3. Refaire avec un CD, puis une cassette.
4. Terminer l'écoute depuis la Live Activity ou l'autre écran pendant que la feuille est ouverte.
5. Refaire avec Réduire les animations activé.

**Résultat attendu** : Vinyle : le disque démarre en accélérant (environ 1,3 s) ; le bras de lecture, qui pend à droite du disque, se pose sur les sillons après un court instant avec un léger haptique. À « Arrêter l'écoute » : le bras se relève (haptique léger) pendant que le disque ralentit jusqu'à l'immobilité (environ 1,6 s), puis la feuille se ferme (environ 2 s au total) ; l'écoute, elle, s'arrête immédiatement (Live Activity et journal). CD : même démarrage et même ralentissement, sans bras. Cassette : bobines qui accélèrent puis ralentissent, ruban qui ne bouge plus une fois les bobines arrêtées, sans bras. Écoute terminée ailleurs : même arrêt en douceur avant fermeture. Le bouton est désactivé pendant l'arrêt. Avec Réduire les animations : disque immobile, bras posé d'emblée, fermeture presque immédiate. Rotation fluide, y compris sur un petit écran (le bras déborde un peu dans la marge sans être coupé) (calcul du mouvement couvert par SpinProfileTests).

- [ ] Passé — date / appareil / version :

### Q31 — Réglages : état du compte Apple Music sous la case de connexion `AUDIT` `AUTO`

**Conditions** : Compte Apple Music avec abonnement, puis un compte sans abonnement ; autorisation Musique accordée puis refusée dans les réglages de l'iPhone.

**Étapes** :

1. Réglages > Écoute et Apple Music : activer « Connecter mon compte Apple Music » et accepter l'invite.
2. Observer la ligne sous la case, pendant puis après la vérification.
3. Refaire avec un compte sans abonnement.
4. Refuser l'accès Musique dans les réglages de l'iPhone, revenir dans l'app.
5. Souscrire un abonnement dans l'app Musique, revenir dans Réglages.

**Résultat attendu** : Pendant la vérification : « Vérification de l'abonnement… » avec un indicateur, jamais « aucun abonnement » par erreur. Avec abonnement : coche verte « Abonnement Apple Music actif : lecture complète des titres. ». Sans abonnement : « Aucun abonnement Apple Music actif : seuls les extraits de 30 s sont lus. » avec un triangle orange. Accès refusé : « Accès à Apple Music refusé… » avec un triangle orange. L'état est relu à chaque ouverture de la page (abonnement souscrit entre-temps pris en compte). Case décochée : aucune ligne d'état. Chaque état est lisible sans la couleur (règle de choix couverte par AppleMusicAccountStatusTests).

- [ ] Passé — date / appareil / version :

### Q32 — Stop dans la fenêtre de lecture : retour en douceur dans le mini-lecteur `AUDIT`

**Conditions** : Un extrait (sans abonnement) puis un morceau complet (abonnement Apple Music) ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Lancer un titre depuis une fiche, toucher le mini-lecteur pour ouvrir la fenêtre de lecture.
2. Toucher Stop.
3. Recommencer avec un morceau complet, puis avec Réduire les animations.

**Résultat attendu** : 2 : la fenêtre se réduit vers le mini-lecteur (même mouvement qu'à la fermeture par glissé), le son de l'extrait baisse en fondu, puis le mini-lecteur s'efface de la barre d'onglets. Aucune coupure brutale. 3 : morceau complet arrêté à la fin du mouvement (sans fondu) ; avec Réduire les animations, fermeture en fondu et arrêt immédiat. Relancer un titre aussitôt après : il joue à plein volume.

- [ ] Passé — date / appareil / version :

### Q33 — Disparition animée du mini-lecteur ; feuille platine qui se réduit dans le mini-lecteur `AUDIT`

**Conditions** : Barre d'onglets normale puis réduite (défiler) ; Réduire les animations désactivé puis activé.

**Étapes** :

1. Lancer un titre Apple Music, toucher Stop dans le mini-lecteur.
2. Lancer une écoute sur platine, toucher Stop dans le mini-lecteur.
3. Relancer une écoute sur platine, ouvrir la feuille depuis le mini-lecteur, la fermer en glissant, puis la rouvrir et toucher « Arrêter l'écoute ».
4. Recommencer 1 à 3 avec la barre d'onglets réduite.

**Résultat attendu** : 1-2 : le mini-lecteur disparaît d'un bloc, capsule et contenu ensemble (titre et barre de progression affichés jusqu'au bout, sans capsule vide). 3 : la feuille sort du mini-lecteur et s'y réduit en se fermant ; avec Arrêter, le disque ralentit, la feuille rentre dans le mini-lecteur, puis le mini-lecteur s'efface. Relancer aussitôt une lecture : le mini-lecteur réapparaît avec le nouveau titre. Avec Réduire les animations : fondus seulement.

- [ ] Passé — date / appareil / version :

<a id="famille-r"></a>

## R — Mise à jour & migration de données

> Installer la nouvelle version PAR-DESSUS la version précédente (App Store ou TestFlight), sans supprimer l'app, pour vérifier la reprise des données existantes.

### R1 — Mise à jour avec une session Discogs existante `AUDIT`

**Conditions** : Version précédente (App Store/TestFlight) installée et connectée. Installer la nouvelle version PAR-DESSUS, sans supprimer l'app.

**Étapes** :

1. Lancer la nouvelle version.
2. Verrouiller l'iPhone 10 minutes puis laisser une vérification d'alertes se produire (ou F13).

**Résultat attendu** : L'utilisateur reste connecté ; les identifiants sont migrés (lisibles même écran verrouillé) ; aucune reconnexion demandée.

- [ ] Passé — date / appareil / version :

### R2 — Mise à jour avec des actions hors ligne en attente `AUDIT` `LIMITE`

**Conditions** : Version précédente : actions effectuées en mode avion (ajout, retrait, champ modifié) non encore synchronisées.

**Étapes** :

1. Installer la nouvelle version par-dessus.
2. Rétablir le réseau.

**Résultat attendu** : Les anciennes actions en attente sont rejouées sur le compte connecté ; un ajout depuis la wantlist mis en file par l'ancienne version arrive dans le bon dossier.

- [ ] Passé — date / appareil / version :

### R3 — Mise à jour avec synchro iCloud active `AUDIT` `PREMIUM` `2 APPAREILS`

**Conditions** : Synchro active sur 2 appareils avec l'ancienne version.

**Étapes** :

1. Mettre à jour un seul des deux appareils.
2. Modifier des tags de chaque côté.

**Résultat attendu** : La synchro continue dans les deux sens entre ancienne et nouvelle version ; pas de nouvelle poussée initiale complète à chaque lancement.

- [ ] Passé — date / appareil / version :

### R4 — Mise à jour avec des alertes wantlist existantes `AUDIT` `PREMIUM`

**Conditions** : Alertes créées avec l'ancienne version, dont une déjà notifiée.

**Étapes** :

1. Mettre à jour.
2. Lancer une vérification (F13).

**Résultat attendu** : Les alertes sont conservées ; l'alerte déjà notifiée ne renvoie pas de notification tant que le prix ne baisse pas.

- [ ] Passé — date / appareil / version :

### R5 — Mise à jour depuis une très ancienne version (tags par release) `LIMITE`

**Conditions** : Données créées avant l'isolation par compte et avant les tags par exemplaire.

**Étapes** :

1. Mettre à jour vers la nouvelle version et ouvrir la Collection.

**Résultat attendu** : Les anciens tags sont repris sur les bons exemplaires, une seule fois, pour le premier compte connecté ; aucun doublon.

- [ ] Passé — date / appareil / version :

### R6 — Mise à jour hors ligne `LIMITE`

**Conditions** : Version précédente avec cache hors ligne complet ; mode avion activé avant la mise à jour.

**Étapes** :

1. Installer la nouvelle version (via Xcode) en restant en mode avion.
2. Parcourir Collection, Wantlist, Stats.

**Résultat attendu** : Toutes les données hors ligne restent consultables après la mise à jour ; aucune perte du cache local.

- [ ] Passé — date / appareil / version :

### R7 — Réinstallation : plus de connexion fantôme ; mise à jour : toujours connecté `AUDIT` `AUTO`

**Conditions** : Compte Discogs connecté sur une build de la version précédente.

**Étapes** :

1. Installer la nouvelle build par-dessus (mise à jour) et lancer.
2. Supprimer l'app, la réinstaller et lancer.

**Résultat attendu** : 1 : toujours connecté au même compte, collection et réglages intacts. 2 : l'écran d'accueil s'affiche, déconnecté (auparavant l'app se croyait connectée, sans ses données). Règle couverte par SecurityHardeningTests.

- [ ] Passé — date / appareil / version :

### R8 — Prix d'achat et état du disque gardés dans l'app (reprise des champs Discogs) `AUDIT` `AUTO`

**Conditions** : Compte déjà configuré avec un champ « Prix d'achat » et un champ « Media Condition » (valeurs saisies sur plusieurs albums, dont une valeur illisible comme « Neuf »), installé depuis la version précédente ; un second compte sans champ configuré.

**Étapes** :

1. Ouvrir l'app et attendre la fin du chargement de la Collection ; ouvrir Stats > « Investi vs cote actuelle ».
2. Ouvrir « Mon exemplaire » d'un album à prix et état connus, puis la fiche « Prix et état ».
3. Modifier le prix puis l'état d'un album, fermer, rouvrir.
4. Collection > ··· > Filtres : « Sans prix d'achat » puis « Sans état du média ».
5. Réglages > Export : produire le PDF et le CSV.
6. Mode avion : modifier le prix d'un album, puis revenir en ligne.
7. Se déconnecter, se reconnecter avec le même compte, puis avec le second compte.
8. Réglages > Supprimer mes données (compte de test).

**Résultat attendu** : 1 : le total investi est identique à celui de la version précédente. 2 : prix et état affichés comme avant. 3 : les nouvelles valeurs sont conservées, y compris après relance, et partent sur Discogs comme avant. 4 : les filtres suivent les valeurs enregistrées. 5 : les exports reprennent les mêmes valeurs. 6 : la valeur reste affichée hors ligne et part au retour du réseau. 7 : chaque compte retrouve ses valeurs, sans mélange. 8 : les données du compte sont effacées. Règles couvertes par CopyDetailsTests ; la reprise sur l'appareil réel est à confirmer ici.

- [ ] Passé — date / appareil / version :

<a id="famille-s"></a>

## S — Langues, libellés & traductions

### S1 — Interface entièrement en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais (Réglages iOS → Général → Langue et région), utilisateur connecté, compte premium.

**Étapes** :

1. Parcourir les 5 onglets, une fiche album, les Réglages (toutes les sous-pages), le paywall et les feuilles d'édition (tags, prix d'achat, alerte prix).
2. Déclencher quelques messages : ajout/retrait, export sans connexion, recherche hors ligne.

**Résultat attendu** : Aucun texte de l'app en français (seules les données Discogs, comme les titres, genres ou notes, restent dans leur langue d'origine) ; pas de clé brute du type « %lld » visible.

- [ ] Passé — date / appareil / version :

### S2 — Lexique : écoute sur platine ≠ lecture Apple Music (français) `AUDIT`

**Conditions** : Fiche d'un album de la collection avec des titres reconnus par Apple Music.

**Étapes** :

1. Toucher « J'écoute » puis observer le mini-lecteur, la Live Activity et la pastille de la fiche.
2. Arrêter l'écoute (balayage dans la Collection, bouton de la Live Activity).
3. Lancer un titre Apple Music et observer le mini-lecteur.

**Résultat attendu** : Platine : « J'écoute ce disque sur la platine », « Écoute en cours sur la platine », badge « Sur platine », « Arrêter l'écoute ». Apple Music : « Lecture sur Apple Music », bouton « Lire … sur Apple Music ». Plus aucun « Stop » ni « Touchez Lecture pour lancer ».

- [ ] Passé — date / appareil / version :

### S3 — Lexique en anglais : Listen (platine) / Play (Apple Music) `AUDIT`

**Conditions** : iPhone en anglais.

**Étapes** :

1. Refaire les étapes de S2.
2. Ouvrir Stats → classement d'écoute, et Réglages → arrêt automatique.

**Résultat attendu** : Platine : « I'm Listening », « Listening on the turntable », « Stop Listening », « Listened N times », « Turntable Listening Charts », « Automatic Listening Stop ». Apple Music : « Playing on Apple Music », « Play … on Apple Music ». Jamais « Playing » pour la platine.

- [ ] Passé — date / appareil / version :

### S4 — Les lectures Apple Music ne comptent pas comme des écoutes `AUDIT` `PREMIUM`

**Conditions** : Album avec un compteur « Écouté N fois » connu ; abonnement Apple Music actif.

**Étapes** :

1. Écouter un titre complet de cet album via Apple Music.
2. Revenir sur la fiche puis ouvrir Stats → palmarès.

**Résultat attendu** : Le compteur « Écouté N fois », « Dernière écoute » et le palmarès sont inchangés ; le paywall et les Réglages Apple Music précisent bien que les lectures Apple Music ne sont pas comptées.

- [ ] Passé — date / appareil / version :

### S5 — Singulier / pluriel en français `AUDIT` `LIMITE`

**Conditions** : Disposer de cas à 0, 1 et 2 : album écouté 1 fois, release avec 1 exemplaire en vente, dossier à 1 élément, tag posé sur 1 disque.

**Étapes** :

1. Observer : « Écouté 1 fois », « 1 exemplaire en vente », sous-titre du dossier « 1 élément », suppression du tag (« retiré de 1 disque »), scan par lot avec 1 disque ajouté, essai gratuit du paywall.
2. Refaire avec 2 (ou plus).

**Résultat attendu** : Accord correct partout (« 1 écoute » / « 2 écoutes », « 0 disque »…) ; aucune forme bancale du type « 1 disques » ou « exemplaire(s) ».

- [ ] Passé — date / appareil / version :

### S6 — Singulier / pluriel en anglais `AUDIT` `LIMITE`

**Conditions** : iPhone en anglais ; mêmes cas qu'en S5.

**Étapes** :

1. Refaire les observations de S5.

**Résultat attendu** : « 1 listen » / « 2 listens », « 1 copy for sale » / « 3 copies for sale », « 0 records », « 1 item » / « 5 items », « 7-day free trial ». Aucun nombre mal accordé.

- [ ] Passé — date / appareil / version :

### S7 — Tutoiement homogène `AUDIT`

**Conditions** : iPhone en français.

**Étapes** :

1. Ouvrir les confirmations et messages : déconnexion, suppression de compte, suppression et fusion de tag, export sans connexion, téléchargement hors ligne en 4G/5G, alerte prix sans notification, paywall, autorisation caméra (premier scan).

**Résultat attendu** : Toute l'app tutoie l'utilisateur (« Veux-tu vraiment… », « Connecte-toi… », « Obtiens un accès complet ») ; plus aucun « vous », « votre » ni « Touchez ».

- [ ] Passé — date / appareil / version :

### S8 — Messages d'erreur, notifications et sous-titres traduits `AUDIT` `PREMIUM`

**Conditions** : iPhone en anglais.

**Étapes** :

1. Provoquer une erreur Discogs (Network Link Conditioner « 100% Loss ») pendant un ajout.
2. Laisser une alerte prix se déclencher (notification).
3. Lancer un export PDF/CSV et un téléchargement hors ligne, puis observer leurs sous-titres de progression.

**Résultat attendu** : Toasts, alertes, notification (« 🎯 Wantlist Deal! ») et textes de progression (« Generating document… », « Downloading collection (page …) ») sont en anglais.

- [ ] Passé — date / appareil / version :

### S9 — Formats régionaux (dates, nombres, prix) `AUDIT` `LIMITE`

**Conditions** : Tester en anglais (région États-Unis) puis en français (région France).

**Étapes** :

1. Observer les dates : ajout à la collection, dernière synchro, sections « Date d'ajout » du tri, déclaration PDF.
2. Observer les prix : cote, prix d'achat, abonnements du paywall.

**Résultat attendu** : Dates et mois affichés selon la langue/région de l'appareil (plus de mois forcés en français) ; prix d'abonnement fournis par l'App Store dans la devise locale.

- [ ] Passé — date / appareil / version :

### S10 — Nom de l'app et autorisations système `AUDIT`

**Conditions** : Installation fraîche, en français puis en anglais.

**Étapes** :

1. Observer le nom sous l'icône.
2. Déclencher l'autorisation caméra (scan) et l'autorisation Apple Music (Réglages → Connecter mon compte Apple Music).

**Résultat attendu** : Nom « Spinfolio » dans les deux langues (pas « Spinlog ») ; textes d'autorisation tutoyés en français, traduits en anglais, et celui d'Apple Music mentionne la lecture des titres.

- [ ] Passé — date / appareil / version :

### S11 — Widgets et Live Activity en anglais `AUDIT`

**Conditions** : iPhone en anglais, widget « Album du jour » installé.

**Étapes** :

1. Observer le widget.
2. Lancer une écoute sur platine et observer la Live Activity (écran verrouillé, Dynamic Island).

**Résultat attendu** : « Album of the Day », « Listening on the turntable » et bouton « Stop Listening » ; aucun texte français.

- [ ] Passé — date / appareil / version :

### S12 — Libellés longs et grandes tailles de texte `AUDIT` `LIMITE`

**Conditions** : Taille du texte au maximum (accessibilité), en anglais puis en français.

**Étapes** :

1. Parcourir le mini-lecteur, le menu contextuel d'une pochette, les boutons de la fiche album, le paywall et les cartes Stats.

**Résultat attendu** : Les libellés plus longs (« Stop Listening on the Turntable », « I'm listening to this record on the turntable ») passent à la ligne ou se tronquent proprement, sans chevauchement.

- [ ] Passé — date / appareil / version :

### S13 — Changement de langue sans perte de réglages `AUDIT` `LIMITE`

**Conditions** : Thème « Sombre », tri de collection et filtre artiste personnalisés, en français.

**Étapes** :

1. Passer l'iPhone en anglais puis rouvrir l'app.
2. Vérifier les réglages puis revenir en français.

**Résultat attendu** : Thème, tri, filtres et personnalisations conservés ; leurs libellés suivent la langue (« Dark » / « Sombre », « Sort: … ») sans retour aux valeurs par défaut.

- [ ] Passé — date / appareil / version :

### S14 — Nouveaux textes en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Parcourir la démo (entrée, messages de blocage, sortie), la gestion des dossiers, le scan par lot (fermeture, hors ligne), la Live Activity terminée.

**Résultat attendu** : Tout est en anglais, avec les bons pluriels (« Your 1 scanned barcode is saved… », suppression d'un dossier vide ou non).

- [ ] Passé — date / appareil / version :

<a id="famille-t"></a>

## T — Guide de l'app (Réglages > Guide)

### T1 — Accéder au guide depuis Réglages `AUDIT`

**Conditions** : Compte connecté, démo ou non connecté.

**Étapes** :

1. Ouvrir l'onglet Réglages.
2. Repérer la ligne « Guide » tout en haut (sous la bannière Premium si elle est affichée).
3. Toucher « Guide ».

**Résultat attendu** : La page Guide liste 8 sections : Premiers pas, Collection et Wantlist, Fiche d'un disque, Statistiques, Écoute sur platine, Rangement, Alertes de prix, Réglages. Chaque page de section affiche ses cartes (3 à 6), chacune avec un visuel, un titre et une phrase, sans appel réseau ni écran vide.

- [ ] Passé — date / appareil / version :

### T2 — Visuels et textes des cartes « Premiers pas » `AUDIT`

**Conditions** : Compte non Premium.

**Étapes** :

1. Parcourir les 4 cartes.
2. Comparer chaque visuel à l'écran réel : boutons de connexion (écran de connexion d'un onglet), barre de Recherche avec l'icône de scan entourée, boutons « Collection » / « Wantlist » (fiche d'un disque), icône de scan par lot.
3. Déplier « Détails » sur chaque carte.
4. Toucher la pastille Premium et le badge « Compte Discogs requis ».

**Résultat attendu** : Chaque visuel ressemble à l'écran qu'il représente (libellés, icônes, couleurs du thème, clair et sombre). « Détails » montre 2 étapes au plus et une astuce. « Scan par lot » porte la pastille Premium, « Ajouter un disque » le badge « Compte Discogs requis » ; aucun toucher sur ces badges n'ouvre le paywall.

- [ ] Passé — date / appareil / version :

### T3 — Bouton « Essayer » `AUDIT` `AUTO`

**Conditions** : Réglages ouvert sur une fiche du guide.

**Étapes** :

1. Sur la carte « Ajouter un disque », toucher « Essayer ».
2. Revenir dans Réglages (le guide est toujours ouvert).
3. Sur la carte « Se connecter à Discogs », toucher « Essayer ».

**Résultat attendu** : Le premier bouton ouvre l'onglet Recherche. Le second ramène à la racine de Réglages (liste des comptes visible), sans rester sur la page du guide. Retour léger au toucher.

- [ ] Passé — date / appareil / version :

### T4 — Re-tap sur l'onglet Réglages depuis le guide `AUDIT`

**Conditions** : Guide ouvert, avec puis sans abonnement Premium.

**Étapes** :

1. Ouvrir Réglages > Guide > Premiers pas.
2. Toucher une fois l'onglet Réglages.
3. Toucher une seconde fois l'onglet Réglages.

**Résultat attendu** : Le premier toucher revient à la racine de Réglages, le second remonte tout en haut : la ligne « Guide » est visible (bannière Premium en premier pour un non abonné).

- [ ] Passé — date / appareil / version :

### T5 — Guide sans réseau, déconnecté et en démo `AUDIT` `LIMITE`

**Conditions** : Mode avion ; tester déconnecté, puis en démo.

**Étapes** :

1. Ouvrir le guide hors connexion.
2. Ouvrir « Premiers pas » et lire les fiches.
3. Répéter en mode démo.

**Résultat attendu** : Le guide reste entièrement lisible, sans message d'erreur ni bannière hors ligne : il ne dépend d'aucune donnée réseau ni d'aucun compte.

- [ ] Passé — date / appareil / version :

### T6 — Guide en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Ouvrir Réglages > Guide > Getting Started.
2. Lire les 4 cartes et déplier « Details ».

**Résultat attendu** : Titres, phrases, étapes, astuces, badge « Discogs account required » et bouton « Try It » sont en anglais ; les visuels et les boutons cités correspondent à l'interface anglaise (« Sign In », « In Collection », « Exit Demo Mode »…).

- [ ] Passé — date / appareil / version :

### T7 — Guide avec VoiceOver et grand texte `AUDIT`

**Conditions** : VoiceOver activé, puis taille de texte maximale (accessibilité).

**Étapes** :

1. Parcourir une page de section au rotor « En-têtes ».
2. Se placer sur un bouton « Essayer » et sur « Détails ».
3. Passer la taille de texte au maximum.

**Résultat attendu** : Chaque titre de carte est un en-tête ; les visuels sont ignorés par VoiceOver (le texte porte le sens) ; « Essayer » annonce le titre de sa carte ; « Détails » annonce son état déplié ou replié. En grand texte rien n'est tronqué ni chevauché.

- [ ] Passé — date / appareil / version :

### T8 — Textes des sections « Collection et Wantlist » et « Fiche d'un disque » `AUDIT`

**Conditions** : Compte avec une collection, au moins un tag, plusieurs dossiers ; écran de Collection puis fiche d'un disque en collection.

**Étapes** :

1. Lire les 4 cartes de « Collection et Wantlist » en dépliant « Détails ».
2. Suivre chaque étape dans la Collection : menu « ··· » (Affichage, Tri, Filtres, Dossier, Sélectionner), barre à droite, bouton « Disque au hasard », glisser ou maintenir une ligne.
3. Lire les 4 cartes de « Fiche d'un disque » et suivre chaque étape sur une fiche : maintenir « En collection », « Modifier » sur un exemplaire, « Tags de l'exemplaire », étoiles de « Ma note de la release », Réglages > « Prix d'achat et état ».

**Résultat attendu** : Chaque menu, bouton et section cité existe à l'identique à l'écran. Aucune étape ne décrit un geste ou un écran absent. « Ranger » est bien réservé au Premium, et les tags ne sont pas visibles sur discogs.com. La carte « Trois affichages » ne renvoie pas vers Réglages : le mode liste/mosaïque/carrousel est retenu séparément pour la Collection et la Wantlist (le « Mode d'affichage » de Réglages est le thème clair/sombre).

- [ ] Passé — date / appareil / version :

### T9 — Visuels des sections « Collection et Wantlist » et « Fiche d'un disque » `AUDIT`

**Conditions** : Thèmes clair et sombre, puis une palette Premium.

**Étapes** :

1. Comparer les maquettes aux écrans réels : trois affichages, tri avec barre d'index, recherche et puces de filtre, actions de ligne, titres, exemplaires, tags et étoiles, prix et cote.
2. Passer en thème sombre, puis changer de palette.
3. Taille de texte maximale.

**Résultat attendu** : Les maquettes ressemblent aux écrans réels (couleurs, icônes, libellés) et suivent le thème et la palette. Aucune maquette ne déborde sur sa voisine ni ne se tronque, y compris en grand texte.

- [ ] Passé — date / appareil / version :

### T10 — Sections « Collection et Wantlist » et « Fiche d'un disque » en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Ouvrir Settings > Guide > Collection and Wantlist, puis A Record’s Page.
2. Lire toutes les cartes et déplier « Details ».

**Résultat attendu** : Tout est en anglais, et les menus et boutons cités correspondent à ceux de l'interface anglaise (« Display », « Sort », « Filters », « Select », « Edit », « Shelve », « Random Record », « Copy Tags », « My Release Rating », « Purchase Price and Condition »).

- [ ] Passé — date / appareil / version :

### T11 — Textes de la section « Statistiques » `AUDIT`

**Conditions** : Compte avec une collection, un prix d'achat renseigné sur quelques exemplaires et quelques écoutes ; avec puis sans Premium.

**Étapes** :

1. Lire les 4 cartes de « Statistiques » en dépliant « Détails ».
2. Suivre chaque étape dans l'onglet Stats : tuiles « Collection » et « Wantlist », « Estimation de la collection », toucher une portion ou une barre, bascule années/décennies dans « Sorties originales », « Investi vs Cote actuelle », « Tops & Palmarès ».
3. Vérifier les badges d'accès des cartes.

**Résultat attendu** : Chaque titre de section et chaque geste cité existent à l'identique à l'écran. « Plus-value » et « Palmarès d'écoute » portent la pastille Premium et sont verrouillés sans abonnement ; les deux autres cartes portent « Compte Discogs requis ». Hors ligne, seuls les compteurs et la cote sont indisponibles.

- [ ] Passé — date / appareil / version :

### T12 — Visuels de la section « Statistiques » `AUDIT`

**Conditions** : Thèmes clair et sombre, puis une palette Premium ; taille de texte maximale.

**Étapes** :

1. Comparer les maquettes (3 compteurs, anneau et histogramme, total investi / cote / plus-value, podium) à l'onglet Stats.
2. Passer en thème sombre, changer de palette, puis agrandir le texte.

**Résultat attendu** : Les maquettes ressemblent aux écrans réels et suivent le thème et la palette ; les trois tuiles de compteurs ont la même hauteur ; la plus-value positive est en vert lisible ; rien ne se tronque ni ne se chevauche.

- [ ] Passé — date / appareil / version :

### T13 — Section « Statistiques » en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Ouvrir Settings > Guide > Statistics.
2. Lire les 4 cartes et déplier « Details ».

**Résultat attendu** : Tout est en anglais ; les noms cités correspondent à l'interface anglaise (« Recent Additions », « Original Releases », « Collection Valuation », « Invested vs Current Value », « Top Charts », « I'm Listening »).

- [ ] Passé — date / appareil / version :

### T14 — Textes de la section « Écoute sur platine » `AUDIT`

**Conditions** : Compte avec une collection ; Live Activités autorisées ; widget « Album du jour » ajoutable ; avec puis sans abonnement Apple Music.

**Étapes** :

1. Lire les 4 cartes de la section en dépliant « Détails ».
2. Suivre chaque étape : « J'écoute » (fiche et glissé d'une ligne), mini-lecteur puis feuille « Écoute sur platine », durée maximale dans Réglages, « Connecter mon compte Apple Music », ajout du widget « Album du jour » en petit, moyen et grand format.
3. Relancer une écoute sur un autre disque pendant la première.

**Résultat attendu** : Chaque libellé et chaque geste cité existent à l'identique. La nouvelle écoute interrompt la précédente ; l'écoute s'arrête à la fin de la durée choisie ; les lectures Apple Music ne s'ajoutent pas au compteur « Écouté N fois » ; le widget est disponible sans abonnement Premium et change de disque chaque jour.

- [ ] Passé — date / appareil / version :

### T15 — Visuels de la section « Écoute sur platine » `AUDIT`

**Conditions** : Thèmes clair et sombre, puis une palette Premium ; taille de texte maximale.

**Étapes** :

1. Comparer les maquettes (boutons d'écoute et pastille, bandeau de Live Activity, réglage Apple Music, widget) aux écrans réels.
2. Passer en thème sombre, changer de palette, puis agrandir le texte.

**Résultat attendu** : Les maquettes ressemblent aux écrans réels et suivent le thème et la palette ; la ligne Apple Music passe à deux lignes sans se tronquer ; rien ne déborde.

- [ ] Passé — date / appareil / version :

### T16 — Section « Écoute sur platine » en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Ouvrir Settings > Guide > Listening on the turntable.
2. Lire les 4 cartes et déplier « Details ».

**Résultat attendu** : Tout est en anglais ; les noms cités correspondent à l'interface anglaise (« I'm Listening », « Turntable Listening & Live Activity », « Connect My Apple Music Account », « Album of the Day »).

- [ ] Passé — date / appareil / version :

### T17 — Textes de la section « Rangement » `AUDIT` `PREMIUM`

**Conditions** : Compte Premium avec des disques de plusieurs artistes (dont « The … » et un solo) et plusieurs supports ; puis compte non Premium.

**Étapes** :

1. Lire les 4 cartes de « Rangement » en dépliant « Détails ».
2. Suivre chaque étape : glisser une ligne et « Ranger », « Rangement physique » sur une fiche, « Règle de rangement dans le meuble » dans Réglages, « Ignorer les articles », « Trier par nom de famille », « Personnaliser le tri des artistes », « Limiter au dossier Discogs ».
3. Ajouter un disque à la collection et observer le guide de rangement.

**Résultat attendu** : Chaque libellé cité existe à l'identique. Sans Premium, « Ranger » ouvre le verrou et non le guide. Le guide s'ouvre après un ajout, montre le disque central entre ses deux voisins, et sépare vinyles 12/10/7 pouces, CD et cassettes ; « Personnaliser le tri des artistes » n'apparaît qu'avec « Trier par nom de famille » actif.

- [ ] Passé — date / appareil / version :

### T18 — Visuels de la section « Rangement » `AUDIT`

**Conditions** : Thèmes clair et sombre, puis une palette Premium ; taille de texte maximale.

**Étapes** :

1. Comparer les maquettes (disque entre ses voisins avec N° et jauge, quatre règles, noms d'artistes, supports et badge de dossier) au guide de rangement et aux Réglages.
2. Passer en thème sombre, changer de palette, puis agrandir le texte.

**Résultat attendu** : Les maquettes ressemblent aux écrans réels et suivent le thème et la palette ; les règles de classement et les puces de supports ne se tronquent pas en grand texte.

- [ ] Passé — date / appareil / version :

### T19 — Section « Rangement » en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Ouvrir Settings > Guide > Shelving.
2. Lire les 4 cartes et déplier « Details ».

**Résultat attendu** : Tout est en anglais ; les noms cités correspondent à l'interface anglaise (« Shelve », « Physical Shelving », « Shelving Rule », « Ignore Articles (The...) », « Sort by Last Name », « Customize Artist Sorting », « Limit to Discogs Folder »).

- [ ] Passé — date / appareil / version :

### T20 — Textes de la section « Alertes de prix » `AUDIT` `PREMIUM`

**Conditions** : Compte Premium avec des disques en wantlist ; notifications autorisées, puis refusées ; compte non Premium.

**Étapes** :

1. Lire les 3 cartes de « Alertes de prix » en dépliant « Détails ».
2. Dans la Wantlist, glisser ou maintenir une ligne : « Définir une alerte prix » ; saisir « Prix maximum » ; toucher un état de « Cote moyenne récente par état » ; utiliser -10 %, -20 %, -30 % ; « OK ».
3. Vérifier la pastille « ≤ prix » sur la ligne, puis son passage en vert quand l'alerte se déclenche.

**Résultat attendu** : Chaque libellé cité existe à l'identique. Un état touché remplit le prix cible ; la pastille apparaît sur la ligne. Sans notification autorisée, l'alerte propose « Ouvrir Réglages » ou « Continuer quand même ». Sans Premium, la fonction est verrouillée.

- [ ] Passé — date / appareil / version :

### T21 — Textes de la section « Réglages » `AUDIT` `PREMIUM`

**Conditions** : Compte Premium puis non Premium ; au moins un tag et deux dossiers ; démo testée à part.

**Étapes** :

1. Lire les 6 cartes de « Réglages » en dépliant « Détails ».
2. Suivre chaque étape : « Mode hors ligne » (« Télécharger toute ma collection », « Synchro auto en Wi-Fi »), « Synchroniser avec iCloud », « Mode d'affichage » et « Couleur du thème », « Exporter la collection en CSV » et « Déclaration de collection (PDF) », « Gestion des tags » et « Gestion des dossiers », profil Discogs, « Se déconnecter », « Supprimer mon compte… ».
3. Répéter en mode démo pour iCloud.

**Résultat attendu** : Chaque libellé et chaque geste cité existent à l'identique. Pendant la démo, iCloud est coupé. Sans Premium, hors ligne, iCloud, export et palettes sont verrouillés mais le thème Signature et le mode clair/sombre restent disponibles.

- [ ] Passé — date / appareil / version :

### T22 — Visuels des sections « Alertes de prix » et « Réglages » `AUDIT`

**Conditions** : Thèmes clair et sombre, puis une palette Premium ; taille de texte maximale.

**Étapes** :

1. Comparer les maquettes (pastille d'alerte, cotes par état, alerte déclenchée en vert, archive locale, iCloud, palettes, exports, tags et dossier, compte) aux écrans réels.
2. Passer en thème sombre, changer de palette, puis agrandir le texte.

**Résultat attendu** : Les maquettes ressemblent aux écrans réels et suivent le thème ; la pastille d'alerte et les libellés d'export ne se tronquent pas en grand texte.

- [ ] Passé — date / appareil / version :

### T23 — Sections « Alertes de prix » et « Réglages » en anglais `AUDIT`

**Conditions** : iPhone réglé en anglais.

**Étapes** :

1. Ouvrir Settings > Guide > Price Alerts, puis Settings.
2. Lire toutes les cartes et déplier « Details ».

**Résultat attendu** : Tout est en anglais ; les noms cités correspondent à l'interface anglaise (« Set Price Alert », « Maximum price », « Offline Mode », « Auto-Sync Over Wi-Fi », « Sync with iCloud », « Theme Color », « Tag Management », « Folder Management », « Sign Out », « Delete My Account… »).

- [ ] Passé — date / appareil / version :

### T24 — Page « Comment ça fonctionne ? » du suivi de plus-value : contenu `AUDIT`

**Conditions** : Compte connecté, avec puis sans champ « prix d'achat » ni « état du disque » créés sur Discogs.

**Étapes** :

1. Réglages > Suivi de plus-value > « Comment ça fonctionne ? ».
2. Lire « Le principe » (prix payé et état du disque → cote Discogs → plus-value), « Un exemple » et « Ta configuration ».
3. Déplier « Créer le champ prix d'achat » puis « Limites à connaître ».

**Résultat attendu** : Le schéma, l'exemple (20 € − 35 € = +15 €) et les détails repliés s'affichent. « Ta configuration » indique « Détecté » ou « À créer sur Discogs » pour le prix, « Détecté » ou « Non détecté : cote moyenne » pour l'état, et la devise par défaut. La page est lisible sans Premium (voir J33) et sans réseau.

- [ ] Passé — date / appareil / version :

### T25 — Page plus-value : corriger la configuration depuis la page `AUDIT`

**Conditions** : Compte sans champ « prix d'achat » détecté.

**Étapes** :

1. Sur la page, toucher « Choisir mes champs dans Réglages ».
2. Choisir un champ dans « Champ prix d'achat » puis revenir sur la page.
3. Toucher « Ouvrir les réglages de collection Discogs » et fermer la fenêtre.

**Résultat attendu** : Le bouton ramène à la racine de Réglages ; après le choix, « Champ prix d'achat » passe à « Détecté » et le bouton disparaît quand les deux champs sont définis. La fenêtre Discogs s'ouvre et se ferme sans perdre la page.

- [ ] Passé — date / appareil / version :

### T26 — Page plus-value en anglais, VoiceOver et grand texte `AUDIT`

**Conditions** : iPhone réglé en anglais ; VoiceOver activé ; taille de texte maximale.

**Étapes** :

1. Ouvrir Settings > Gain Tracking > page d'aide.
2. Parcourir la page avec VoiceOver, puis agrandir le texte.

**Résultat attendu** : Tout est en anglais (« How It Works », « An Example », « Your Setup », « Detected », « Not detected: average value »). VoiceOver lit chaque ligne de configuration d'un bloc (état en toutes lettres) et l'exemple comme une phrase ; rien ne se tronque en grand texte.

- [ ] Passé — date / appareil / version :

### T27 — Fiche « Plus-value » : accès à la page « Comment ça fonctionne ? » `AUDIT`

**Conditions** : Compte non Premium puis Premium ; Réglages > Guide > Statistiques ; aussi en démo.

**Étapes** :

1. Ouvrir la fiche « Plus-value » de la section Statistiques.
2. Toucher « Comment ça fonctionne ? ».
3. Faire retour, puis toucher « Essayer ».
4. Comparer avec la page ouverte depuis Réglages (ligne « Comment ça fonctionne ? » du suivi de plus-value).

**Résultat attendu** : Le bouton « Comment ça fonctionne ? » apparaît à côté de « Essayer » et ouvre, dans la pile de Réglages, la même page « Suivi de plus-value » (schéma, exemple, état de la configuration, détails), accessible sans Premium. Le retour ramène à la fiche du guide ; « Essayer » mène toujours à l'onglet Statistiques. Les deux boutons tiennent sur une ligne en taille de texte standard et passent sous eux en grande taille.

- [ ] Passé — date / appareil / version :

<a id="famille-u"></a>

## U — Grades et badges

### U1 — Réglages : badges près du nom et ligne « Mes grades » `AUDIT`

**Conditions** : Compte Discogs connecté avec une collection déjà fournie (ex. 120 disques) et des écoutes ; première ouverture de Réglages après la mise à jour.

**Étapes** :

1. Ouvrir Réglages.
2. Observer la ligne du compte (avatar, nom) et la ligne en dessous.
3. Toucher la ligne « Mes grades ».

**Résultat attendu** : Un ou deux badges (un par parcours) apparaissent à droite du nom, seulement pour les parcours où un grade est acquis ; la ligne « Mes grades » résume les grades (ex. « Passionné · Habitué ») et mène à la page. À la première évaluation, les grades déjà mérités sont attribués avec leur vraie date historique (date d'ajout du N-ième disque, horodatage de la N-ième écoute) et une seule carte « Bienvenue ! » présente le plus haut (voir U10). Sans aucun grade, aucun badge et le texte « Gagne ton premier grade en ajoutant un disque. ».

- [ ] Passé — date / appareil / version :

### U2 — Page « Mes grades » : grade acquis, jauge, liste et animations `AUDIT`

**Conditions** : Au moins un grade acquis par parcours ; Réduire les animations désactivé puis activé ; thème clair puis sombre.

**Étapes** :

1. Ouvrir « Mes grades ».
2. Observer les deux parcours (Collection, Écoute sur platine) : badge, nom du grade, « Obtenu le … », compteur et jauge.
3. Parcourir la liste des 7 grades de chaque parcours.
4. Refaire avec Réduire les animations activé.

**Résultat attendu** : Les sections arrivent en cascade, le badge rebondit, le nombre défile jusqu'à sa valeur et la jauge se remplit avec un reflet. Les badges obtenus tournent lentement (anneau, reflets, halo qui respire ; étincelles au dernier grade) ; les grades à venir sont grisés, immobiles, avec un cadenas et leur condition (« À 250 disques »). Le grade actuel porte la pastille « Grade actuel ». Avec Réduire les animations : tout est fixe et affiché directement. Lisible en clair et en sombre.

- [ ] Passé — date / appareil / version :

### U3 — Franchir un palier de collection : célébration `AUDIT`

**Conditions** : Compte avec 49 disques distincts, collection complète et synchronisée (ou 9 pour tester le palier des 10).

**Étapes** :

1. Ajouter un disque absent de la collection (recherche).
2. Attendre quelques secondes.
3. Toucher « Voir mes grades », puis refaire en touchant « Fermer » et en touchant à côté.

**Résultat attendu** : Quelques secondes après l'ajout, une carte s'ouvre par-dessus l'app : le badge arrive en tournant et rebondissant au milieu d'étincelles, avec un haptique de succès, le nom du grade et « Nouveau grade ! ». « Voir mes grades » ouvre la page dans Réglages ; « Fermer » et le toucher à côté la ferment. Le grade et sa date du jour apparaissent dans « Mes grades ». Aucune seconde célébration pour le même palier.

- [ ] Passé — date / appareil / version :

### U4 — Aucune rétrogradation quand on retire des disques `AUDIT` `AUTO`

**Conditions** : Compte au grade « Collectionneur » (50 disques ou plus).

**Étapes** :

1. Supprimer des disques jusqu'à passer sous 50.
2. Ouvrir Réglages puis « Mes grades ».
3. Rajouter un disque.

**Résultat attendu** : Le grade et sa date d'obtention restent inchangés ; la jauge vise le palier suivant d'après le nombre actuel. Repasser au-dessus de 50 ne déclenche aucune nouvelle célébration (règles couvertes par GradeRulesTests et GradeStoreTests).

- [ ] Passé — date / appareil / version :

### U5 — Écoutes sur platine : grade « Auditeur » à 10 écoutes, Apple Music exclu `AUDIT`

**Conditions** : Compte avec 9 écoutes sur platine enregistrées.

**Étapes** :

1. Lancer une lecture Apple Music d'un disque (sans écoute sur platine) et la laisser tourner.
2. Enregistrer une 10e écoute sur platine (« J'écoute ce disque sur la platine »).
3. Ouvrir « Mes grades ».

**Résultat attendu** : La lecture Apple Music ne change pas le compteur d'écoute ni le grade. La 10e écoute sur platine déclenche la célébration « Auditeur » (parcours Écoute sur platine), avec haptique et badge animé ; le compteur de « Mes grades » affiche 10.

- [ ] Passé — date / appareil / version :

### U6 — Synchro iCloud sur deux appareils : grades fusionnés, date la plus ancienne `AUDIT` `PREMIUM`

**Conditions** : Compte Premium avec synchro iCloud sur 2 appareils ; grades différents sur chacun.

**Étapes** :

1. Sur l'appareil A, franchir un palier de collection ; sur l'appareil B, un palier d'écoute.
2. Laisser iCloud synchroniser, rouvrir l'app sur les deux.
3. Comparer « Mes grades » sur A et B.

**Résultat attendu** : Les deux appareils affichent les deux grades. Pour un grade franchi des deux côtés, la date affichée est la plus ancienne. Aucun grade ne disparaît, quel que soit l'ordre de synchronisation, et un appareil qui reçoit un grade d'ailleurs ne le fête pas par un saut en bloc (synchro de masse).

- [ ] Passé — date / appareil / version :

### U7 — Comptes multiples, démo et suppression du compte `AUDIT`

**Conditions** : Deux comptes Discogs sur l'appareil ; mode démo disponible.

**Étapes** :

1. Noter les grades du compte A, se déconnecter, se connecter avec le compte B, noter ses grades, revenir au compte A.
2. Lancer la démo : regarder Réglages.
3. Supprimer les données du compte A (Réglages), se reconnecter.

**Résultat attendu** : Chaque compte garde ses propres grades et les retrouve en se reconnectant. La démo n'attribue ni n'affiche aucun grade (pas de badge, pas de célébration). Après suppression des données du compte, ses grades locaux sont effacés et recalculés en silence à la reconnexion.

- [ ] Passé — date / appareil / version :

### U8 — Collection partielle, périmée ou hors ligne : aucun grade attribué ni fêté `AUDIT` `AUTO`

**Conditions** : Grosse collection (plus de 250 disques) ; compte neuf sur l'appareil ; réseau coupé puis rétabli.

**Étapes** :

1. Se connecter hors ligne avec un cache de plus de 6 h ou une collection pas encore chargée : ouvrir « Mes grades ».
2. Rétablir le réseau et laisser la collection se synchroniser entièrement.
3. Revenir sur « Mes grades ».

**Résultat attendu** : Tant que la collection n'est pas complète et fraîche en cache, aucun grade de collection n'est attribué et le texte « Le comptage apparaîtra une fois ta collection synchronisée. » s'affiche. Une fois la synchro terminée, les grades mérités sont attribués d'un coup, en silence (règle couverte par GradeRulesTests).

- [ ] Passé — date / appareil / version :

### U9 — Accessibilité des grades : VoiceOver et grande taille de texte `AUDIT`

**Conditions** : VoiceOver activé puis taille de texte maximale.

**Étapes** :

1. Parcourir Réglages, la ligne du compte et « Mes grades » avec VoiceOver.
2. Parcourir la page « Mes grades » et la célébration d'un grade.
3. Passer en très grande taille de texte.

**Résultat attendu** : Les badges sont annoncés avec le nom du grade et le parcours (ex. « Collectionneur, Collection »), sans bruit décoratif ; chaque ligne de la liste est lue d'un bloc (nom, date ou condition, grade actuel). La célébration est lisible, se ferme avec le geste d'échappement et « Fermer ». Rien n'est tronqué en grande taille de texte.

- [ ] Passé — date / appareil / version :

### U10 — Import d'une grosse collection : carte « Bienvenue ! » et dates historiques `AUDIT` `AUTO`

**Conditions** : Compte Discogs de plus de 250 disques et plusieurs écoutes, jamais connecté à cette version ; réseau disponible ; collection chargée en entier.

**Étapes** :

1. Se connecter et laisser la collection se synchroniser complètement.
2. Observer la carte qui s'ouvre.
3. Fermer, ouvrir Réglages puis « Mes grades ».
4. Se déconnecter puis se reconnecter, et relancer l'app.

**Résultat attendu** : Une seule carte « Bienvenue ! » s'ouvre, pour le plus haut grade déjà mérité (la collection l'emporte à égalité), avec son animation et le texte « Voici ton grade de départ… ». Dans « Mes grades », chaque grade porte la vraie date où il a été franchi (date d'ajout du N-ième disque distinct, horodatage de la N-ième écoute), jamais la date du jour sauf grade tout juste gagné. Aucun autre grade n'est fêté. L'accueil ne se répète ni à la reconnexion ni après relance, et un compte qui part de zéro n'en reçoit pas (règles couvertes par GradeRulesTests et GradeStoreTests).

- [ ] Passé — date / appareil / version :

### U11 — Accueil sur un second appareil : pas de carte en double `AUDIT` `PREMIUM`

**Conditions** : Compte Premium avec synchro iCloud, accueil déjà fait sur l'appareil A ; second appareil B jamais utilisé avec ce compte.

**Étapes** :

1. Sur B, se connecter au même compte, laisser iCloud se rapatrier puis la collection se synchroniser.
2. Ouvrir « Mes grades » sur B.

**Résultat attendu** : B n'affiche pas de nouvelle carte « Bienvenue ! » (le fait que l'accueil est fait est synchronisé) et retrouve les grades et dates de A. Limite connue : si B décide avant la fin du premier rapatriement iCloud, la carte peut apparaître une fois.

- [ ] Passé — date / appareil / version :

# Journal de bord — Spinfolio (Spinlog)

Détail des évolutions **commitées**, jour par jour, du plus récent au plus ancien.
Mis à jour chaque jour où des commits sont faits (une entrée par jour, un paragraphe par commit).
Source : historique git (`git log`). Les volumes indiqués sont ceux de `git --shortstat`.
Les commits qui ne font que mettre à jour ce journal n'y sont pas repris.

---

## 2026-10-28 — Premium : grille tarifaire France, achat à vie, codes d'offre

### 00:54 — `7026ce5` Page web : prix France, grille 3 colonnes, manuel à jour ; audit du 25 octobre
- Page web : prix France (1,99 € / 17,99 € / 39,99 €), grille en 3 colonnes, manuel à jour.
- Ajout du rapport d'audit du 25 octobre et du script des captures App Store.
- 3 fichiers, +764 / −28.

### 00:51 — `2ebcbab` Premium : achat à vie, codes d'offre et grille tarifaire France
- Grille : mensuel 1,99 €, annuel 17,99 € (essai d'une semaine conservé), achat à vie 39,99 €
  (produit non consommable, sans partage familial).
- Paywall : carte « Premium pour toujours » sous l'offre d'abonnement ; message et accès à la
  gestion de l'abonnement quand un abonné achète à vie.
- Codes d'offre : bouton sur le paywall et ligne « Utiliser un code » dans Réglages > À propos
  (masquée en mode démo et pour un achat à vie) ; « Gérer mon abonnement » masqué sans abonnement actif.
- Fichier StoreKit local, textes anglais, recettes L11 et L32–L42, 12 tests de droits Premium (522 au total).
- 16 fichiers, +641 / −129.

---

## 2026-10-27 — Prix d'achat et état du média : filtre, saisie rapide, feuille « Prix et état »

### 10:34 — `f098c84` Prix d'achat et état du média : saisie après un scan par lot et feuille « Prix et état »
- Après un scan par lot, le bilan propose de renseigner prix et état tout de suite : une feuille
  saisit disque par disque, avec « Passer » (disques ajoutés en ligne, champs configurés).
- La feuille de la fiche disque devient « Prix et état » : prix d'achat et état du média
  ensemble, seuls les champs modifiés sont envoyés.
- Recettes G29, H34 et P41.
- 13 fichiers, +782 / −54.

### 10:34 — `3a4bdfa` Feuilles de saisie : bouton de validation « OK » au lieu d'« Enregistrer »
- Alerte de prix, renommage de tag, tri d'un artiste, renommage de dossier : « OK » (libellé
  VoiceOver explicite) ; bouton du clavier de l'alerte renommé « Terminé ».
- Le bouton des dossiers n'était pas traduit en anglais : corrigé.
- 4 fichiers, +14 / −5.

### 10:34 — `a39def5` Collection : filtre « À compléter » (sans prix d'achat, sans état du média)
- Menu Filtres > « À compléter » : « Sans prix d'achat » et « Sans état du média », pour les champs
  configurés ; cumulables entre eux et avec les autres filtres, pastille par filtre.
- Tests du filtre (510 au total) ; recette B52.
- 11 fichiers, +259 / −21.

---

## 2026-10-26 — Audit : lots 12, 8, 9, 11, 13, 14, 15 et 10 ; découpage des gros fichiers

### 19:55 — `c954b41` Scan par lot : pastilles Collection et Wantlist comme sur les autres écrans
- Dans la liste du scan par lot, les pastilles « Collection » (verte) et « Wantlist » (couleur
  du thème) sont celles des autres écrans, au lieu d'un texte rose.
- Recette G28.
- 3 fichiers.

### 19:41 — `f42c0b5` Découpe ReleaseDetailView, ArtistDetailViewModel et DeveloperOptionsView sous 500 lignes
- Fiche disque (829 → 432 lignes) : jaquette, crédits d'artistes, squelette de chargement,
  lignes de rangement et section « Infos Discogs » deviennent des sous-vues à paramètres
  explicites.
- Page artiste (731 → 471) : possession locale, rattachement à l'artiste par identifiant et
  classement sans requête de la discographie en fonctions pures, testées.
- Options développeur (701 → 375, version de développement seulement) : sections en vues,
  alimentation du prix d'achat net et sauvegarde JSON en services.
- Aucun changement de comportement.
- Tests de la possession et du classement (498 au total) ; recette P40.
- 14 fichiers, +1503 / −1094.

### 19:30 — `a56f875` Audit lot 11 : relecture des traductions anglaises, guillemets typographiques
- Relecture des 465 traductions automatiques anglaises : 3 chaînes corrigées (indication
  VoiceOver à la 3ᵉ personne, « Gain hidden », une phrase du rangement).
- Guillemets et apostrophes droits remplacés par “ ” et ’ dans 115 chaînes anglaises ;
  pluriels conservés.
- 2 fichiers, +176 / −176.

### 19:30 — `1240b3e` Audit lot 13 : règles de fusion iCloud extraites et testées
- Fusion des tags, des tags autonomes, des personnalisations de rangement et des réglages
  reçus d'iCloud extraite dans des fonctions pures, sans changer le comportement.
- Tests : union à la première synchro, remplacement ensuite, suppression propagée, valeur
  inconnue d'une autre version, anciens enregistrements encore lisibles (485 tests au total).
- 3 fichiers, +220 / −24.

### 19:30 — `f44cdc1` Audit lots 10 et 8 : jetons podium et paywall, PDF à 9 pt, section courante isolée
- Couleurs du podium des Stats et de l'en-tête du paywall passées en jetons (rendu inchangé).
- Export PDF de la collection : texte à 9 pt minimum, 13 albums par page au lieu de 15.
- Le changement de section pendant le défilement ne réévalue plus tout l'écran Collection ou
  Wantlist, seulement la barre d'index.
- Recettes P38 (étendue), P39 et M31.
- 10 fichiers, +54 / −30.

### 18:58 — `fb09ff2` Audit lot 10 : contraste des boutons pleins et jetons de design
- Texte des boutons pleins choisi automatiquement selon le thème (contraste ≥ 4,5:1) :
  foncé en mode sombre pour les 10 thèmes, blanc en clair ; violet du thème Violet clair
  légèrement foncé pour atteindre le seuil.
- Badges de pochette à 11 pt ; thème verrouillé : ouvre le paywall.
- Couleurs d'avertissement, hors ligne et de note en jetons ; graphiques sans teinte proche
  de l'accent ; or, rayons, animations, pastille PREMIUM et cartes unifiés ; tailles fixes
  remplacées par des styles de texte.
- Tests du contraste et de la palette (468 au total) ; recette P38.
- 68 fichiers, +465 / −189.

### 11:47 — `5bf7419` Audit lot 15 : diagnostic d'abonnement masqué, force unwraps retirés
- Le diagnostic d'abonnement n'apparaît plus de lui-même sur TestFlight ni en revue App Store :
  7 touchers sur « Version » (À propos) l'affichent ou le masquent, jamais sur l'App Store.
- Derniers `try!` et force unwraps du code retirés (chemins d'erreur explicites).
- Recette L31.
- 19 fichiers, +116 / −19.

### 11:38 — `12e5fe8` Découpe Collection, Stats et fiche disque sous 500 lignes
- Les quatre plus gros fichiers (de 820 à 1 000 lignes) passent sous 500, par une vraie
  extraction : services sans état et fonctions pures, sans élargir l'accès à l'état.
- **Écritures vers Discogs** regroupées dans un seul service, partagé par la Collection et la
  fiche disque ; hors ligne ou sans identifiants, une écriture part toujours en file.
- Collection : affichage (tri, filtres, sections), pagination et mises à jour optimistes séparés ;
  vue découpée en sous-vues. Stats : calculs en fonctions pures, lectures Discogs dans un service.
- Résultats ignorés après un changement de compte ou de dossier en cours de chargement.
- Tests des nouvelles fonctions (436 au total) ; recette P36.
- 37 fichiers, +2764 / −2291.

### 10:36 — `e3b3e11` Audit lots 8, 9, 11, 13, 14 : fluidité, accessibilité, localisation, tests, factorisation
- **Fluidité** : tags, badges d'exemplaires, barre d'index et Tri des artistes calculés une fois
  et gardés en cache au lieu d'être refaits à chaque rendu ou à chaque frappe.
- **Accessibilité** : zones de toucher de 44 pt sans changer le dessin ; note en étoiles réglable
  avec VoiceOver ; résumé du graphique de cote ; progression du mini-lecteur réglable ; fondus à
  la place des mouvements avec « Réduire les animations ».
- **Localisation** : sélecteur de recherche traduit, nombres et montants selon la langue,
  « listen(s) » pour la platine en anglais.
- **Tests** : 53 tests de plus (rangement, alertes, grades, Stats, devises, export CSV, écoutes
  iCloud), tests existants nettoyés ; 421 au total.
- **Factorisation** : types déplacés dans leurs fichiers, états vides partagés entre Collection et
  Wantlist, répartitions des Stats en fonctions pures ; App Group et attributs de la Live
  Activity dans un seul fichier commun à l'app et au widget.
- Recettes P32 à P35.
- 100 fichiers, +2917 / −1869.

### 00:52 — `a294c2a` Audit lot 12 : cohérence de l'interface
- **Appui long** : menus en mode Liste (Collection, Wantlist), dans la Recherche et le Tri des artistes,
  menu complet sur la mosaïque Wantlist ; ni Modifier ni Supprimer sur un cache hors ligne périmé.
- Retrait d'un tag porté par une partie de la sélection : confirmation aussi depuis le menu.
- Erreurs de caméra du scan par lot affichées ; bandeau hors ligne sur les pages Label et Master,
  un seul message hors ligne dans la Recherche.
- Vibration d'ajout et de retrait identique partout (une seule pour un retrait en lot).
- **Vocabulaire** : « Supprimer » pour sortir un disque de la collection ou de la wantlist,
  compteurs en « albums » ; alertes à message unifiées (`messageAlert`).
- Recette P31 (+ B9, B17, N22 mis à jour).
- 25 fichiers, +325 / −411.

---

## 2026-10-25 — Audit complet : lots 1 à 7 ; mini-lecteur et fermetures en douceur

Audit en lecture seule de toute l'app (rapport `QA/audit-2026-10-25.md`, non publié), puis traitement
lot par lot : isolation des comptes et de la démo, intégrité iCloud, retrait performant, petites
corrections, messages d'échec et suppression des données, sécurité et journaux, réseau robuste,
rechargements d'onglet.
En parallèle, fermetures du lecteur Apple Music et de la feuille d'écoute sur platine dans le mini-lecteur.

### 23:35 — `2fdfd9d` Audit lot 7 : rechargements d'onglet espacés de 5 minutes
- Collection et Wantlist : en revenant sur l'onglet, le cache s'affiche et Discogs n'est redemandé qu'au
  plus toutes les 5 min (`ReloadThrottle`) ; une grosse collection peut finir sa relecture de fond.
- Stats : compteurs et valeur de la collection redemandés au plus toutes les 5 min.
- Tirer-pour-actualiser, retour du réseau, connexion et changement de compte rechargent toujours tout de suite.
- Tests `ReloadThrottleTests` ; recette B51.
- 9 fichiers, +101 / −6.

### 23:20 — `e8c744b` Audit lot 6 : réseau robuste
- **File hors ligne** : quota Discogs dépassé (429) → nouvel essai espacé au lieu d'une boucle toutes
  les 5 s ; détection textuelle de « 429 » retirée.
- **Tâches de fond** : classement des œuvres et années des masters s'arrêtent sur quota ou panne
  passagère, masters remis en attente au lieu d'être perdus.
- **Note et prix d'achat** gardés et mis en file hors ligne ou sur panne (nouvelle action de note) ;
  les champs personnalisés restent acceptés en file même sur un cache ancien (choix produit).
- **Export CSV** : cache frais ou garde anti-doublon des relectures complètes.
- **Limiteur** : requêtes au-delà du plafond de 20 s espacées d'une seconde.
- **Erreurs réseau** : seules les coupures sont réessayées (plus les certificats ni les réponses illisibles).
- Chemins d'API regroupés dans `DiscogsEndpoints` ; année du master via `MasterYearLookup`.
- Tests du limiteur et des erreurs réseau ; recettes N28, N29.
- 15 fichiers, +244 / −77.

### 19:49 — `014af53` Écoute sur platine : arrêt en 1,5 s avant la fermeture de la feuille
- Ralentissement du disque ramené à 1,2 s, feuille fermée après 1,5 s (au lieu de 2,1 s).
- 2 fichiers, +3 / −3.

### 19:38 — `e28b37e` Mini-lecteur : disparition d'un bloc après un Stop ; feuille platine qui se réduit dans le mini-lecteur
- Contenu du mini-lecteur figé jusqu'au retrait de l'accessoire : capsule et contenu disparaissent ensemble.
- Feuille d'écoute sur platine : zoom depuis et vers le mini-lecteur ; Stop ralentit le disque,
  referme la feuille, puis arrête l'écoute une fois la feuille partie (plus d'assombrissement).
- Fin d'écoute : interface mise à jour avant la fermeture des Live Activities.
- Recette Q33.
- 6 fichiers, +125 / −41.

### 17:28 — `1a6aecb` Audit lot 5 : sécurité et journaux
- **Vidéos YouTube** : identifiant validé (hôte exact, 11 caractères) avant insertion dans le lecteur,
  stockage web éphémère séparé de la session discogs.com.
- **Journaux** : diagnostics des listes en `.debug`, identifiants masqués, erreurs détaillées privées.
- Clés Keychain partagées (`KeychainKeys`) ; widget sans repli hors App Group.
- **Réinstallation** : jetons Discogs effacés au premier lancement d'une installation neuve, sans
  déconnecter lors d'une mise à jour (`FreshInstallKeychainReset`).
- **Live Activity** : lien d'arrêt avec un jeton propre à l'écoute ; un lien externe n'a plus d'effet.
- Tests `ReleaseVideoTests`, `SecurityHardeningTests` ; recettes H33, R7, O24.
- 23 fichiers, +315 / −76.

### 17:10 — `c21170e` Lecteur Apple Music : Stop referme la fenêtre en douceur dans le mini-lecteur
- La fenêtre rentre dans le mini-lecteur (zoom inverse) avant l'arrêt ; son de l'extrait en fondu.
- Recette Q32.
- 4 fichiers, +41 / −2.

### 17:04 — `2b71a0e` Audit lot 4 : échecs hors ligne affichés, rangement par compte, suppression complète
- Action hors ligne abandonnée : alerte à fermer sur tous les onglets, listes rechargées depuis Discogs.
- **Réglages de rangement propres à chaque compte** (anciens réglages repris par le premier compte,
  jamais par la démo) ; `ShelfPreferencesStore` dans son propre fichier.
- « Supprimer mes données » efface aussi le rangement, le brouillon du scan et l'historique du complément
  de discographie ; déconnexion : sessions Google, Apple et Facebook de la webview vidées.
- Tests `ShelfPreferencesStoreTests`, `AccountLeftoversTests` ; recettes N27, D11, A31.
- 13 fichiers, +403 / −142.

### 16:53 — `4b2eb1b` Audit : gains rapides, code mort et nettoyage du catalogue
- Libellés VoiceOver des boutons à icône, « Arrêter la lecture » du mini-lecteur, index vertical ≥ 11 pt.
- Traductions et pluriels manquants, « Identifiant » de nouveau traduit, pourcentages du Guide formatés.
- Formatters partagés, vignettes vidéo en cache, closure de géométrie `@Sendable`, titre masqué dans
  les journaux du widget.
- Code mort supprimé et 140 clés obsolètes retirées du catalogue ; recettes A23/A30 et I27 corrigées.
- 20 fichiers, +153 / −1 831.

### 16:31 — `a120aa1` Audit lot 3 : retrait performant
- Retrait d'un disque : plus de relecture complète de la collection pour le widget, un seul passage
  par lot sur l'instantané.
- Guide de rangement et tri des artistes : collection décodée hors du fil principal.
- Tests `WidgetSnapshotRemovalTests` ; recette C18.
- 9 fichiers, +140 / −39.

### 16:24 — `0513cb3` Audit lot 2 : intégrité iCloud
- Grades connus d'un seul appareil renvoyés sur iCloud ; fusion initiale décidée au moment d'appliquer.
- Poussée initiale seulement après une récupération réussie, sur le même moteur et le même compte.
- Thème Premium masqué sans écriture à la perte de l'abonnement, rétabli au réabonnement.
- Suppression de zone reçue d'iCloud : les autres appareils effacent les données synchronisées du compte.
- Tests `GradeRulesTests`, `ThemeManagerTests`, `CloudSyncZoneDeletionTests` ; recettes M27 à M30.
- 12 fichiers, +309 / −27.

### 11:55 — `f103f1a` Audit lot 1 : isolation multi-compte et démo
- Cache des champs personnalisés par compte ; Wantlist, Stats, alertes, widget et file hors ligne
  ignorent les résultats arrivés après un changement de compte.
- Démo : modification de champ bloquée, file, alertes et état hors ligne purgés à la sortie, pas d'iCloud.
- Date de synchro hors ligne et nombre de disques archivés propres à chaque compte.
- Tests `AccountIsolationTests`, `OfflineSyncRecordStoreTests` ; recettes P30, N26.
- 17 fichiers, +336 / −27.

### 11:24 — `4a8918d` Collection : grand titre qui se réduit de nouveau au défilement après l'entrée en démo ou la connexion
- Le squelette reste dans la vraie liste jusqu'à la fin du premier chargement (plus d'état vide
  intermédiaire qui retenait la barre de navigation).
- 2 fichiers, +10 / −2.

---

## 2026-10-24 — Écoute sur platine, accueil animé, démo, interface plus vivante

### 17:50 — `f478523` Cassette : design plus riche et plus en relief
- Coque biseautée avec reflet et ombre, étiquette papier, fenêtre vitrée, pelotes de ruban et moyeux
  métalliques, vis aux coins ; seules les bobines sont redessinées à chaque image.
- 3 fichiers, +270 / −56.

### 17:30 — `0cedc3b` Guide : maquettes sans taille de police fixe, textes réels en .caption
- Styles système pour les icônes de la maquette d'écoute, textes en `.caption`.
- 4 fichiers, +7 / −7.

### 17:24 — `4da3c6a` Démo : pastille flottante de sortie, entrée toujours sur Collection ; accroche d'accueil sans chevauchement
- Pastille « Mode démo ✕ » sous la barre de navigation, sortie directe vers l'écran d'accueil.
- Chaque entrée en démo repart de la racine de Collection ; accroche de l'accueil qui ne recouvre plus le nom.
- Recettes A28, A29 ; tests d'interface associés.
- 7 fichiers, +164 / −5.

### 16:56 — `e878a24` Écran d'accueil animé et plein écran avant la connexion
- `WelcomeView` par-dessus les onglets : disque qui tourne, pochettes qui flottent, accroches qui défilent ;
  actions de connexion factorisées (`LoginActionsView`), anciens écrans « non connecté » supprimés.
- Recette A27.
- 24 fichiers, +437 / −129.

### 15:45 — `d5f949e` Réglages Apple Music : afficher l'état de l'abonnement sous la case de connexion
- Vérification en cours, abonnement actif, aucun abonnement ou accès refusé, relu à chaque ouverture.
- Tests `AppleMusicAccountStatusTests` ; recette Q31.
- 6 fichiers, +175 / −13.

### 15:45 — `50b8dc5` Animations : courbe de la cote qui se dessine, Mode Hors Ligne et lignes de Réglages en fondu
- Courbe « Évolution de la cote » dessinée de gauche à droite ; chiffres qui roulent dans Mode Hors Ligne ;
  lignes de Réglages révélées en fondu.
- 7 fichiers, +93 / −19.

### 15:27 — `7e7ec61` Écoute sur platine réservée aux disques possédés (fiche et raccourcis)
- « Mes écoutes sur platine » seulement pour un disque en collection ; raccourci refusé sinon.
- Recettes B50, F24, G27, H31, H32.
- 8 fichiers, +53 / −13.

### 15:27 — `5230486` Interface plus vivante : zoom pochette vers fiche, compteurs animés, scan par lot, suppression en lot instantanée
- Zoom de la pochette vers la fiche ; chiffres qui roulent dans le scan par lot.
- Suppression en lot : éléments retirés d'un coup, Discogs mis à jour en arrière-plan.
- 14 fichiers, +189 / −42.

### 14:55 — `c6decb2` Réglages : « Mode Hors Ligne » et « Couleur du thème » alignés sur les autres sous-pages
- Mise en page commune `SettingsSubPage` ; recette J38.
- 5 fichiers, +23 / −65.

### 14:49 — `e567d25` Scan par lot : retour à l'onglet de destination, codes non reconnus à part
- Après l'ajout, ouverture de Collection ou Wantlist ; section « Non reconnus », relançable, hors du compteur.
- Recettes G25, G26.
- 6 fichiers, +162 / −20.

### 14:14 — `2d53f98` Ajout : la pochette vole vers l'onglet Collection ou Wantlist
- Animation de la pochette jusqu'à l'onglet de destination ; recette H30.
- 7 fichiers, +366 / −1.

### 00:59 — `bce8905` Bras de lecture : angle posé porté à 20°
- La tête de lecture se pose un peu plus vers l'intérieur du disque (15° → 20°).
- 1 fichier, +2 / −2.

### 00:54 — `a3feb91` Écoute sur platine : bras de lecture, démarrage et arrêt progressifs ; scan par lot et recherche plus vivants
- **Feuille d'écoute** : bras de lecture pour le vinyle (se pose au début du disque, se relève à l'arrêt) ;
  le disque, le CD ou les bobines accélèrent au démarrage et ralentissent jusqu'à l'immobilité
  (`SpinProfile`), la feuille se ferme après l'arrêt en douceur ; le ruban de la cassette suit les bobines.
- **Scan par lot** : coins de visée qui respirent, éclair vert, haptique de succès, rebond du compteur
  et pastille du disque reconnu.
- **Recherche** : le texte d'invite du champ tourne toutes les 3 s parmi quelques suggestions.
- Recettes Q30, G23 et G24 ; tests `SpinProfileTests`.
- 13 fichiers, +611 / −78.

### 00:25 — `ef98f41` Réglages : la personnalisation du tri par artiste passe dans Organisation
- **Rangement** ne garde que la règle du meuble et « Limiter au dossier Discogs ».
- **Organisation** : tags et dossiers, puis section « Personnalisation du tri par artiste » (articles,
  nom de famille, tri personnalisé).
- Résumé de la ligne d'accueil, résultats de recherche et étape du guide mis à jour ; recette J35.
- 7 fichiers, +94 / −54.

### 00:18 — `97e9366` Écoute sur platine : le visuel suit le support (CD, cassette)
- **CD** : pochette entière devant un disque argenté sans impression, reflet irisé qui tourne, trou
  central transparent.
- **Cassette** : cassette en paysage derrière la pochette carrée, coque teintée de la couleur moyenne
  de la pochette, titre et artiste écrits à la main sur l'étiquette, bobines à dents qui tournent et
  ruban qui passe d'une bobine à l'autre.
- Support déduit des formats Discogs (`PhysicalMedia`, le premier support reconnu l'emporte) ; vinyle
  par défaut. Tests `PhysicalMediaTests`, recette Q29.
- 8 fichiers, +447 / −19.

---

## 2026-10-23 — Cloche d'alerte, interface plus vivante, grades et Réglages en pages

### 23:36 — `ba95d11` Grades et badges, confirmation d'effacement en deux étapes, Réglages en pages avec recherche
- **Grades** : deux parcours (disques distincts, écoutes sur platine hors Apple Music), 7 grades chacun,
  jamais rétrogradés ; badges animés, page « Mes grades » avec dates d'obtention, badges près du nom
  dans Réglages ; dates historiques réelles pour les grades attribués en silence et carte « Bienvenue ! »
  pour le plus haut grade de départ ; célébration au franchissement d'un palier ; synchro iCloud fusionnée.
- **Effacement des données** : « Effacer les données de l'app… » ouvre une feuille en grand qui liste les
  pertes avec leurs quantités et demande de retaper le nom d'utilisateur (suite à une perte d'historique
  d'écoute) ; clavier géré.
- **Réglages** : écran d'accueil par groupes (Ma collection, Écoute, Synchronisation, Aide &
  personnalisation) et sous-pages, recherche d'un réglage (casse, accents, mots-clés FR/EN), liens
  profonds redirigés, textes du guide mis à jour.
- Tests `GradeRulesTests`, `GradeStoreTests`, `EraseAccountDataConfirmationTests`, `SettingsSearchTests` ;
  recette U1–U11, A26, J35–J37.
- 36 fichiers, +3 719 / −591.

### 16:11 — `b9c7c18` Guide : la fiche « Plus-value » mène à « Comment ça fonctionne ? »
- Nouveau champ `explanationPage` sur `GuideEntry`, poussé dans la pile de Réglages (page accessible
  sans Premium) ; boutons « Essayer » et « Comment ça fonctionne ? » côte à côte. Recette T27.
- 6 fichiers, +35 / −4.

### 14:24 — `88177dd` Interface plus vivante, appui long du carrousel, Statistiques à jour
- **Fiche disque** : « pop » du bouton, coche et pulsation de la jaquette avec haptique à l'ajout, choc
  léger au retrait ; sections qui arrivent en cascade.
- **Listes** : un disque retiré s'efface en fondu ; pastille « À jour » après le tirage pour actualiser ;
  états vides illustrés (disque qui tourne).
- **Statistiques** : compteurs qui défilent, graphiques qui se dessinent à la première apparition ;
  « Derniers ajouts », compteurs et répartitions suivent ajouts, retraits et déplacements.
- **Carrousel** : appui long sur la jaquette (menu d'actions, retrait avec confirmation).
- Tests `LibraryFeedbackEventTests`, `RecentAdditionsLogicTests` ; recette H28, B46–B49, H29, I28, I29.
- 28 fichiers, +678 / −67.

### 12:29 — `45746c5` Cloche d'alerte sur la jaquette, suppression d'alerte avec confirmation
- **Carrousel de la Wantlist** : la cloche est posée sur la jaquette (en bas à droite) à la place de la
  capsule sous la jaquette ; son disque suit le thème (clair en thème clair, sombre en thème sombre,
  jeton `coverBellDisc`).
- **Feuille « Alerte de prix »** : cloche sur la jaquette, grise sans alerte, rose si elle est active,
  verte si elle est déclenchée (pleine dans les trois cas), comme dans la liste.
- **Vert unique** : les alertes déclenchées utilisent le vert « Seuil atteint » (`gainPositive`) partout
  dans la Wantlist.
- **Suppression** : le bouton « Supprimer cette alerte » passe sous le champ du seuil, avec une
  confirmation avant d'effacer ; traductions anglaises ajoutées.
- Composants `CoverAlertBellButton` et `DeleteAlertButton` ; cas de recette E20 à E24.
- 12 fichiers.

---

## 2026-10-22 — « Mon exemplaire » et « Alerte de prix »

### 17:56 — `a890d61` Feuille « Alerte de prix » animée ; retour visuel de la cloche de la Wantlist
- **Feuille d'alerte** : prix qui défile, halo de focus, lueur verte quand le seuil rejoint
  l'annonce la moins chère, tuiles et pastilles en cascade, jauge animée, cloche d'en-tête qui rebondit ;
  au focus du prix maximum, le titre « Mon seuil d'alerte » remonte sous la barre de navigation.
- **Cloche de la Wantlist** (liste, carrousel) : pastille rose et rebond au toucher, retour haptique
  léger ; sans changement d'échelle avec « Réduire les animations ».
- Extraction de `PriceChip`, `MarketTile` et `AlertBellButtonStyle` ; cas de recette E21, E22, E23.
- 14 fichiers.

### 17:35 — `ce2c710` Animations : disque qui tourne, guide de rangement vivant
- **Feuille d'écoute sur platine** : jaquette entière devant un disque noir dont l'étiquette tourne à
  33 tours/min (jamais de jaquette recadrée).
- **Carte « Mes écoutes sur platine »** : icône disque qui tourne, point qui pulse, halo discret,
  compteur qui défile au démarrage.
- **Guide de rangement** : compteur et jauge qui montent, disques qui arrivent en séquence, pochette
  cible qui respire lentement, halo et repère « ICI » ; colonne cible extraite en `ShelfTargetColumn`.
- Tout est neutralisé avec « Réduire les animations ».

### 17:36 — `da359e6` Retours haptiques du carrousel et de la barre A-Z ; barre horizontale alignée
- Cran léger à chaque pochette centrée du carrousel (au doigt, un toutes les 50 ms au plus) et à
  chaque lettre de la barre verticale (Liste, Mosaïque).
- Barre A-Z horizontale du carrousel : le doigt est mesuré dans la rangée de lettres centrée, plus de
  décalage vers les bords.
- Cas de recette I27, J34, B43, B44, B45.

### 12:30 — `c9cc6e6` « Mon exemplaire » et « Alerte de prix » embellis ; pastille « Utilisé pour la plus-value »
- **Les deux feuilles** : en-tête commun (jaquette en grand avec halo, titre, artiste, pastilles
  d'année, de format et de dossier) et fond teinté de la couleur de la pochette.
- **Mon exemplaire** : pastilles Payé / Cote / Plus-value en vert ou rouge (Premium) ; sous les champs
  choisis pour le calcul, une pastille orange « Utilisé pour la plus-value » ouvre Réglages sur la
  ligne concernée, mise en surbrillance, y compris à la toute première visite de Réglages.
- **Alerte de prix** : ouverture en pleine hauteur, grand prix maximum centré (focus au premier
  toucher, curseur en fin de montant), tuiles de marché, jauge seuil / annonce la moins chère,
  pastilles de prix, squelettes de chargement, tuile « Annonce la moins chère » vers Discogs.
- Tests `PriceSheetModelsTests` et cas de recette H26, H27, E20.
- 16 fichiers.

---

## 2026-10-21 — Graphiques de Stats fluides, paywall après la connexion

### 19:50 — `b560d74` Lecteur plein écran depuis le mini-lecteur
- **Apple Music** : toucher le mini-lecteur ouvre une fenêtre plein écran sur le modèle de « Lecture en
  cours » (pochette en fond flouté, titre, artiste, progression, précédent / stop / suivant, volume
  système, AirPlay, liste des pistes en feuille), avec une transition zoom depuis le mini-lecteur et
  une fermeture interactive au glissé. Un bouton disque ramène à la fiche d'origine.
- **Platine** : petite feuille à la hauteur de son contenu (jaquette, titre, artiste, fiche du disque,
  « Arrêter l'écoute »).
- 13 fichiers dont `NowPlaying/` (6 nouveaux) et `NowPlayingAlbumTests`.

### 19:51 — `edf2c38` Listes courtes : rebond et retour de la barre d'onglets
- Rebond toujours actif en Liste, Mosaïque et Carrousel ; le tirage vers le bas au sommet rétablit tout
  de suite la barre d'onglets réduite (`expandTabBar`).

### 19:52 — `04f1276` Réglages : aide du suivi de plus-value pour tous
- « Comment ça fonctionne ? » reste accessible sans Premium, sous la carte d'offre.

### 19:53 — `3dfa799` Position conservée au retour sur une fiche, un master, un label, un artiste, un profil
- Ces écrans ne se rechargent plus quand ils sont déjà affichés (`loadIfNeeded`) : plus de squelette ni
  de retour en haut au retour arrière.

- Cas de recette Q11, Q27, Q28, E19, J33, H25 (`c72fd46`).

### 18:25 — `bd79597` Synchro iCloud sans plantage à l'achat Premium, « All » retiré des choix de dossier, histogrammes par année avec axe vertical lisible
- **Plantage après achat** (rapport TestFlight, `CKSyncEngine.fetchChanges` appelé en récursion) : le
  premier démarrage de la synchro émet `accountChange`, dont le traitement lançait des `Task`
  héritant du contexte du rappel ; `fetchChanges`/`sendChanges` partent maintenant d'une tâche
  détachée sur l'acteur principal (`detachedOnMainActor`).
- **Dossiers** : « All », simple vue agrégée de Discogs, n'est plus proposé pour changer le dossier
  d'un exemplaire ni dans les menus d'ajout de la fiche d'un disque.
- **Stats** : marge de l'échelle verticale corrigée pour les petits effectifs (vue par année) et
  graphique à défilement natif, avec axe vertical fixe et valeurs entières visibles.
- Tests unitaires et cas de recette M26, J32, I26.
- 11 fichiers.

### 16:55 — `fe4527b` Guide de rangement : le disque central réagit au toucher, repère « ICI » à plat
- Toucher la pochette centrale ou « ICI » la fait rebondir (bordure rose épaissie, ombre renforcée)
  avec un léger retour haptique, sans rien ouvrir ; avec « Réduire les animations », seule la
  bordure change. Le repère « ICI » devient un texte rose à plat pour ne plus ressembler à un
  bouton ; VoiceOver lit la colonne centrale d'un bloc. Cas de recette J31.
- 5 fichiers.

### 16:50 — `94c3f5e` Profil Discogs : bouton Se déconnecter au-dessus de Supprimer mon compte
- Le profil Discogs (Réglages) propose « Se déconnecter », avec la même confirmation que dans
  les Réglages ; il ferme le profil et ramène à l'écran de connexion, sans effacer les données du
  compte (retrouvées à la reconnexion). Cas de recette A25.
- 4 fichiers.

### 14:58 — `1a89f07` Connexion annulée sans erreur ; page de collection tolérante aux exemplaires illisibles
- **Connexion** : fermer la fenêtre Discogs ou toucher « Annuler » n'affiche plus de message
  d'erreur rouge (seule l'annulation est ignorée, les vraies pannes restent signalées).
- **Collection** : un exemplaire illisible dans une page Discogs est ignoré (et compté dans les logs)
  au lieu de vider l'onglet avec « Les données n'ont pas pu être lues » ; note, date d'ajout et
  dossier deviennent facultatifs. Cause exacte non confirmée, à vérifier sur TestFlight.
- Tests unitaires et cas de recette A24 et B42.
- 8 fichiers, +103 / −7.

### 14:10 — `d36490c` Stats : graphiques fluides et titre en haut, paywall après la connexion, bannière Premium et barre de titre
- **Stats** : sélections et feuilles de tous les graphiques (histogrammes par année, camemberts
  genre/support/label, classement des artistes) isolées dans un objet observable lu seulement par
  le graphique touché, au lieu d'états qui ré-évaluaient toute la page. Les autres parts s'estompent
  immédiatement, la sélection se remet à zéro dès que la feuille commence à se fermer (détection
  du début de fermeture, le `Binding` n'arrivant qu'à la fin de l'animation), un second toucher
  désélectionne, et les listes de disques sont calculées hors du fil principal.
- **Camemberts** : un composant commun remplace trois copies du même code (fichier des graphiques
  de 786 à 350 lignes) ; la feuille « support » ne remet à zéro que la part qui l'a ouverte.
- **Titre en haut** : toute ouverture de feuille, et la sélection d'une part de camembert, fait
  défiler le titre du graphique en haut de l'écran.
- **Paywall** : présenté une fois l'utilisateur connecté (compte ou démo), plus avant l'écran de
  connexion ; la bannière Premium de Réglages et le paywall tiennent aussi compte du forçage
  développeur.
- **Barre de navigation** : apparence du titre serif appliquée une seule fois par barre (piste du
  grand titre qui ne se réduit pas sur iPhone 13 mini sous iOS 26.6, non reproduite).
- 20 fichiers, +1 220 / −963.

---

## 2026-10-20 — Démo plus parlante, synchro iCloud réglable, plantage à l'écoute corrigé, données Discogs allégées

Journée consacrée aux retours de TestFlight : historique de valeur tenu hors d'iCloud, mode démo
qui montre enfin ce que le Premium apporte, interrupteur de synchronisation iCloud, création de
compte Discogs depuis l'app, traque d'un plantage au lancement d'une écoute sur platine, puis
deux finitions (Réglages, Stats).

### 23:42 — `f8e830a` Mode hors ligne : la durée de conservation des pochettes est expliquée
- La note sous « Pochettes en cache » annonce que les pochettes sont gardées 7 jours au plus après
  leur téléchargement (durée lue dans `DiscogsConstants`, pluriel français et anglais).
- 4 fichiers, +56 / −2.

### 23:26 — `a5b48ce` Données Discogs : pochettes 7 jours au plus, historique de valeur arrêté, suppression de compte complète
- Historique de valeur : l'enregistrement quotidien est désactivé tant que le graphique « Évolution
  de la cote » est masqué ; pochettes conservées 7 jours au plus sans prolongation à la
  consultation ; « Supprimer mes données » efface aussi les cotes par disque, le cache d'images,
  les années de master et les catégories d'œuvres.
- 11 fichiers, +60 / −10.

### 16:47 — `aba4000` Règle de rangement mise en évidence, 5 lignes entières dans Tops & Palmarès
- Depuis « Modifier » du guide de rangement, la ligne « Règle de rangement dans le meuble » de
  Réglages prend 2 s la teinte du thème pour être repérée tout de suite.
- Classements d'écoute des Stats : hauteur du cadre calculée d'après le contenu mesuré, la 5ᵉ
  ligne n'est plus coupée en passant d'Albums à Artistes (règle testée).
- 8 fichiers, +85 / −13.

### 16:29 — `39e5430` Démo plus parlante, synchro iCloud réglable, création de compte et plantage à l'écoute corrigé
- **Plantage au lancement d'une écoute** : les couleurs dynamiques (`UIColor { trait in }`)
  héritaient de l'isolation au fil principal et lisaient le thème dans leur closure, alors que
  SwiftUI les résout sur son fil de rendu asynchrone à l'apparition animée du mini-lecteur.
  Elles sont désormais `@Sendable`, thème lu avant ; mêmes précautions pour les `PreferenceKey`,
  `FlowLayout` et le suivi de défilement des fiches. Piège ajouté aux règles du projet.
- **Live Activity** : jaquette plafonnée à 2 800 octets, l'activité n'était plus refusée pour
  dépassement de la limite de 4 Ko. **Stats** : secteurs des camemberts sans arrondi (plantage
  Charts remonté par TestFlight le 19).
- **Mode démo** : étiquette dorée « PREMIUM » sur chaque fonction Premium, cote d'exemple
  signalée et jamais mise en cache, journal d'écoute d'exemple pour remplir palmarès et podiums.
- **Réglages** : interrupteur « Synchroniser avec iCloud » (Premium, propre à l'appareil),
  réactivé au passage Premium avec fusion complète ; lien « Pas de compte ? Crée-en un » vers
  l'inscription Discogs, aussi sur l'écran de connexion.
- **Abonnement** : forçage développeur séparé de l'abonnement réel, droits expirés ignorés,
  diagnostic StoreKit hors App Store.
- Traductions anglaises, tests unitaires, 7 cas ajoutés au cahier de recette.
- 45 fichiers, +804 / −135.

### 11:24 — `835ce37` Historique de valeur : synchro iCloud désactivée tant que le graphique est masqué
- Les points d'historique de la valeur de la collection (données Discogs conservées au-delà de
  6 h) ne sont plus envoyés vers iCloud ni appliqués à la réception, en attendant un accord de
  Discogs ; code laissé en commentaire, points locaux conservés.
- 2 fichiers, +29 / −18.

---

## 2026-10-19 — Cote Discogs datée, aperçu Premium de la démo, cote accessible à tous

### 23:01 — `af59b44` Cote et prix d'achat accessibles sans Premium, seule la plus-value reste verrouillée
- La cote Discogs actuelle s'affiche sans abonnement (ligne partagée `MarketEstimateRow`) et le
  prix d'achat se saisit sans Premium ; seule la plus-value garde la carte verrouillée. Textes de
  Réglages, du paywall et de l'aide ajustés ; cahier de recette mis à jour.
- 14 fichiers, +273 / −151.

### 21:34 — `a538e50` Réglages : aperçu Premium du mode démo signalé
- Ligne « Aperçu Premium (mode démo) » expliquant que les fonctions Premium sont débloquées
  pendant la démo ; bouton de démo qui mentionne l'aperçu Premium.
- 5 fichiers, +62 / −3.

### 21:34 — `01ca1b6` Cote Discogs de plus de 6 h : datée hors ligne au lieu d'être présentée comme actuelle
- Cote en cache réutilisée telle quelle seulement si elle a moins de 6 h ; plus ancienne, servie
  hors ligne uniquement et datée (« Cote du … »), conformément aux CGU de l'API Discogs. Règle
  extraite dans `MarketEstimate.fromCache` et testée.
- 6 fichiers, +126 / −22.

---

## 2026-10-18 — Audit complet, mode démo, tests automatiques, fiabilité des données, interface, Swift 6, règles du projet

Journée consacrée à l'aboutissement de l'audit de l'app (branche `audit-fixes`) : préparation de la
soumission App Store, mode démo pour App Review, fiabilité des données, accessibilité, découpage des
plus gros fichiers, mise en place des tests automatiques et d'un cadre de règles pour la suite,
puis fiabilisation des données (stores illisibles, déconnexion, dossiers, doublons, suppression de
compte, conflits iCloud), puis le bloc interface et accessibilité, le passage en Swift 6 avec un premier lot de qualité, les raccourcis Siri, et enfin six petits défauts.

### 12:29 — `0c4f597` Applique l'audit : soumission App Store, mode démo, fiabilité et accessibilité
- **Soumission App Store** : manifestes de confidentialité `PrivacyInfo.xcprivacy` (app et widget),
  déclaration « pas de chiffrement soumis à déclaration » (`ITSAppUsesNonExemptEncryption`),
  revérification de l'abonnement au retour au premier plan et juste après un achat, noms
  d'utilisateur et d'artistes masqués dans les logs, cible minimale abaissée à iOS 26.1 (repli par
  menu contextuel là où le balayage n'existe pas), identifiant du widget corrigé
  (`com.auralabs.Spinlog.SpinlogWidgets`), widget « Album du jour » accessible à tous.
- **Mode démo** (sans compte Discogs) : collection d'exemple embarquée (`DemoLibrary.json`, 36
  vinyles, 5 CD, 3 cassettes, 12 souhaits, 3 dossiers, prix d'achat), requêtes du compte servies
  par `DemoServer`, toute écriture vers Discogs bloquée avec des messages dédiés, aperçu Premium
  pendant la démo sans masquer l'offre, démo limitée à la session et données effacées à la sortie.
- **Fiabilité** : file hors ligne qui réessaie avec un délai croissant (30 s → 30 min) au lieu
  d'abandonner après ~6 s, abandon seulement après 7 jours ; scan par lot conservé (fermeture,
  perte de réseau, app tuée) avec confirmation de fermeture ; Live Activity affichée « Écoute
  terminée » puis fermée après la durée maximale même app suspendue.
- **UX et accessibilité** : paywall au lancement limité à une fois par semaine, barres A-Z et mode
  sélection utilisables avec VoiceOver, messages de la Wantlist enfin visibles, textes d'aide
  adaptés à iOS 26, 62 traductions anglaises ajoutées.
- **Aussi** : gestion des dossiers dans Réglages (création, renommage, suppression vers
  Uncategorized, dossier par défaut), retour en haut au re-tap d'un onglet, tags à la taille de la
  variation de prix dans « Mon exemplaire », factorisations (sections de Réglages, carte de liste
  groupée, helpers de dates, durées, alertes et notifications).
- 81 fichiers, +7 368 / −1 126.

### 12:39 — `3b31af5` Découpe les plus gros fichiers en fichiers thématiques
- Code uniquement déplacé, vérifié ligne à ligne : `CloudSyncEngine` (rapatriement, délégué
  CKSyncEngine, types d'enregistrements), `LocalDataStore` (modèles SwiftData, Collection,
  Wantlist), `AppTheme` (ThemeManager, palette, cache des couleurs), `StatsViewModel` (types des
  classements), sous-vues extraites (`CollectionFieldControl`, `ReleaseDetailInstanceRow`,
  `ArtistSortEditSheet`, `AutoScrollingText`, `BatchScanRow`).
- Conformité `CKSyncEngineDelegate` déclarée sur la classe (corrige un avertissement `Sendable`).
- Seuls les membres réellement partagés entre fichiers perdent leur `private`.
- 24 fichiers, +3 059 / −3 019.

### 16:21 — `db99544` Ajoute les tests unitaires et d'interface, cahier de recette v3.3
- **Tests unitaires** (`SpinlogTests`, Swift Testing, un fichier par domaine) : 97 tests au total
  (+65) — dates et durées Discogs, règle de nouvel essai et classification des erreurs de la file
  hors ligne, tris et sections, serveur de démo, fréquence du paywall. Délai et expiration de la
  file hors ligne extraits en fonctions statiques testables ; identifiant de la cible corrigé.
- **Tests d'interface** (nouvelle cible `SpinlogUITests`) : 5 parcours sur la collection de démo,
  lancés avec `-uiTestDemo` / `-uiTestSignedOut` (Debug uniquement), identifiants d'accessibilité
  sur les disques et le bouton Wantlist de la fiche.
- **Cahier de recette v3.3** : 34 nouveaux cas tagués AUDIT (359 au total), nouveau tag AUTO pour
  les cas couverts par les tests automatiques, PDF régénéré.
- 23 fichiers, +812 / −117.

### 16:30 — `0b29bc9` Ajoute CLAUDE.md : règles d'implémentation du projet
- Cadre à respecter pour tout nouveau code : méthode de travail, architecture, concurrence,
  performance, design system, accessibilité, localisation, contextes transverses (Premium, démo,
  hors ligne, multi-compte, iCloud, widget), confidentialité, compatibilité iOS 26.1, tests, style,
  pièges connus et checklist de fin.
- 1 fichier, +245.

### 16:38 — `aa00792` Ajoute le journal de bord des évolutions commitées
- Ce journal, placé dans `journal/` (hors de `docs/`, publié par GitHub Pages), initialisé avec
  tout l'historique.
- 1 fichier, +304.

### 17:14 — `293d5da` Fiabilise les données : stores illisibles, déconnexion, dossiers, doublons, compte, conflits iCloud
- **Stores illisibles** : tags, écoutes, alertes et file hors ligne chargés de façon tolérante
  (`PersistedStoreDecoding`) ; une entrée abîmée est ignorée et l'original est copié sous une clé
  de secours, au lieu de vider tout le store à la prochaine écriture.
- **Déconnexion** : téléchargement hors ligne, années de master, classement des discographies,
  écoute sur platine et lecture Apple Music arrêtés ; notifications et tâche de fond des alertes
  du compte quitté retirées ; plus d'écriture tardive dans le widget ni de notification.
- **Suppression de dossier** : actions en attente redirigées vers Uncategorized, cache local des
  dossiers élagué, dossier par défaut supprimé sur discogs.com remis à « Toujours demander ».
- **Doublons** : avant de rejouer un ajout, la file vérifie s'il a déjà abouti chez Discogs.
- **Suppression de compte** : alertes, actions en attente, préférences, état hors ligne,
  historique de valeur et métadonnées de cache effacés ; la zone iCloud n'est plus recréée.
- **Conflits iCloud** : la modification la plus récente l'emporte (`CloudSyncModificationLog`,
  champ `modifiedAt` sur chaque enregistrement).
- 24 tests unitaires ajoutés (121 tests verts) ; cahier de recette v3.4 (7 cas, 366 au total).
- 25 fichiers, +707 / −63.

### 21:48 — `341cfce` Interface et accessibilité : prix réels, thème, messages, navigation, états vides, VoiceOver
- **Montants** : bannière Premium au prix StoreKit réel (plus de « 2,50 € » codé en dur) ;
  plus-value de « Mon exemplaire » dans la devise choisie au lieu de l'euro.
- **Thème** : `accentColor` (violet fixe) remplacé par la couleur du thème dans 8 écrans ; Live
  Activity aux couleurs du thème via l'App Group.
- **Widget et scan** : aperçu de galerie et message « Ouvre Spinfolio » ; caméra refusée ou absente
  expliquée avec accès aux Réglages au lieu d'un écran noir.
- **Messages** : échec d'enregistrement à la fermeture de « Mon exemplaire » affiché sur l'écran
  d'origine ; ajouts et retraits hors ligne annoncés ; bilan du scan par lot qui distingue les
  ajouts en attente et les échecs (codes en échec conservés).
- **Navigation** : liens profonds sans vider la Recherche ; pile gérée et re-tap pour Réglages.
- **États vides et erreurs** : boutons Réessayer et Rechercher un disque ; erreurs HTTP Discogs
  traduites au lieu du message anglais de l'API.
- **Accessibilité** : graphiques des Stats utilisables avec VoiceOver (résumé et actions), Réduire
  les animations respecté (squelettes, parallaxe, carrousel).
- Traductions anglaises, 127 tests automatiques, cahier de recette v3.5 (380 cas).
- 46 fichiers, +1 041 / −210.

### 22:22 — `ef02599` Passe en Swift 6 ; décodage hors fil principal, webview limitée à Discogs, code mort, tests réseau
- **Swift 6** sur les 4 cibles : 49 avertissements de concurrence stricte corrigés (types décodés
  ou triés en arrière-plan déclarés non isolés, observateurs de notifications, moteur de sections,
  widget) ; tâche de fond, suivi du réseau et retour OAuth protégés contre l'arrêt par la
  vérification d'isolation à l'exécution.
- **Performance** : pages de collection et de wantlist (jusqu'à 100 exemplaires) décodées hors du
  fil principal.
- **Sécurité** : webview limitée à discogs.com (liens externes et site personnel du profil ouverts
  dans Safari, connexion Google/Apple conservée) ; retour OAuth accepté seulement si son jeton
  correspond à la demande en cours.
- **Code mort** : copie de la Live Activity côté app, `VinylSleeveCover`, `StyledNavigationSubtitle`,
  ancien toast d'écoute, alias de couleurs et constantes inutilisés.
- **Correctif** : page Discogs de la feuille d'alerte wantlist présentée par `item:` au lieu d'un `Bool`.
- **Tests** : signature OAuth vérifiée sur l'exemple de la spécification, retour OAuth, calcul des
  créneaux du limiteur de débit, domaines de la webview (154 tests verts) ; cahier v3.5 (384 cas).
- 47 fichiers, +457 / −609.

### 22:50 — `9ec9af8` Ajoute les raccourcis Siri ; contraste doré et tertiaire, bulle pour les actions hors ligne
- **Raccourcis Siri** (Siri, Spotlight, app Raccourcis, proposés sans configuration) : disque au
  hasard (ouvre sa fiche), démarrer une écoute (Siri demande le disque, recherché dans la
  collection en cache, hors ligne compris ; Live Activity lancée sans ouvrir l'app), arrêter
  l'écoute. Phrases en français et en anglais ; démarrage d'écoute unifié pour les écrans et Siri.
- **Contraste** : or des textes plus profond en mode clair (5,1:1 au lieu de 2,6:1), texte
  tertiaire plus lisible en mode sombre (5,4:1 au lieu de 2,5:1).
- **Hors ligne** : ajouts et retraits annoncés par la bulle de confirmation (« Hors ligne :
  synchronisé au retour du réseau ») au lieu d'une alerte à fermer à chaque action.
- 156 tests verts ; cahier de recette v3.5 (388 cas).
- 26 fichiers, +578 / −45.

### 23:02 — `7727973` Corrige six défauts : widget au thème, refus Discogs en wantlist, prix Marketplace, recherche, historique par compte, dossiers supprimés
- **Widget « Album du jour »** aux couleurs du thème (teinte foncée sur pochette claire),
  redessiné dès le changement de thème.
- **Wantlist** : un refus définitif de Discogs réaffiche le disque avec un message au lieu
  d'être mis en file ; le déplacement vers la collection n'enlève le disque de la wantlist
  qu'une fois l'ajout acquis (avant, un ajout refusé le faisait disparaître des deux listes).
- **Marketplace** : prix le plus bas converti dans la devise choisie (au lieu du dollar).
- **Recherche** : bouton « Réessayer » sur l'erreur (texte ou code-barres).
- **Historique de valeur** séparé par compte : un compte ne voit plus celui des autres, et la
  suppression d'un compte n'efface plus que le sien.
- **Dossiers** supprimés sur discogs.com : les actions en attente qui les visaient partent vers
  Uncategorized.
- 157 tests verts ; cahier de recette v3.5 (394 cas).
- 18 fichiers, +238 / −76.

### 23:10 — `a34cf4d` Live Activity : libellé d'écoute à 11 pt et traduit ; retire UIRequiresFullScreen
- Libellé « Écoute en cours sur la platine » / « Écoute terminée » de la Live Activity passé de
  9,5 pt à 11 pt, et écrit de façon à être bien traduit.
- Clé `UIRequiresFullScreen`, dépréciée depuis iOS 26, retirée (plus aucun avertissement de build).
- 2 fichiers, +5 / −6.

### 23:12 — `5c9ac4e` CLAUDE.md : règle Swift 6
- Ajout au §2 (Concurrence) : cibles en Swift 6, aucun avertissement d'isolation toléré,
  `nonisolated(unsafe)` / `@preconcurrency import` réservés aux types système non annotés et
  toujours commentés, rappels système hors fil principal `@Sendable` ou planifiés sur la file
  principale.
- 1 fichier, +6.

### 23:41 — `90009b5` Mon exemplaire : plus-value masquée sans Premium, au format du Premium
- Sans abonnement, la pastille de plus-value de « Mon exemplaire » reprend celle du Premium
  (flèche, montant seul, sans pourcentage) avec le montant masqué « +? € » ; le toucher ouvre
  l'offre Premium. Couleurs en dur remplacées par le design system, libellé VoiceOver ajouté.
- 6 fichiers, +49 / −10.

---

## 2026-10-17 — Finitions d'interface, abonnement, typographie centralisée

### 13:42 — `1492973` Ajoute un accès à la gestion de l'abonnement dans les Réglages
- Permet de vérifier et gérer l'abonnement Premium (par exemple un reste d'essai Sandbox) depuis
  TestFlight et la production, où les options développeur ne sont pas disponibles.
- 2 fichiers, +24.

### 13:42 — `3c42ee5` Corrige la disparition furtive d'un item wantlist tout juste ajouté
- Un rafraîchissement remplaçait toute la liste par la réponse serveur, qui pouvait ne pas encore
  contenir l'ajout optimiste : fusion au lieu du remplacement (même principe que la Collection).
- 1 fichier, +19 / −2.

### 13:43 — `0818462` Corrige les lignes de résultats de recherche partiellement cliquables et le scroll perdu au retour
- Zone cliquable du `NavigationLink` étendue à toute la ligne (`EmptyView()` avait une taille
  nulle) et suppression du conflit avec le geste de fermeture du clavier posé sur la liste.
- Plus de rechargement à chaque réapparition de la vue : la recherche ne repart que si la requête
  ou le filtre change, ce qui conserve la position de défilement au retour d'une fiche.
- 2 fichiers, +35 / −21.

### 14:18 — `a086da8` Harmonise le libellé et la couleur du badge « Collection »
- Même texte et même vert dans les résultats de recherche, la fiche artiste et son résumé, au lieu
  de « Collection » / « Possédé » pour la même notion.
- 4 fichiers, +34 / −7.

### 14:19 — `d4ed5e7` Resserre l'agencement du Carrousel et allège la barre de navigation rapide
- Indicateur de position déplacé sous les icônes d'action, bloc carrousel et barre alignés en haut
  (plus de grand vide), fond en capsule retiré de la barre de navigation rapide.
- 4 fichiers, +13 / −17.

### 14:19 — `6d9f2c8` Ajoute une bulle de confirmation à l'ajout/retrait collection et wantlist
- Bulle façon Apple Music affichée au-dessus de la barre d'onglets quel que soit l'écran d'origine,
  déclenchée depuis les points d'ajout/retrait centralisés de `LibraryMembershipStore`.
- 3 fichiers, +68 / −4.

### 14:19 — `3f14437` Ajoute les chaînes localisées manquantes pour les derniers changements
- 1 fichier, +21.

### 14:42 — `ce0712e` Met en place un système de typographie centralisé et corrige les textes trop petits
- Nouveau `Design/AppTypography.swift` : 4 jetons partagés (`inlineIcon`, `emphasisLabel`,
  `statHeadlineNumber`, `coverCornerBadge`) remplaçant des tailles en dur (6,5 à 32 pt) réparties
  dans une quinzaine de fichiers.
- Textes remontés au-dessus du seuil de lisibilité (barre A-Z à 9 pt, badge « PREMIUM » stylé de
  3 façons, phrase de la Live Activity à 9,5 pt) ; titre et artiste de « Mon exemplaire » agrandis.
- 16 fichiers, +74 / −35.

---

## 2026-10-16 — Patine vinyle, performances de la Collection, quota Discogs

### 08:39 — `bfd70d7` Affine les ombres et teintes de la patine vinyle (clair/sombre), supprime le moniteur de saccades
- Ombres et teintes de la patine vinyle revues en clair et en sombre, sous-titre stylé New York sur
  les titres de section, textes trop petits resserrés (Collection, exemplaires).
- Export CSV et PDF fusionnés en une seule fonctionnalité Premium ; moniteur de saccades
  (`ScrollHitchMonitor`) retiré, devenu inutile après les correctifs de performance.
- 15 fichiers, +210 / −167.

### 19:14 — `a665654` Corrige les perfs Collection (cache de dates, lots SwiftData), priorise le quota Discogs et sécurise les liens vers discogs.com
- Cache du parsing des dates d'ajout (615 ms mesurés dans Instruments pendant le défilement), lots
  d'écriture SwiftData réduits, attente du limiteur de débit plafonnée à 20 s.
- Les 6 synchronisations de fond passent enfin en priorité basse dans le limiteur Discogs (elles
  concurrençaient à égalité les actions de l'utilisateur) ; signposts ajoutés pour Instruments.
- Derniers liens directs vers discogs.com remplacés par la vue Safari à session isolée (pas de
  fuite de session entre comptes).
- Tags isolés dans `CollectionRow` (une édition invalidait toutes les lignes visibles) ; un second
  appui sur « démarrer l'écoute » n'incrémente plus le compteur.
- 20 fichiers, +259 / −79.

### 19:36 — `11499e1` Affiche un message quand un achat premium reste en attente de validation
- Cas « Demander à acheter » (partage familial) : la paywall restait figée sans retour ; un message
  explique désormais que l'achat attend une validation.
- 1 fichier, +8.

---

## 2026-10-15 — Gels et saccades corrigés, harmonisation des titres

### 17:55 — `0782f10` Corrige un gel au tri Rangement, factorise les carrousels Collection/Wantlist, thème Espresso
- Le tri « Meuble » relisait les préférences à chaque comparaison (jusqu'à O(n log n) fois) et
  restait sur le fil principal : gel de 700 à 900 ms au lancement sur une grande collection. Le
  contexte de tri est maintenant capturé une seule fois avant le tri détaché.
- Carrousels Collection/Wantlist factorisés, nouveau thème Espresso.
- 59 fichiers, +1 785 / −779.

### 19:30 — `8893a2b` Corrige les saccades de défilement identifiées par Instruments (Keychain, synchro SwiftData, suivi de section)
- Identifiants Discogs gardés en mémoire au lieu de relire le Keychain à chaque accès (41 sites
  d'appel, ~15-30 ms par lecture).
- Écritures SwiftData de la synchro de fond asynchrones et par lots, avec pauses : plus de blocage
  de plusieurs secondes à l'ouverture.
- Badges d'exemplaires précalculés (chaque ligne observait tout un dictionnaire) ; suivi de section
  allégé ; moniteur de saccades limité à un log par seconde.
- 15 fichiers, +198 / −96.

### 19:36 — `5bed042` Corrige les résultats de recherche non cliquables
- Le geste de fermeture du clavier posé sur toute la liste absorbait le toucher des lignes ;
  remplacé par un geste qui n'entre pas en conflit.
- 1 fichier, +6 / −1.

### 19:56 — `4875056` Corrige la navigation release dans l'alerte de prix, harmonise les titres (New York + SectionEyebrow), nettoie le profil Discogs
- L'en-tête de l'alerte de prix ouvre la fiche release (même correction de geste que la recherche).
- Titres de section au style `SectionEyebrow` dans l'alerte et tout l'onglet Réglages ; gros
  titres de Statistiques, Recherche et Réglages en New York.
- Profil Discogs : doublon nom/identifiant retiré.
- 6 fichiers, +49 / −35.

---

## 2026-10-14 — Cloisonnement multi-compte et factorisation

### 16:05 — `53d0892` Cloisonnement multi-compte des alertes, factorisation Collection/Wantlist, synchro iCloud étendue
- Alertes de prix isolées par compte (elles ne survivaient pas à la fermeture de l'app).
- Collection et Wantlist factorisées (`LibrarySectionsEngine`, `LibraryMosaicView`,
  `LibraryListView` génériques : ~700 lignes dupliquées supprimées) ; `StatsView` (2 176 lignes)
  et la fiche release (2 617 lignes) découpées par responsabilité.
- URLs discogs.com, animations et tailles de pochette centralisées ; protection de
  `CloudSyncEngine` contre une boucle d'envoi silencieuse.
- Appels réseau sortis des vues vers des view models/services ; compte Apple Music déconnecté à la
  déconnexion Discogs ; thème, apparence et durée de la Live Activity synchronisés via iCloud.
- Avertissements de build corrigés (`UIScreen.main` déprécié, `Sendable`).
- 76 fichiers, +5 889 / −4 548.

---

## 2026-10-11 — Discographie Discogs sur la fiche artiste

### 09:48 — `f487f93` Discographie Discogs sur la fiche artiste, liens vers les artistes, ajustements UI et corrections de tri
- Discographie Discogs (rôle principal, masters et releases orphelines) classée en Albums,
  Singles & EP, Compilations, Autres, avec cache permanent synchronisé iCloud et classement en
  tâche de fond à priorité basse ; elle remplace la discographie Apple Music.
- Noms d'artistes cliquables dans Collection, Wantlist et Stats.
- Barre de navigation rapide condensée et centrée, bulle de position, aperçu qui suit le doigt.
- Fiche exemplaire : section Plus-value, champs personnalisés redessinés ; guide de rangement
  ouvert quasi instantanément.
- Tri « Meuble » corrigé (année du pressage utilisée au lieu de l'année originale) ; tag conservé
  comme autonome quand on le retire de son dernier exemplaire.
- 35 fichiers, +2 341 / −757.

---

## 2026-10-10 — Page artiste Apple Music et fluidité des listes

### 13:26 — `9afee91` Page artiste alimentée par Apple Music, fiable et utilisable hors ligne
- Photo, nom, biographie et discographie issus d'Apple Music, par section, éditions regroupées,
  jusqu'à 500 albums ; badges Possédé/Wantlist mis à jour en direct.
- Choix fiable de l'artiste Apple Music (homonymes départagés par la collection), affichage
  progressif, accès refusé expliqué, fonctionnement hors ligne avec relance au retour du réseau.
- Design : fond teinté selon la photo, en-tête plafonné sur iPad, boutons Partager et Ouvrir dans
  Apple Music ; chaque artiste du titre d'une fiche album mène à sa page.
- 7 fichiers, +1 682 / −93.

### 13:26 — `027666d` Fluidité des listes : tri et couleur moyenne hors du fil principal, lignes resserrées
- Tri et regroupement de la Collection calculés hors du fil principal (300-400 ms à chaque page
  reçue), résultats périmés écartés par un compteur de génération.
- Couleur moyenne des pochettes calculée hors du fil principal ; marges réduites et en-têtes
  harmonisés entre Liste et Mosaïque.
- 12 fichiers, +173 / −49.

---

## 2026-10-09 — Lexique, tutoiement, traductions

### 12:50 — `84dfbd2` Lexique écoute/lecture, tutoiement, pluriels catalogue et anglais complet
- Vocabulaire séparé entre écoute sur platine (Listen) et lecture Apple Music (Play), en français
  et en anglais ; tous les textes affichés rendus traduisibles ; app entièrement au tutoiement.
- Vrais pluriels dans les catalogues ; anglais complété (292 nouvelles traductions, 35 reprises,
  177 clés obsolètes supprimées) ; nom de l'app et texte d'autorisation Apple Music corrigés.
- Cahier de recette v3.2 : nouvelle famille S (13 tests de langues et libellés).
- 66 fichiers, +6 062 / −3 313.

### 13:20 — `b120e84` Corrige le centrage du bouton « Disque au hasard » en vue carrousel
- Défilement vers la pochette tirée au sort calculé par position (index × largeur) au lieu de
  l'identité, qui échouait pour une carte jamais affichée ; plus de limite de cartes franchies.
- 1 fichier, +40 / −20.

---

## 2026-10-07 — Fiabilisation des stores, alertes et actions

### 10:02 — `0fa0945` Fiabilisation et performances : stores, alertes, actions, Stats, lecture, widgets
- Stores synchronisés : plus de plantage sur un tag en double, mises à jour groupées, une seule
  notification de préférences par réception iCloud.
- Alertes wantlist : vérification plus repoussée à chaque passage en arrière-plan, gestion de
  l'expiration de la tâche de fond, notifications fiabilisées.
- Actions collection/wantlist : erreurs classées (passagère → file, 404 → succès, définitive →
  annulation avec message), exemplaires ajoutés hors ligne correctement retirés ou déplacés.
- Stats, années de master et devises mises en cache ; lecture Apple Music fiabilisée ; en-têtes
  OAuth envoyés uniquement à discogs.com ; widget allégé.
- 30 fichiers, +985 / −365.

### 10:06 — `9a32c2b` Ajoute la dépendance SpinlogTests -> Spinlog
- Évite que la cible de tests soit compilée contre un ancien module de l'app.
- 1 fichier, +15.

### 20:37 — `c0f8608` Alertes vérifiées à l'ouverture, widget rechargé à la déconnexion, cahier de recette v3.1
- Alertes wantlist vérifiées au lancement et au retour au premier plan (au plus toutes les 15 min) ;
  widget rechargé à la déconnexion.
- Cahier de recette v3.1 : 312 tests (+83, dont 73 AUDIT), famille R (mise à jour et migration),
  données centralisées dans `tests.js`, PDF régénéré.
- 7 fichiers, +633 / −297.

---

## 2026-10-06 — Premier audit de code

### 22:55 — `36597f1` Corrections de l'audit de code + travail en cours
- Regroupe le travail en cours (fonctionnalités, marketing, QA) et les corrections du premier audit,
  imbriqués dans les mêmes fichiers.
- `CloudSyncEngine` : envoi limité à la zone du compte actif, cache des métadonnées serveur,
  nouveaux essais seulement sur échec passager, changements de compte iCloud gérés.
- File hors ligne rattachée au compte Discogs ; connexion OAuth fiabilisée ; Keychain accessible
  écran verrouillé avec migration ; disques supprimés sur discogs.com retirés après un parcours
  complet ; limiteur de débit et signature OAuth corrigés.
- Nouvelle cible `SpinlogTests` (Swift Testing, 18 tests).
- 154 fichiers, +33 377 / −3 102.

---

## 2026-09-28 — Page de support et secrets

### 19:31 — `881c5e2` Add support page for GitHub Pages (App Store support URL)
- Page de support publiée via GitHub Pages pour l'App Store, et premier versement de l'essentiel du
  code de l'app (fonctionnalités, modèles, réseau, design, widget).
- 123 fichiers, +12 159 / −18.

### 19:33 — `b7951c8` Fix .gitignore path and untrack Secrets.swift
- Chemin du `.gitignore` corrigé : `Spinlog/Secrets.swift` (identifiants Discogs, alors vides) n'est
  plus suivi par git.
- 2 fichiers, +1 / −12.

---

## 2026-09-11 — Création du projet

### 14:08 — `5375e37` Initial Commit
- Projet Xcode SwiftUI de départ (`MyApp`, `ContentView`, catalogue d'assets).
- 7 fichiers, +412.

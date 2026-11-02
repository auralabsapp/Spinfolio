# Captures App Store — suivi et procédure de reprise

Images « Aperçu d'app et captures d'écran » de la fiche App Store : 10 images de **1206 × 2622 px
uniquement** + une planche de comparaison. Elles sont produites par
`docs/appstore-screenshots/generate.py` à partir des captures brutes de `docs/appstore-screenshots/raw/`.

Ce fichier est dans `QA/` (non publié par GitHub Pages, contrairement à `docs/`). Il ne contient
**aucun identifiant ni mot de passe** : les garder dans le trousseau, jamais dans le dépôt.

## Série du 30 octobre 2026

Conditions communes : simulateur **iPhone 17** (iOS 27.0), écran natif 1206 × 2622, **compte Discogs réel
du développeur** (291 albums, Premium actif, palette Signature), barre d'état forcée à **09:41**
(batterie pleine, 4 barres, Wi-Fi), apparence **claire** sauf l'image 10. Build installé depuis Xcode juste
avant les captures (1-5 et 7-10 : build de 13 h 28 ; 6 : réinstallé à 18 h 43).

| N° | Fichier final | Capture brute | Écran | Conditions |
|---|---|---|---|---|
| 1 | `01-collection.png` | `01_mosaic.png` | Collection, mosaïque | Tri **Année, décroissant** |
| 2 | `02-carrousel.png` | `02_carousel.png` | Collection, carrousel | Tri **Date d'ajout**, centré sur *Californication* (RHCP), n° 183 sur 291 |
| 3 | `03-fiche-disque.png` | `03_release.png` | Fiche d'un disque | *Hurry Up, We're Dreaming* (M83), en collection, tag « Vinyle couleur » |
| 4 | `04-plus-value.png` | `04_instance.png` | « Mon exemplaire » (Premium) | *Fallen* (Evanescence, 2023) : payé 45,36 €, cote 101,91 €, plus-value +57 € |
| 5 | `05-rangement.png` | `05_shelf.png` | Guide de rangement (Premium) | *Let All That We Imagine Be The Light* (Garbage), n° 90 sur 287, voisins Fugees et Ghost |
| 6 | `06-alerte-prix.png` | `06_alert.png` | Feuille « Alerte de prix » (Premium) | *Thriller* (Michael Jackson), alerte à 25,00 € déjà enregistrée (arrivée par iCloud) |
| 7 | `07-statistiques.png` | `07_stats.png` | Statistiques (haut de page) | 291 albums, 6 en wantlist, 148 artistes |
| 8 | `08-valeur-palmares.png` | `08_value.png` | Stats : estimation, investi vs cote, palmarès (Premium) | Défilement : titre « Estimation de la collection » juste sous la barre ; écoutes présentes |
| 9 | `09-grades.png` | `09_grades.png` | Réglages › Mes grades (gratuit) | Grade « Disquaire », 291 / 500 |
| 10 | `10-theme-sombre.png` | `10_dark_list.png` | Collection, liste | Apparence **sombre**, tri **Date d'ajout** |

Choix de contenu à respecter (demandés par l'utilisateur) : mosaïque triée par année décroissante ; tous les
autres écrans en tri par date d'ajout ; capture sombre en affichage Liste ; pas d'image des thèmes de couleur
(fonction jugée secondaire) ; comptes et montants réels acceptés dans les images.

Les versions précédentes des images 3, 4, 5 et 6 n'ont pas été conservées dans le dépôt.

## Fonds des images (depuis le 30 octobre 2026)

Tous les fonds sont dans la famille de la palette **Signature** de l'app (violet 158/61/207, clair 210/122/245,
foncé 133/46/184 dans `AppTheme.swift`) et de l'orchidée de l'icône ; aucun bleu ni indigo. Chaque image a son
propre dégradé (angle, arrêts, halos) : 01 orchidée, 02 rose, 03 lavande, 04 prune, 05 magenta, 06 améthyste,
07 lilas, 08 pourpre, 09 aube, 10 nuit (sombre). Définis dans `PALETTES` de `generate.py` ; le script contrôle le
contraste du texte blanc sur le haut de chaque fond (≥ 4,5:1) et signale un fond trop clair. Version précédente
du script (fonds violet / indigo / bleu) : non conservée dans le dépôt.

## Captures pour la page web uniquement (30 octobre 2026)

Hors série App Store, rangées dans `docs/appstore-screenshots/raw/` et converties dans `docs/assets/site/` :
`11_apple_music.png` (simulateur, lecteur Apple Music sur *Absolution* de Muse, extrait de 30 s, 0:02 / −0:27) ;
`12_listen_cd.jpeg`, `13_listen_tape.jpeg`, `14_listen_vinyl.jpeg` (photos d'écran de l'iPhone du développeur,
feuille « Écoute sur platine » : CD *No Need To Argue*, cassette *Born In The U.S.A.*, vinyle *From Zero*),
détourées avec coins arrondis transparents (voir l'historique de la session : recadrage x 24-1182, rayon 190).

## Image de réserve : écoute sur platine (2 novembre 2026)

`docs/appstore-screenshots/reserve-ecoute-platine.png` (1206 × 2622), hors des 10 images et de la planche, gardée pour un
test A/B de la première image (« Optimisation de la page produit »). Générée par `generate.py` (`RESERVE_SLIDES`) :
accroche « Chaque écoute, sur le bon support ». Il n'existe pas de capture plein écran de la feuille d'écoute : la feuille
réelle du vinyle (*From Zero*, Linkin Park, photo de l'iPhone détourée : `docs/assets/site/ecoute-vinyle.webp`) est posée sur
la liste de la Collection (`raw/10_light_list.png`) assombrie, ce qui reproduit la présentation du système
(`compose_listening_screen`, écrit `raw/18_listen_screen.png`). Image **recomposée**, à signaler comme telle si l'App Store
la questionne ; pour une capture authentique, refaire l'image au simulateur (feuille ouverte depuis le mini-lecteur).

## Données personnelles visibles

Montants investis et cote de la collection (images 4 et 8), écoutes et classement (8), grade et taille de la
collection (7, 9), tags personnels (3, 4). À revoir avant toute republication si le contexte change.

## Procédure de reprise

1. **Simulateur** : iPhone 17, appareil déjà connecté au compte réel. Vérifier dans Réglages que le compte
   affiché est le bon (le simulateur peut être resté sur le compte vide de démonstration) ; sinon
   Réglages › Se déconnecter, puis Se connecter (page Discogs : identifiant et mot de passe, « Plus tard »
   pour le trousseau, « Reject All » pour les cookies, pas de code de sécurité demandé).
2. **Installer le build actuel** avant toute capture : `DeviceInteractionStartWorkspaceSession` sur le
   simulateur puis `DeviceInteractionInstallAndRun` sans argument. Ne pas utiliser `-uiTestDemo` (écraserait la
   session). Exception à la règle « ne jamais lancer l'app » : à signaler dans le compte rendu.
3. **Réglages du simulateur** :
   - `xcrun simctl status_bar <UDID> override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`
   - `xcrun simctl ui <UDID> appearance light` (ou `dark` pour l'image 10).
4. **Naviguer** avec `DeviceInteractionSynthesize` (coordonnées en points, écran 402 × 874), puis capturer en
   pleine résolution : `xcrun simctl io <UDID> screenshot --type=png docs/appstore-screenshots/raw/NN_nom.png`
   (la capture de l'outil, 402 × 874, ne convient pas).
5. **Régénérer** : `python3 docs/appstore-screenshots/generate.py` (Pillow ; écrit les 10 images et la planche).
6. **Vérifier** : chaque image fait bien 1206 × 2622, puis regarder la planche et les images refaites.
7. **Remettre le simulateur en état** : apparence claire, mosaïque, tri Artiste croissant ; ne pas laisser de
   brouillon ni d'alerte créés pour une capture (cas de l'image 6 : toucher une cote d'état remplit le seuil,
   puis « Annuler »).

## Pièges déjà rencontrés

- **Menu « Tri »** tronqué : « Croissant / Décroissant » est sous « Meuble ». Attendre environ 1 s entre deux
  appuis et faire défiler le menu avant de toucher « Décroissant » ; sinon l'appui tombe sur « Meuble ».
- **Carrousel** : l'index d'années ne réagit ni au toucher ni au glissement simulé ; balayer le carrousel
  (≈ 5 disques par balayage), puis lire « N sur 291 » dans la hiérarchie.
- **Barre d'onglets** réduite en deux bulles après un défilement : toucher la bulle de gauche pour la déplier
  avant de changer d'onglet ; un appui à y ≈ 822 peut sinon ouvrir Réglages ou le paywall.
- **Réglages** : « Se déconnecter » et « Supprimer mon compte… » sont voisins en bas de page ; viser la ligne
  exacte d'après la hiérarchie.
- **Classement « Les plus écoutés »** capte le défilement : faire défiler depuis une zone hors de la liste.
- **Session d'interaction** fermée seule après une longue pause : en rouvrir une
  (`DeviceInteractionStartSession` + `activationBundleId`) sans réinstaller.
- **Paywall** : la page d'abonnement échoue au simulateur sans configuration StoreKit ; ne pas la capturer.
- **Police des titres** : New York Bold n'a pas de trait d'union ; `generate.py` le dessine à la main.
- **Titres de l'app** : ne pas citer « 8 palettes » (Signature + 9 Premium).

## Autres sources

- Procédure détaillée et historique des passes : mémoire de l'assistant (`project_appstore_screenshots`).
- Une ancienne génération (2e passe du 21 octobre) a servi aux images de la page web `docs/assets/site/`, non
  mises à jour depuis.

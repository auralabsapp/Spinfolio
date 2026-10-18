# Journal de bord — Spinfolio (Spinlog)

Détail des évolutions **commitées**, jour par jour, du plus récent au plus ancien.
Mis à jour chaque jour où des commits sont faits (une entrée par jour, un paragraphe par commit).
Source : historique git (`git log`). Les volumes indiqués sont ceux de `git --shortstat`.

---

## 2026-10-18 — Audit complet, mode démo, tests automatiques, règles du projet

Journée consacrée à l'aboutissement de l'audit de l'app (branche `audit-fixes`) : préparation de la
soumission App Store, mode démo pour App Review, fiabilité des données, accessibilité, découpage des
plus gros fichiers, mise en place des tests automatiques et d'un cadre de règles pour la suite.

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

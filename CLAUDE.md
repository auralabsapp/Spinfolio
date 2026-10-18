# Spinfolio (Spinlog) — Règles d'implémentation

Cadre à respecter pour toute nouvelle fonctionnalité, correction ou refonte. En cas de doute entre
deux options, choisir celle qui ressemble le plus au code existant. Toute exception à ces règles
doit être signalée explicitement dans le compte rendu, jamais faite en silence.

Application iOS (SwiftUI) de gestion de collection de vinyles/CD/K7 basée sur l'API Discogs.
Code dans `Spinlog/`, widget et Live Activity dans `SpinlogWidgets/`, tests dans `SpinlogTests/`
(unitaires) et `SpinlogUITests/` (interface), cahier de recette manuel dans `QA/`.

---

## 0. Méthode de travail (non négociable)

- **Langue** : répondre en français ; code, noms de types et identifiants en anglais ; commentaires
  et textes d'interface en français (langue source du catalogue).
- **Ne jamais lancer l'app** (`RunProject`) : l'utilisateur teste lui-même sur appareil. Valider
  avec `BuildProject`, `XcodeRefreshCodeIssuesInFile`, et les tests (`RunAllTests` / `RunSomeTests`
  sur un **Simulateur** — la destination « Any iOS Device » n'exécute aucun test).
- **Ne jamais committer sans demande explicite.** Lors d'un commit, exclure systématiquement
  `Marketing/`, `Instruments/`, `assets/`, `docs/assets/`, `index.html`. Ne jamais pousser sans demande.
- **Secrets** : `Spinlog/Secrets.swift` est ignoré par git ; ne jamais afficher ses valeurs, les
  copier ailleurs, ni les écrire en mémoire ou dans un log.
- **Périmètre** : ne modifier que ce qui est demandé. Une amélioration repérée en chemin est
  proposée, pas appliquée d'office.
- **Décisions produit** (comportement visible, Premium, données utilisateur, réglages de projet
  sensibles comme la signature ou les identifiants de bundle) : proposer et demander avant de coder.
- **Compte rendu honnête** : dire ce qui a été vérifié (build, tests) et ce qui ne l'a pas été
  (rien n'est testé sur appareil tant que l'utilisateur ne l'a pas fait).
- **Tests manuels** : tout nouveau cas à vérifier sur appareil est ajouté dans `QA/tests.js`
  (tag `AUDIT` si lié à la branche en cours, `AUTO` si couvert par un test automatique), puis le
  PDF est régénéré (commande en tête de `QA/print.html`).

## 1. Architecture

- **Organisation** : un dossier par fonctionnalité dans `Spinlog/Features/<Domaine>/`
  (`Collection`, `Wantlist`, `Search`, `Stats`, `Settings`, `Shelf`, `LiveActivity`, `Root`),
  services et stores transverses dans `Features/Shared/`, composants visuels réutilisables et
  jetons de design dans `Spinlog/Design/`, modèles Discogs dans `Spinlog/Models/`, réseau dans
  `Spinlog/Networking/`. Les groupes Xcode sont synchronisés : un fichier créé dans le bon dossier
  est inclus automatiquement.
- **Couches** : Vue SwiftUI → view model `@Observable @MainActor` → services/stores partagés
  (`DiscogsAPIClient`, `LocalDataStore`, `OfflineSyncQueue`, `TagStore`, `CloudSyncEngine`…).
  Une vue n'appelle jamais `DiscogsAPIClient` directement.
- **État partagé** : `@Observable` (jamais `ObservableObject`/Combine). Singletons `.shared`
  pour les stores qui vivent toute la session, comme le code existant.
- **Accès Discogs** : uniquement via `DiscogsAPIClient` + `DiscogsEndpoints` (signature OAuth,
  limiteur de débit `DiscogsRateLimiter`, 60 req/min). Les tâches de fond utilisent la priorité
  `.background` du limiteur (`DiscogsRateLimiter.$priority.withValue(.background)`).
- **Écritures vers Discogs** : passer par les chemins existants (`ReleaseActions`,
  view models Collection/Wantlist), qui gèrent mise à jour optimiste, annulation en cas de refus,
  file hors ligne (`OfflineSyncQueue`) et mode démo. Ne pas recoder ce circuit.
- **Erreurs réseau** : distinguer passagère (`error.isTransientNetworkFailure` → mise en file /
  nouvel essai) et définitive (message à l'utilisateur, état restauré). `isNotFound` sur un retrait
  = objectif atteint.
- **Cache local** : SwiftData via `LocalDataStore` (jetable, TTL 6 h, jamais synchronisé
  CloudKit). Données utilisateur à garder entre appareils (tags, écoutes, préférences durables,
  alertes) : stores dédiés + `CloudSyncEngine`, isolés par compte (`setActiveUsername`).
- **Constantes et textes partagés** : `AppConstants.swift` (`DiscogsConstants`, `AppMessages`,
  App Group…). Pas de chaîne magique ou de clé `UserDefaults` recopiée à la main.
- **Encapsulation** : garder `private` / `private(set)` ; ne pas élargir l'accès pour découper un
  fichier. Un découpage qui exigerait de rendre un état modifiable partout doit passer par une
  vraie extraction (sous-vue avec paramètres explicites, fonction pure), sinon il ne se fait pas.
- **Taille des fichiers** : viser < 500 lignes ; au-delà, extraire sous-vues et types
  indépendants dans leur propre fichier. Un type public par fichier, sauf petits types privés liés.
- **Pas de nouvelle dépendance** (Swift Package) sans accord. Seule dépendance : Kingfisher.

## 2. Concurrence

- Les 4 cibles sont en **Swift 6** (vérification stricte de la concurrence) : aucun avertissement
  ni erreur d'isolation n'est toléré. `nonisolated(unsafe)` et `@preconcurrency import` sont
  réservés aux types système sûrs entre fils mais pas encore annotés `Sendable` (`Notification`,
  formatters, `NSCache`, `Activity`…), toujours accompagnés d'un commentaire qui le justifie.
  Un rappel système exécuté hors du fil principal (tâche de fond, réseau, OAuth) doit être
  `@Sendable` ou planifié sur la file principale, sinon l'app s'arrête à l'exécution.
- La cible a `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` : tout est `@MainActor` par défaut.
  Marquer `nonisolated` ce qui doit tourner ailleurs (décodage, calculs purs, `Codable` des modèles
  décodés en arrière-plan — voir `CollectionItem`).
- `async/await` uniquement : pas de Combine, pas de `DispatchQueue` sauf contrainte d'API.
- Travail lourd (décodage volumineux, tri de grosses collections) hors du fil principal via
  `Task.detached` ou fonctions `nonisolated`, comme `requestDecodingInBackground`.
- Toute boucle longue ou tâche annulable vérifie `Task.isCancelled` ; garder une référence à la
  `Task` pour l'annuler (changement de dossier, de compte, de vue).
- Après chaque `await`, revérifier que le contexte est toujours valide (même compte, même dossier)
  avant d'appliquer un résultat — voir `fetchPage` dans `CollectionViewModel`.
- Tâches iOS en arrière-plan : un seul identifiant déclaré (`wantlistAlertsTaskIdentifier`) ;
  toujours fournir un `expirationHandler` et appeler `setTaskCompleted`.

## 3. Performance (SwiftUI et données)

- **Invalidation** : une vue ne lit que ce qu'elle affiche. Pas de dictionnaire observé lu par
  chaque ligne d'une liste ; préférer des valeurs calculées une fois et mises en cache dans le
  view model (cf. `LibraryMembershipStore`, classements de `StatsViewModel`).
- **Listes** : `ForEach` avec identité stable (`id` du modèle, `instanceId` pour un exemplaire),
  jamais `\.self` sur des valeurs non uniques ni les indices. Pas de filtre/tri en ligne dans
  `body` : calculer dans le view model et mettre en cache.
- **Pas de travail dans `body`** : pas de formatter créé à chaque rendu (formatters `static`),
  pas d'accès disque/Keychain/UserDefaults dans une propriété lue à chaque rendu.
- **Images** : `AsyncCoverImage` (cache Kingfisher, taille cible adaptée). Ne pas utiliser
  `AsyncImage` ni télécharger une pochette à la main.
- **Réseau** : pagination paresseuse pour les écrans de liste ; chargement complet
  (`fetchAllCollectionItems`) seulement pour les besoins ponctuels (stats, export), avec la garde
  anti-doublon de `LocalDataStore` (`beginFullCollectionSync`).
- Mesurer avant d'optimiser un point non évident ; ne pas introduire de cache sans stratégie
  d'invalidation.

## 4. Interface et design system

- **Jetons obligatoires** : couleurs de `AppColors.swift` (`spinlogPink`, `appBackground`,
  `appSecondaryText`, `appSeparator`, dégradés or pour le Premium…) ; typographie de
  `AppTypography.swift` (`.inlineIcon`, `.emphasisLabel`, `.coverCornerBadge`…, sinon styles
  système `.body`, `.footnote`…) ; rayons de `AppLayout.swift` ; animations de
  `AppAnimations.swift`. Aucune couleur RGB ni taille de police en dur hors de ces fichiers.
- **Lisibilité** : aucun texte réel sous 11 pt ; privilégier les styles de texte système pour
  suivre la taille de texte de l'utilisateur.
- **Composants à réutiliser** avant d'en créer un nouveau : `SectionEyebrow`,
  `appleMusicGroupedCard()`, `GroupedListCard`, `SheetCloseButton`, `PremiumLockedCard`,
  `OfflineBannerView`, `StatusBadgeView`, `LibraryListView`/`LibraryMosaicView`/`LibraryCarouselView`,
  `serifNavigationTitle()`, `errorAlert` / `messageAlert`, `LibraryToastBubble`.
- **Feuilles (sheets)** : `.presentationDetents([.medium, .large])` +
  `.presentationDragIndicator(.visible)` + `SheetCloseButton`, comme les feuilles existantes.
  Présenter avec `sheet(item:)`, jamais un `Bool` + un état de données séparé (risque d'ouvrir une
  feuille vide).
- **Messages** : un résultat d'action passe par une alerte visible (`messageAlert`) ou la bulle
  `LibraryToastBubble` ; jamais un `errorMessage` affiché seulement quand la liste est vide.
- **Actions sur une ligne** : `.swipeActions` + `swipeActionsContainerIfAvailable()` hors `List`,
  **toujours doublées d'un `.contextMenu`** (seul moyen sur iOS 26). Textes d'aide adaptés via
  `SwipeActionsSupport.isAvailable`.
- **Actions destructives** : confirmation (`confirmationDialog`) avant suppression ; jamais de
  perte silencieuse de données (cf. scan par lot conservé, confirmation de fermeture).
- **Retour haptique** : celui déjà utilisé pour la même famille d'action
  (`UIImpactFeedbackGenerator` léger/moyen, `UINotificationFeedbackGenerator` pour un succès).
- **Navigation** : destinations via `SearchDestination` et `TabNavigationCoordinator` ; une nouvelle
  pile d'onglet doit gérer le re-tap (retour racine / haut de page).
- Pour une API SwiftUI récente ou inconnue (Liquid Glass, iOS 27…), chercher dans la documentation
  Apple (`DocumentationSearch`) avant de l'utiliser.

## 5. Accessibilité

- Tout bouton à icône seule a un `accessibilityLabel`. Un élément personnalisé interactif expose
  ses traits (`.isButton`, `.isSelected`…) et une action VoiceOver.
- Un geste personnalisé (glissé, appui long seul) a toujours une alternative VoiceOver
  (`accessibilityAdjustableAction`, `accessibilityAction`) — cf. barres A-Z et mode sélection.
- Un calque transparent qui intercepte les touches doit être accessible, et masquer pour VoiceOver
  l'élément qu'il recouvre.
- Pas d'information portée uniquement par la couleur.
- Les identifiants pour les tests (`accessibilityIdentifier`) sont autorisés et n'altèrent rien.

## 6. Textes et localisation

- Langue source : français (tutoiement). Chaque nouveau texte reçoit sa traduction anglaise dans
  `Spinlog/Localizable.xcstrings` (ou `SpinlogWidgets/…`), via les outils String Catalog — ne pas
  éditer le JSON à la main.
- Dans une vue : littéral direct (`Text("…")`, `Button("…")`) ; hors vue : `String(localized:)`.
  Jamais `Text(condition ? "a" : "b")` (devient une `String` non traduite) : écrire
  `condition ? Text("a") : Text("b")`.
- Nombres + nom comptable : variations de pluriel dans le catalogue (source et cible).
- Lexique : « écoute (sur platine) » ≠ « lecture (Apple Music) » ; « exemplaire » = copy ;
  « disque »/« album » ; « wantlist » ; garder les noms Discogs All/Uncategorized.
- Messages réutilisables dans `AppMessages`.

## 7. Contextes transverses à vérifier pour chaque fonctionnalité

Pour toute fonctionnalité qui lit ou écrit des données, se poser ces questions et les traiter :

1. **Premium** : réservée ? Lire `PremiumStore.shared.isPremium` (accès) ; pour décider d'afficher
   l'offre, `hasSubscription`. Carte `PremiumLockedCard` pour le verrou. Penser à la dégradation
   (perte d'abonnement).
2. **Mode démo** (`DemoMode.isActive`) : toute écriture vers Discogs est bloquée **avant** la mise
   à jour optimiste, avec `AppMessages.demoAddBlocked` / `demoRemovalBlocked` /
   `demoModificationBlocked`. Pas de synchro iCloud en démo. Une nouvelle route Discogs liée au
   compte doit être servie par `DemoServer` (et `DemoLibrary.json` si besoin de données).
3. **Hors ligne** : comportement sans réseau (lecture seule sur cache > 6 h, mise en file sinon) ;
   bannière `OfflineBannerView` si l'écran dépend du réseau ; ne jamais fermer un écran ni perdre
   une saisie à la perte du réseau.
4. **Multi-compte** : données isolées par nom d'utilisateur ; vidage à la déconnexion
   (`DiscogsAuthManager.logout`) ; aucune action rejouée sur le mauvais compte.
5. **iCloud** : la donnée doit-elle suivre l'utilisateur sur ses appareils ? Si oui, passer par
   `CloudSyncEngine` (nouveau `SyncedRecordKind`), avec fusion et isolation par compte.
6. **Widget / Live Activity** : la donnée affichée par le widget doit-elle être mise à jour
   (`WidgetSnapshotStore`, `WidgetCenter.reloadTimelines`) ?
7. **Arrière-plan** : un minuteur ne tourne pas app suspendue ; prévoir l'état au retour au
   premier plan (`scenePhase == .active`) ou une `staleDate`.

## 8. Sécurité et confidentialité

- Identifiants dans le Keychain (`KeychainStore`) uniquement ; rien de sensible dans
  `UserDefaults` ni dans les logs.
- Logs via `Logger` (OSLog). Données personnelles (nom d'utilisateur, artistes, titres) en
  `privacy: .private` (ou `.private(mask: .hash)` pour pouvoir corréler) ; `.public` seulement
  pour du technique (codes, compteurs, états).
- Nouvelle API à justification obligatoire (UserDefaults, dates de fichiers, espace disque…) ou
  nouvelle donnée collectée : mettre à jour les deux `PrivacyInfo.xcprivacy` (app et widget).
- Pas de chiffrement non exempté (sinon revoir `ITSAppUsesNonExemptEncryption`).

## 9. Compatibilité

- Cible minimale **iOS 26.1** (SDK iOS 27). Toute API iOS 27 est protégée par
  `if #available(iOS 27.0, *)` avec un repli fonctionnel (pas seulement « rien »).
- iPhone uniquement, portrait.
- Code réservé aux tests ou au développement entouré de `#if DEBUG`
  (cf. `UITestLaunchOptions`, options développeur).

## 10. Tests

- **Unitaires** (`SpinlogTests`, framework Swift Testing `@Test`/`#expect`) : toute règle métier
  nouvelle ou modifiée (calcul, tri, parsing, classification, règle de nouvel essai…) est testée.
  Un fichier par domaine. Extraire la règle en fonction pure (`static`/`nonisolated`) plutôt que
  tester à travers un singleton ; injecter `UserDefaults`/`Date` si nécessaire.
- **Interface** (`SpinlogUITests`, XCUIAutomation) : seulement les parcours clés, sur le mode démo
  (`-uiTestDemo`, `-uiTestSignedOut`), ciblés par `accessibilityIdentifier`. 5 à 10 parcours max.
- **Manuels** : ce qui exige un appareil (caméra, iCloud 2 appareils, Live Activity, widget,
  StoreKit sandbox, OAuth réel, VoiceOver ressenti) va dans `QA/tests.js`.
- Avant de rendre : `BuildProject` sans erreur **ni avertissement nouveau**, et tous les tests
  verts (lancer au minimum les suites touchées).

## 11. Style de code

- Indentation 4 espaces ; `PascalCase` pour les types, `camelCase` pour le reste.
- `@State private var` pour l'état local de vue ; `let` dès que possible ; pas de force unwrap
  (sauf URL littérale constante).
- Commentaires en français, au même niveau de détail que le code voisin : expliquer le **pourquoi**
  (contrainte, bug évité), pas le quoi.
- Pas de code mort, pas de `print` (utiliser `Logger`), pas de TODO laissé sans le signaler.

## 12. Pièges déjà rencontrés (ne pas les réintroduire)

- `sheet`/`fullScreenCover` pilotés par un `Bool` + données séparées → feuille vide : utiliser `item:`.
- `dismissSearch` lu sur la vue parente ne fonctionne pas : le lire dans un `ViewModifier` enfant
  placé avant `.searchable()`.
- `NavigationLink` avec `EmptyView()` (zone de toucher nulle) et gestes posés sur toute la `List`
  cassent le toucher des lignes : vérifier les deux.
- Remplacements de texte en masse (sed/regex) : relire le diff, ils ont déjà créé une récursion
  infinie silencieuse.
- `CKSyncEngineDelegate` (et tout protocole `Sendable`) doit être adopté dans le fichier de la
  classe.
- Tests push CloudKit : peu fiables en Simulateur / « Designed for iPad », utiliser 2 appareils.

## 13. Checklist avant de rendre une fonctionnalité

- [ ] Périmètre respecté, décisions produit validées avec l'utilisateur
- [ ] Architecture : bonne couche, bon dossier, composants et jetons réutilisés
- [ ] Contextes : Premium, démo, hors ligne, multi-compte, iCloud, widget, arrière-plan (§7)
- [ ] Performance : pas de travail dans `body`, identité de liste stable, caches invalidés
- [ ] Accessibilité : libellés, alternatives VoiceOver aux gestes, contraste, ≥ 11 pt
- [ ] Textes : français + anglais dans le catalogue, pluriels, pas de ternaire de `String`
- [ ] Confidentialité : logs `.private`, manifeste à jour si besoin
- [ ] iOS 26.1 : `#available` + repli, menu contextuel pour les balayages
- [ ] Tests unitaires ajoutés/ajustés, suites vertes, build sans nouvel avertissement
- [ ] Cas manuels ajoutés dans `QA/tests.js` si un appareil est nécessaire
- [ ] Compte rendu : ce qui est vérifié, ce qui ne l'est pas ; pas de commit sans demande

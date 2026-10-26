import SwiftUI

/// Actions possibles sur un exemplaire de la Collection, communes au balayage de la liste, au
/// menu de l'appui long et aux boutons du carrousel. Les fermetures modifient l'état de
/// `CollectionView` (feuilles, confirmations) qui les fournit.
struct CollectionItemActions {
    let isPlaying: (CollectionItem) -> Bool
    let showShelf: (CollectionItem) -> Void
    let edit: (CollectionItem) -> Void
    let requestDeletion: (CollectionItem) -> Void

    static func startListening(to item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NowPlayingActivityManager.shared.startListening(
            releaseId: item.releaseId,
            albumTitle: item.basicInformation.title,
            artistName: item.basicInformation.artistNames,
            coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
        )
    }

    static func stopListening(to item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await NowPlayingActivityManager.shared.endActivity(for: item.releaseId)
        }
    }

    func toggleListening(_ item: CollectionItem) {
        if isPlaying(item) {
            Self.stopListening(to: item)
        } else {
            Self.startListening(to: item)
        }
    }
}

/// Menu de l'appui long sur un exemplaire (liste, mosaïque, carrousel) : mêmes actions que le
/// balayage, qui n'existe pas hors `List` sur iOS 26 — voir `LibraryListView`.
struct CollectionItemContextMenu: View {
    let item: CollectionItem
    let actions: CollectionItemActions
    /// Hors ligne avec des données de plus de 6 h, comme les balayages de la liste : ni
    /// modification ni suppression sur un état peut-être périmé.
    let allowsChanges: Bool

    var body: some View {
        if actions.isPlaying(item) {
            Button {
                CollectionItemActions.stopListening(to: item)
            } label: {
                Label("Arrêter l'écoute", systemImage: "stop.fill")
            }
        } else {
            Button {
                CollectionItemActions.startListening(to: item)
            } label: {
                Label("J'écoute ce disque sur la platine", systemImage: "opticaldisc.fill")
            }
        }

        Button {
            actions.showShelf(item)
        } label: {
            Label("Où ranger", systemImage: "books.vertical.fill")
        }

        if allowsChanges {
            Button {
                actions.edit(item)
            } label: {
                Label("Modifier la note et les commentaires", systemImage: "pencil")
            }

            Button(role: .destructive) {
                actions.requestDeletion(item)
            } label: {
                Label("Supprimer de la collection", systemImage: "trash")
            }
        }
    }
}

/// Balayage vers la droite d'une ligne : écoute sur platine et guide de rangement.
struct CollectionLeadingSwipeActions: View {
    let item: CollectionItem
    let actions: CollectionItemActions

    var body: some View {
        if actions.isPlaying(item) {
            Button {
                CollectionItemActions.stopListening(to: item)
            } label: {
                Label("Arrêter l'écoute", systemImage: "stop.fill")
            }
            .tint(Color(uiColor: .systemGray))
        } else {
            Button {
                CollectionItemActions.startListening(to: item)
            } label: {
                Label("J'écoute", systemImage: "opticaldisc.fill")
            }
            .tint(Color.spinlogPink)
        }

        Button {
            actions.showShelf(item)
        } label: {
            Label("Ranger", systemImage: "books.vertical.fill")
        }
        .tint(.indigo)
    }
}

/// Balayage vers la gauche d'une ligne : suppression (avec confirmation) et modification.
struct CollectionTrailingSwipeActions: View {
    let item: CollectionItem
    let actions: CollectionItemActions

    var body: some View {
        Button(role: .destructive) {
            actions.requestDeletion(item)
        } label: {
            Label("Supprimer", systemImage: "trash.fill")
        }
        .tint(.red)

        Button {
            actions.edit(item)
        } label: {
            Label("Modifier", systemImage: "pencil")
        }
        .tint(.orange)
    }
}

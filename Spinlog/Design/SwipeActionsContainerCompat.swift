import SwiftUI

/// Les textes d'aide qui invitent à balayer une ligne doivent s'adapter : sur iOS 26, ces mêmes
/// actions passent par un appui long (menu contextuel).
enum SwipeActionsSupport {
    static var isAvailable: Bool {
        if #available(iOS 27.0, *) {
            return true
        } else {
            return false
        }
    }
}

extension View {
    /// `swipeActionsContainer()` n'existe qu'à partir d'iOS 27 : sans lui, les `.swipeActions`
    /// posés hors d'une `List` sont simplement ignorés. Sur iOS 26, chaque écran concerné
    /// propose les mêmes actions via un `.contextMenu` (appui long), qui sert alors de repli.
    @ViewBuilder
    func swipeActionsContainerIfAvailable() -> some View {
        if #available(iOS 27.0, *) {
            swipeActionsContainer()
        } else {
            self
        }
    }
}

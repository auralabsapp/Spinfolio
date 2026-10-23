import SwiftUI

/// Remplace `.refreshable` sur les listes : même geste de tirage, mais une fois la synchronisation
/// finie, une pastille « À jour » apparaît brièvement en haut avec un léger retour haptique — le
/// tirage reste sinon muet quand il n'y a rien de nouveau. Rien n'est affiché sans réseau : la
/// synchronisation n'a alors pas eu lieu et ne doit pas se prétendre à jour.
private struct LibraryRefreshConfirmationModifier: ViewModifier {
    let action: () async -> Void

    @State private var showsConfirmation = false
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .refreshable {
                await action()
                guard !Task.isCancelled, NetworkMonitor.shared.isConnected else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showConfirmation()
            }
            .overlay(alignment: .top) {
                if showsConfirmation {
                    Label("À jour", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.gainPositive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
    }

    private func showConfirmation() {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showsConfirmation = true }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { showsConfirmation = false }
        }
    }
}

extension View {
    /// `.refreshable` suivi d'une pastille « À jour » (voir `LibraryRefreshConfirmationModifier`).
    func libraryRefreshable(_ action: @escaping () async -> Void) -> some View {
        modifier(LibraryRefreshConfirmationModifier(action: action))
    }
}

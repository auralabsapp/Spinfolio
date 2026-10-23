import SwiftUI

/// Disque noir dessiné (sillons, étiquette rose) qui tourne lentement, avec un petit symbole en
/// pastille : illustration des écrans vides. Sans « Réduire les animations », le disque est fixe.
private struct EmptyStateDisc: View {
    let symbol: String

    private static let diameter: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.88))
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    // Sillons : quelques anneaux fins concentriques.
                    ZStack {
                        ForEach([0.88, 0.74, 0.60], id: \.self) { ratio in
                            Circle()
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                                .frame(width: Self.diameter * ratio, height: Self.diameter * ratio)
                        }
                    }
                )
                .overlay(
                    // Reflet : un secteur clair qui fait sentir la rotation.
                    Circle()
                        .trim(from: 0.05, to: 0.18)
                        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: Self.diameter * 0.74, height: Self.diameter * 0.74)
                )
                .overlay(
                    Circle()
                        .fill(Color.spinlogPink)
                        .frame(width: Self.diameter * 0.34, height: Self.diameter * 0.34)
                        .overlay(
                            Circle()
                                .fill(Color.black.opacity(0.85))
                                .frame(width: Self.diameter * 0.06, height: Self.diameter * 0.06)
                        )
                )
                .frame(width: Self.diameter, height: Self.diameter)
                .continuousRotation(isActive: true, rpm: RecordSpin.rpm33 / 2)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.spinlogPink)
                .frame(width: 36, height: 36)
                .background(Color.appBackground, in: Circle())
                .overlay(Circle().strokeBorder(Color.appSeparator.opacity(0.3), lineWidth: 1))
                .offset(x: 6, y: 6)
        }
        .accessibilityHidden(true)
    }
}

/// État vide des listes (Collection, Wantlist…) : disque qui tourne, titre, explication et action.
/// Même structure que `ContentUnavailableView`, dont il reprend la mise en page et l'accessibilité.
struct LibraryEmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                EmptyStateDisc(symbol: symbol)
                    .padding(.bottom, 4)
                Text(title)
                    .font(.title2.bold())
            }
        } description: {
            Text(message)
        } actions: {
            actions()
        }
    }
}

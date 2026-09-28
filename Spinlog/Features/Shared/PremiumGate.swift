import SwiftUI

/// Carte compacte affichée à la place d'une fonctionnalité réservée aux comptes premium
/// (`PremiumStore.shared.isPremium == false`), dans le même style que les autres cartes
/// (`.appleMusicGroupedCard()`).
struct PremiumLockedCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appleMusicGroupedCard()
    }
}

/// Alerte générique à présenter quand une action est bloquée par le statut premium
/// (ex. tap sur un bouton désactivé).
extension View {
    func premiumUpsellAlert(isPresented: Binding<Bool>, feature: String) -> some View {
        alert("Fonctionnalité premium", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(feature) est réservé aux comptes premium. Active le compte premium dans Réglages pour en profiter.")
        }
    }
}

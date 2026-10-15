import SwiftUI

/// Bandeau persistant affiché en haut des vues de collection et wantlist lorsque l'appareil est
/// hors ligne et que les données en cache dépassent le TTL de 6 heures (Option B conforme aux CGU Discogs).
struct OfflineBannerView: View {
    var lastSyncDate: Date? = nil
    var itemCount: Int? = nil
    var customMessage: String? = nil

    @State private var showingInfoSheet = false

    var body: some View {
        Button {
            showingInfoSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Mode hors ligne")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if let custom = customMessage {
                        Text(custom)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let date = lastSyncDate {
                        let countText = (itemCount ?? 0) > 0 ? " • " + String(localized: "\(itemCount ?? 0) albums") : ""
                        Text("Instantané archivé du \(formattedDate(date))\(countText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Données archivées localement • Reconnexion requise pour actualiser")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.8)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingInfoSheet) {
            offlineInfoSheet
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var offlineInfoSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 24)

                Text("Mode Hors Ligne")
                    .font(.title2.weight(.bold))

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.teal)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Archive locale")
                                .font(.subheadline.weight(.semibold))
                            Text("Ta collection et tes pochettes sont sauvegardées sur ton appareil pour rester accessibles sans connexion réseau.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Synchronisation automatique")
                                .font(.subheadline.weight(.semibold))
                            Text("Tu consultes ta discothèque sauvegardée sur cet appareil. Dès le retour d'une connexion Internet, \(AppInfo.name) réactualisera automatiquement ta collection et les cotes du marché.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                Spacer()
            }
            .background(Color.appBackground)
            .navigationTitle("À propos du hors ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton {
                        showingInfoSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

import SwiftUI

/// Sections crédits et notes personnelles de la fiche release — extrait de
/// ReleaseDetailView.swift, voir le commentaire sur `ReleaseDetailSheets`.
struct CreditsSection: View {
    let credits: [ReleaseArtist]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Crédits", icon: "person.2.fill")
            VStack(spacing: 0) {
                ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                    HStack(alignment: .center, spacing: 12) {
                        // 1. Libellé (Rôle) d'abord, standard .subheadline (noir/régulier) identique à Fabrication
                        Text(credit.role.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Crédit"))
                            .font(.subheadline)
                            .frame(minWidth: 80, alignment: .leading)

                        Spacer(minLength: 8)

                        // 2. Valeur (Nom de l'artiste) ensuite, avec navigation
                        NavigationLink(value: SearchDestination.artist(credit.id)) {
                            HStack(spacing: 4) {
                                Text(credit.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appSecondaryText)
                                    .multilineTextAlignment(.trailing)

                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.appTertiaryText)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if index < credits.count - 1 {
                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                    }
                }
            }
            .padding(.vertical, 4)
            .appleMusicGroupedCard()
        }
    }
}

struct NotesSection: View {
    let notes: String
    @State private var isExpanded = false

    private var isLongNote: Bool {
        notes.count > 180 || notes.components(separatedBy: .newlines).count > 5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Notes", icon: "note.text", style: .subsection)

            VStack(alignment: .leading, spacing: 10) {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLongNote {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Afficher moins" : "Afficher plus")
                                .font(.caption.weight(.semibold))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Color.spinlogPink)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
            .contentShape(Rectangle())
            .onTapGesture {
                if isLongNote {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                }
            }
        }
    }
}

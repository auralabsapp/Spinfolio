import SwiftUI

/// Saisie rapide, album par album, du prix d'achat et de l'état du disque des albums qu'un ajout
/// vient de créer. « Passer » laisse un album tel quel (il reste retrouvable avec le filtre
/// « À compléter » de la Collection) ; fermer la feuille arrête là sans rien perdre : ce qui est
/// enregistré l'est déjà.
struct BatchCompletionSheet: View {
    let request: BatchCompletionRequest

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var amountText = ""
    @State private var currency: String
    @State private var condition: RecordGrade?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(request: BatchCompletionRequest) {
        self.request = request
        _currency = State(initialValue: CollectionPreferencesStore.defaultCurrency(for: request.username))
    }

    private var current: CollectionItem { request.items[index] }
    private var isLast: Bool { index == request.items.count - 1 }

    private var price: (amount: Double, currency: String)? {
        BatchCompletion.parsedPrice(amountText: amountText, currency: currency)
    }

    /// Quelque chose à enregistrer : un prix lisible ou un état choisi.
    private var hasValues: Bool { price != nil || condition != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    PriceAndConditionFields(
                        amountText: $amountText,
                        currency: $currency,
                        condition: $condition,
                        focusTrigger: index
                    )
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Compléter les albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton()
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .messageAlert(message: $errorMessage)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            AsyncCoverImage(
                url: current.basicInformation.thumb ?? current.basicInformation.coverImage,
                cornerRadius: AppLayout.coverCornerRadius, targetSize: 64
            )
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(current.basicInformation.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(current.basicInformation.artistNames)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
                Text("\(index + 1) / \(request.items.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.appTertiaryText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Passer") { advance() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSaving)

            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Enregistrer")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(Color.onAccent)
            .controlSize(.large)
            .disabled(isSaving || !hasValues)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        let toWritePrice = price
        let toWriteCondition = condition
        let item = current
        Task {
            let result = await BatchCompletion.save(price: toWritePrice, condition: toWriteCondition, on: item, username: request.username)
            isSaving = false
            switch result {
            case .saved:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                advance()
            case .refused:
                errorMessage = String(localized: "Impossible d'enregistrer ces informations sur Discogs.")
            case .accountChanged:
                dismiss()
            }
        }
    }

    /// Disque suivant, saisie remise à zéro ; fermeture après le dernier.
    private func advance() {
        guard !isLast else {
            dismiss()
            return
        }
        withAnimation {
            index += 1
            amountText = ""
            condition = nil
        }
    }
}

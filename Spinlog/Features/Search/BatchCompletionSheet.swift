import SwiftUI

/// Saisie rapide, disque par disque, du prix d'achat et de l'état du média des disques qu'un scan
/// par lot vient d'ajouter. « Passer » laisse un disque tel quel (il reste retrouvable avec le
/// filtre « À compléter » de la Collection) ; fermer la feuille arrête là sans rien perdre : ce
/// qui est enregistré l'est déjà.
struct BatchCompletionSheet: View {
    let request: BatchCompletionRequest

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var amountText = ""
    @State private var currency: String
    @State private var condition = ""
    @State private var conditionField: CollectionField?
    @State private var isLoadingFields = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let priceFieldId: Int?
    private let mediaConditionFieldId: Int?

    init(request: BatchCompletionRequest) {
        self.request = request
        priceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: request.username)
        mediaConditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: request.username)
        _currency = State(initialValue: CollectionPreferencesStore.defaultCurrency(for: request.username))
    }

    private var current: CollectionItem { request.items[index] }
    private var isLast: Bool { index == request.items.count - 1 }

    private var values: [(fieldId: Int, value: String)] {
        BatchCompletion.values(
            priceFieldId: priceFieldId, mediaConditionFieldId: mediaConditionFieldId,
            amountText: amountText, currency: currency, condition: condition
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    PriceAndConditionFields(
                        amountText: $amountText,
                        currency: $currency,
                        condition: $condition,
                        showsPrice: priceFieldId != nil,
                        showsCondition: mediaConditionFieldId != nil,
                        conditionField: conditionField,
                        isLoadingConditionField: isLoadingFields,
                        focusTrigger: index
                    )
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Compléter les disques")
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
        .task { await loadConditionField() }
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
            .disabled(isSaving || values.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadConditionField() async {
        defer { isLoadingFields = false }
        guard let mediaConditionFieldId else { return }
        let fields = await CollectionFieldsService.fields(username: request.username, credentials: DiscogsAuthManager.shared.credentials)
        conditionField = fields.first { $0.id == mediaConditionFieldId }
    }

    private func save() {
        isSaving = true
        let toWrite = values
        let item = current
        Task {
            let result = await BatchCompletion.save(toWrite, on: item, username: request.username)
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
            condition = ""
        }
    }
}

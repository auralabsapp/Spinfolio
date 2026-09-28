import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var isScannerPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            searchBar
            scopePicker
            content
        }
        .navigationTitle("Recherche")
        .searchDestinations()
        .fullScreenCover(isPresented: $isScannerPresented) {
            scannerSheet
        }
        .task(id: "\(viewModel.query)|\(viewModel.scope.rawValue)") {
            if viewModel.consumeSuppressFlag() { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    /// Barre de recherche personnalisée (plutôt que `.searchable`) pour pouvoir intégrer
    /// l'icône de scan directement à droite du champ, comme demandé.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Artiste, disque, label…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 18)

            Button {
                isSearchFieldFocused = false
                isScannerPresented = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rechercher par scan")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private var scopePicker: some View {
        Picker("Filtrer", selection: $viewModel.scope) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerRepresentable(
                onScan: { payload in
                    isScannerPresented = false
                    Task { await viewModel.searchByBarcode(payload) }
                },
                onError: { error in
                    isScannerPresented = false
                }
            )
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annuler") { isScannerPresented = false }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            ContentUnavailableView(
                "Recherche Discogs",
                systemImage: "magnifyingglass",
                description: Text("Trouve un disque, un artiste, un label, ou scanne un code-barres.")
            )
        } else if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Recherche impossible",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if viewModel.results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
        } else {
            List(viewModel.results) { result in
                SearchResultRow(result: result)
                    .task { await viewModel.loadMoreIfNeeded(current: result) }
            }
            .listStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}

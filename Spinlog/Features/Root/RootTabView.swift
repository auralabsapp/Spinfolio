import SwiftUI

/// Navigation racine de l'app : 4 onglets, avec Recherche épinglée à la manière de
/// Musique/TV (`Tab(role: .search)`), Liquid Glass appliqué automatiquement par le système.
struct RootTabView: View {
    @State private var selectedTab: AppTab = .collection

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Collection", systemImage: "square.stack", value: .collection) {
                NavigationStack {
                    CollectionView()
                }
            }

            Tab("Wantlist", systemImage: "heart", value: .wantlist) {
                NavigationStack {
                    WantlistView()
                }
            }

            Tab("Scan", systemImage: "barcode.viewfinder", value: .scan) {
                NavigationStack {
                    ScanView()
                }
            }

            Tab(value: .search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
    }
}

enum AppTab: Hashable {
    case collection
    case wantlist
    case scan
    case search
}

#Preview {
    RootTabView()
}

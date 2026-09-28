import SwiftUI

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authManager = DiscogsAuthManager.shared

    var body: some View {
        NavigationStack {
            List {
                if let username = authManager.username {
                    Section {
                        Label(username, systemImage: "person.crop.circle.fill")
                            .font(.headline)
                    }
                }
                Section {
                    Button("Se déconnecter", role: .destructive) {
                        authManager.logout()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Compte Discogs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

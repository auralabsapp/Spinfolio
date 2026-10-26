import SwiftUI

/// Choix du format dans le menu de filtres de la Collection et de la Wantlist : « Tous les
/// formats », puis chaque format présent, coché quand il est actif (le retoucher l'enlève).
struct LibraryFormatFilterOptions: View {
    let formats: [String]
    @Binding var selectedFormat: String?

    var body: some View {
        Button("Tous les formats") {
            selectedFormat = nil
        }
        ForEach(formats, id: \.self) { format in
            Button {
                selectedFormat = (selectedFormat == format ? nil : format)
            } label: {
                HStack {
                    Text(format)
                    if selectedFormat == format {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

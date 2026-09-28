import SwiftUI

struct SettingsView: View {
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.system.rawValue

    var body: some View {
        List {
            Section("Apparence") {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        appThemeRawValue = theme.rawValue
                    } label: {
                        HStack {
                            Label(theme.rawValue, systemImage: theme.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appThemeRawValue == theme.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Paramètres")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

import SwiftUI
import AVFoundation
import VisionKit

/// Affiche le scanner seulement si la caméra est utilisable, sinon une explication.
///
/// Sans ce garde, un accès caméra refusé (ou un appareil sans scanner VisionKit) laissait le
/// scan simple comme le scan par lot sur un écran noir, sans aucune indication.
struct CameraScannerGate<Scanner: View>: View {
    @ViewBuilder let scanner: () -> Scanner

    private enum Access: Equatable {
        case checking
        case granted
        case denied
        case unsupported
    }

    @State private var access: Access = .checking
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch access {
            case .checking:
                Color.black
            case .granted:
                scanner()
            case .denied:
                ContentUnavailableView {
                    Label("Accès à la caméra refusé", systemImage: "camera.fill")
                } description: {
                    Text("Autorise l'accès à la caméra dans les Réglages pour scanner les codes-barres de tes albums.")
                } actions: {
                    Button("Ouvrir les Réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(Color.onAccent)
                }
            case .unsupported:
                ContentUnavailableView(
                    "Scan indisponible",
                    systemImage: "barcode.viewfinder",
                    description: Text("Cet appareil ne permet pas de scanner des codes-barres. Tu peux rechercher l'album par son nom.")
                )
            }
        }
        .task { await refreshAccess() }
        // Retour des Réglages après avoir autorisé la caméra : le scanner s'affiche sans avoir à
        // rouvrir l'écran.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshAccess() }
            }
        }
    }

    private func refreshAccess() async {
        guard DataScannerViewController.isSupported else {
            access = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
        case .notDetermined:
            access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default:
            access = .denied
        }
    }
}

import SwiftUI
import VisionKit

/// Enrobe `DataScannerViewController` (VisionKit) en mode reconnaissance de texte, pour lire
/// le numéro de matrice/runout gravé au centre d'un vinyle. Contrairement au scan de
/// code-barres (un seul candidat évident), le runout comporte souvent plusieurs lignes
/// gravées : on met donc en surbrillance tout le texte reconnu et on laisse l'utilisateur
/// taper sur la ligne exacte à retenir plutôt que de deviner automatiquement.
struct TextRecognitionScannerRepresentable: UIViewControllerRepresentable {
    var onSelect: (String) -> Void
    var onError: (Error) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        do {
            try uiViewController.startScanning()
        } catch {
            onError(error)
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onSelect: (String) -> Void

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case let .text(text) = item {
                onSelect(text.transcript)
            }
        }
    }
}

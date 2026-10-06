import SwiftUI
import VisionKit

/// Enrobe `DataScannerViewController` (VisionKit) pour reconnaître un ou plusieurs
/// codes-barres dans le flux caméra live et les remonter à SwiftUI.
///
/// En mode simple (`continuous == false`, par défaut), s'arrête après le premier code lu.
/// En mode `continuous` (scan par lot), reste actif et rappelle `onScan` pour chaque
/// nouveau code distinct de la session, sans jamais le répéter.
///
/// Maintient l'écran allumé (`isIdleTimerDisabled = true`) pendant que le scanner caméra
/// est actif afin d'empêcher la mise en veille et le verrouillage de l'appareil.
struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onError: (Error) -> Void
    var continuous: Bool = false

    func makeUIViewController(context: Context) -> DataScannerViewController {
        UIApplication.shared.isIdleTimerDisabled = true
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: continuous,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        UIApplication.shared.isIdleTimerDisabled = true
        guard !uiViewController.isScanning else { return }
        do {
            try uiViewController.startScanning()
        } catch {
            onError(error)
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, continuous: continuous)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let continuous: Bool
        private var hasReportedScan = false
        private var reportedPayloads = Set<String>()

        init(onScan: @escaping (String) -> Void, continuous: Bool) {
            self.onScan = onScan
            self.continuous = continuous
        }

        deinit {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard continuous || !hasReportedScan else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    guard continuous else {
                        hasReportedScan = true
                        onScan(payload)
                        break
                    }
                    guard !reportedPayloads.contains(payload) else { continue }
                    reportedPayloads.insert(payload)
                    onScan(payload)
                }
            }
        }
    }
}

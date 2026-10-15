#if DEBUG
import QuartzCore
import OSLog

/// Détecteur de "hitches" de défilement (DEBUG uniquement) : utilise `CADisplayLink` pour mesurer
/// l'intervalle réel entre deux images affichées et journalise dans la console Xcode toute image
/// nettement plus lente que prévu (ex: 40ms au lieu des ~16,7ms attendus à 60Hz) — un indicateur
/// direct de lag perçu pendant le défilement, sans avoir à brancher Instruments.
final class ScrollHitchMonitor {
    static let shared = ScrollHitchMonitor()

    private static let logger = Logger(subsystem: "com.spinlog.app", category: "ScrollHitch")

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    /// `os_log` a lui-même un coût CPU non négligeable (file d'attente `firehose`, IPC vers le
    /// daemon de log) : journaliser CHAQUE hitch pendant une rafale (ex: plusieurs dizaines de
    /// hitchs de 20-40ms par seconde pendant un défilement chargé) ajoutait du travail sur le
    /// thread principal qu'on cherche justement à désengorger, et polluait les traces Instruments
    /// prises en parallèle. Au plus une ligne par seconde ; les hitchs suppriimés dans l'intervalle
    /// sont comptés et leur pire valeur resurfacée dans la ligne suivante, pour ne pas perdre le
    /// signal d'une rafale silencieuse.
    private static let minLogInterval: CFTimeInterval = 1.0
    private var lastLogTimestamp: CFTimeInterval = 0
    private var suppressedCount = 0
    private var worstSuppressedMs: Double = 0

    private init() {}

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        lastLogTimestamp = 0
        suppressedCount = 0
        worstSuppressedMs = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }

        let elapsedMs = (link.timestamp - lastTimestamp) * 1000
        let targetIntervalMs = (link.targetTimestamp - link.timestamp) * 1000
        let expectedMs = targetIntervalMs > 0 ? targetIntervalMs : (1000.0 / 60.0)

        // Au-delà d'1,5x l'intervalle attendu, l'image a visiblement sauté une ou plusieurs
        // frames : c'est exactement ce qui se perçoit comme un à-coup pendant un défilement.
        let threshold = expectedMs * 1.5
        guard elapsedMs > threshold else { return }

        guard link.timestamp - lastLogTimestamp >= Self.minLogInterval else {
            suppressedCount += 1
            worstSuppressedMs = max(worstSuppressedMs, elapsedMs)
            return
        }

        let suffix = suppressedCount > 0
            ? " (+\(suppressedCount) autre(s) dans la dernière seconde, pire : \(String(format: "%.1f", worstSuppressedMs)) ms)"
            : ""
        Self.logger.warning("🐢 Hitch: \(String(format: "%.1f", elapsedMs), privacy: .public) ms (attendu ~\(String(format: "%.1f", expectedMs), privacy: .public) ms)\(suffix, privacy: .public)")
        lastLogTimestamp = link.timestamp
        suppressedCount = 0
        worstSuppressedMs = 0
    }
}
#endif

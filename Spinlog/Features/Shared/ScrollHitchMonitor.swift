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

        Self.logger.warning("🐢 Hitch: \(String(format: "%.1f", elapsedMs), privacy: .public) ms (attendu ~\(String(format: "%.1f", expectedMs), privacy: .public) ms)")
    }
}
#endif

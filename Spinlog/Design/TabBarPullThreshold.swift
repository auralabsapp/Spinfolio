import CoreGraphics

/// Distance de tirage vers le bas (en points), au sommet d'une liste, à partir de laquelle on
/// rétablit la barre d'onglets réduite (voir `TabNavigationCoordinator.expandTabBar()`).
nonisolated enum TabBarPullThreshold {
    static let distance: CGFloat = 12
}

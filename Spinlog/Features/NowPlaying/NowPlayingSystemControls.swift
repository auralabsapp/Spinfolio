import SwiftUI
import AVKit
import MediaPlayer

/// Curseur de volume système (celui des boutons de l'appareil), seul moyen autorisé de régler le
/// volume : `MPVolumeView`. Sa pastille AirPlay est masquée, un bouton dédié existe à côté
/// (`SystemRoutePickerButton`). Sans effet dans le Simulateur, qui n'a pas de volume système.
struct SystemVolumeSlider: UIViewRepresentable {
    /// `MPVolumeView` affiche sa propre pastille de sortie audio quand des appareils AirPlay sont
    /// à portée : on la masque à chaque mise en page plutôt qu'avec `showsRouteButton`, déprécié.
    private final class VolumeView: MPVolumeView {
        override func layoutSubviews() {
            super.layoutSubviews()
            for case let button as UIButton in subviews { button.isHidden = true }
        }
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = VolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Bouton de choix de la sortie audio (AirPlay, Bluetooth), celui du système.
struct SystemRoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.tintColor = UIColor.white.withAlphaComponent(0.7)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

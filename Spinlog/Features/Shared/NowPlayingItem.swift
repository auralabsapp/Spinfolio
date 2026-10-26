import Foundation

/// Informations sur le morceau actuellement en cours de lecture pour le mini-lecteur et le système.
struct NowPlayingItem: Equatable {
    let trackID: String
    let trackTitle: String
    let artistName: String
    let albumTitle: String
    let coverURL: String?
    let destination: SearchDestination?
    let sourceTab: AppTab
}

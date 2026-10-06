import Foundation

/// Image associée à une release, un artiste ou un label.
struct DiscogsImage: Codable, Sendable {
    let type: String
    let uri: String
    let uri150: String
    let width: Int
    let height: Int

    init(type: String = "primary", uri: String, uri150: String = "", width: Int = 0, height: Int = 0) {
        self.type = type
        self.uri = uri
        self.uri150 = uri150
        self.width = width
        self.height = height
    }
}

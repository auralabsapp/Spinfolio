import Foundation

/// Image associée à une release, un artiste ou un label.
struct DiscogsImage: Decodable, Sendable {
    let type: String
    let uri: String
    let uri150: String
    let width: Int
    let height: Int
}

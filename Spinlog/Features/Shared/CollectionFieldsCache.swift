import Foundation

/// Champs personnalisés Discogs mis en cache par compte (nom d'utilisateur insensible à la casse).
/// Une liste vide n'est pas mise en cache : un compte sans champ refait la requête, comme avant.
nonisolated struct CollectionFieldsCache {
    private var fieldsByUser: [String: [CollectionField]] = [:]

    private static func key(for username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func fields(for username: String) -> [CollectionField]? {
        guard let fields = fieldsByUser[Self.key(for: username)], !fields.isEmpty else { return nil }
        return fields
    }

    mutating func store(_ fields: [CollectionField], for username: String) {
        fieldsByUser[Self.key(for: username)] = fields
    }

    mutating func removeAll() {
        fieldsByUser = [:]
    }
}

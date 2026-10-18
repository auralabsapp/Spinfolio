import Foundation
import Testing
@testable import Spinlog

/// Raccourcis Siri : liste des disques proposés et recherche par la voix.
@MainActor
struct RecordLibraryTests {
    private func item(releaseId: Int, instanceId: Int, title: String, artist: String) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": releaseId, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": [
                "id": releaseId, "title": title, "resource_url": "",
                "artists": [["id": 1, "name": artist]],
                "cover_image": "https://example.com/\(releaseId).jpg"
            ] as [String: Any]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func severalCopiesOfARecordAreOfferedOnce() throws {
        let items = [
            try item(releaseId: 1, instanceId: 10, title: "Kind of Blue", artist: "Miles Davis"),
            try item(releaseId: 1, instanceId: 11, title: "Kind of Blue", artist: "Miles Davis"),
            try item(releaseId: 2, instanceId: 20, title: "Blue Train", artist: "John Coltrane")
        ]
        let records = RecordLibrary.uniqueRecords(from: items)
        #expect(records.map(\.id) == [1, 2])
        #expect(records.first?.artist == "Miles Davis")
        #expect(records.first?.coverURL == "https://example.com/1.jpg")
    }

    @Test func searchMatchesTitleAndArtistWordsIgnoringCaseAndAccents() {
        let records = [
            RecordEntity(id: 1, title: "Kind of Blue", artist: "Miles Davis", coverURL: nil),
            RecordEntity(id: 2, title: "Mélodie en sous-sol", artist: "Michel Magne", coverURL: nil),
            RecordEntity(id: 3, title: "Blue Train", artist: "John Coltrane", coverURL: nil)
        ]
        #expect(RecordLibrary.matching("miles blue", in: records).map(\.id) == [1])
        #expect(RecordLibrary.matching("MELODIE", in: records).map(\.id) == [2])
        #expect(RecordLibrary.matching("blue", in: records).map(\.id) == [1, 3])
        #expect(RecordLibrary.matching("   ", in: records).isEmpty)
        #expect(RecordLibrary.matching("abbey road", in: records).isEmpty)
    }
}

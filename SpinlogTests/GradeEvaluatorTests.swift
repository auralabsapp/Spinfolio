import Foundation
import Testing
@testable import Spinlog

/// Dates retenues pour le grade « collection » : une par disque distinct (`firstAdditionDates`).
@MainActor
struct GradeEvaluatorTests {
    private func item(instanceId: Int, releaseId: Int, added: String) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": releaseId, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": added,
            "basic_information": [
                "id": releaseId, "title": "Title", "resource_url": "",
                "artists": [["id": 1, "name": "Artist"]]
            ] as [String: Any]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func twoCopiesCountOnceAtTheirEarliestDate() throws {
        let later = try item(instanceId: 1, releaseId: 10, added: "2024-06-01T10:00:00-07:00")
        let earlier = try item(instanceId: 2, releaseId: 10, added: "2021-03-01T10:00:00-07:00")
        let other = try item(instanceId: 3, releaseId: 20, added: "2023-01-01T10:00:00-07:00")

        let dates = GradeEvaluator.firstAdditionDates(of: [later, earlier, other]).sorted()
        let expectedEarlier = try #require(DiscogsDateParsing.dateAdded(from: earlier.dateAdded))
        let expectedOther = try #require(DiscogsDateParsing.dateAdded(from: other.dateAdded))
        #expect(dates == [expectedEarlier, expectedOther])
    }

    @Test func unreadableDateIsSkipped() throws {
        let unreadable = try item(instanceId: 1, releaseId: 10, added: "hier")
        let readable = try item(instanceId: 2, releaseId: 20, added: "2023-01-01T10:00:00-07:00")

        #expect(GradeEvaluator.firstAdditionDates(of: [unreadable, readable]).count == 1)
    }

    @Test func unreadableCopyDoesNotHideAReadableOne() throws {
        let unreadable = try item(instanceId: 1, releaseId: 10, added: "hier")
        let readable = try item(instanceId: 2, releaseId: 10, added: "2023-01-01T10:00:00-07:00")

        #expect(GradeEvaluator.firstAdditionDates(of: [unreadable, readable]).count == 1)
    }
}

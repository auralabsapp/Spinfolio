import Foundation
import Testing
@testable import Spinlog

/// La liste des fonctions Premium est partagée par le paywall et la feuille de liste : ces tests
/// protègent sa cohérence quand on y ajoute ou retire une fonction.
@MainActor
struct PremiumFeatureCatalogTests {
    @Test func idsAreUnique() {
        let ids = PremiumFeatureCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyFeatureIsComplete() {
        for feature in PremiumFeatureCatalog.all {
            #expect(!feature.icon.isEmpty, "Icône vide : \(feature.id)")
            #expect(!String(localized: feature.title).isEmpty, "Titre vide : \(feature.id)")
            #expect(!String(localized: feature.description).isEmpty, "Description vide : \(feature.id)")
        }
    }

    /// Le paywall garde ses 9 fonctions (la liste dépliable y compte sur ce total).
    @Test func catalogKeepsTheNineSoldFeatures() {
        #expect(PremiumFeatureCatalog.all.count == 9)
    }
}

import Testing
@testable import Spinlog

/// Règle de la confirmation finale d'effacement des données de l'app : il faut retaper le nom du compte.
struct EraseAccountDataConfirmationTests {
    @Test func exactNameConfirms() {
        #expect(EraseAccountDataSheet.isConfirmationValid(typed: "Aurelien", expected: "Aurelien"))
    }

    @Test func caseAndSurroundingSpacesAreIgnored() {
        #expect(EraseAccountDataSheet.isConfirmationValid(typed: "  aurelien ", expected: "Aurelien"))
    }

    @Test func anotherNameOrPartialNameDoesNotConfirm() {
        #expect(!EraseAccountDataSheet.isConfirmationValid(typed: "Aure", expected: "Aurelien"))
        #expect(!EraseAccountDataSheet.isConfirmationValid(typed: "Aurelien2", expected: "Aurelien"))
        #expect(!EraseAccountDataSheet.isConfirmationValid(typed: "", expected: "Aurelien"))
    }

    /// Sans nom de compte connu, rien ne se confirme (jamais d'effacement par un champ vide).
    @Test func emptyExpectedNameNeverConfirms() {
        #expect(!EraseAccountDataSheet.isConfirmationValid(typed: "", expected: ""))
        #expect(!EraseAccountDataSheet.isConfirmationValid(typed: "   ", expected: "  "))
    }
}

import Testing
@testable import Spinlog

struct SessionRejectionTrackerTests {
    @Test func theFirstRejectionOfTheConnectedAccountRaisesTheAlertOnce() {
        var tracker = SessionRejectionTracker()
        let raised1 = tracker.noteRejected(usedToken: "a", currentToken: "a", isDemo: false)
        #expect(raised1)
        #expect(tracker.isRejected)
        // Les refus suivants (écran par écran) ne redéclenchent pas l'alerte.
        let raised2 = tracker.noteRejected(usedToken: "a", currentToken: "a", isDemo: false)
        #expect(!raised2)
        #expect(tracker.isRejected)
    }

    @Test func aLateAnswerForAnotherTokenIsIgnored() {
        var tracker = SessionRejectionTracker()
        // Réponse tardive d'un compte quitté, ou connexion en cours (jeton pas encore enregistré).
        let raised3 = tracker.noteRejected(usedToken: "old", currentToken: "new", isDemo: false)
        #expect(!raised3)
        let raised4 = tracker.noteRejected(usedToken: "new", currentToken: nil, isDemo: false)
        #expect(!raised4)
        #expect(!tracker.isRejected)
    }

    @Test func theDemoNeverRejectsTheSession() {
        var tracker = SessionRejectionTracker()
        let raised5 = tracker.noteRejected(usedToken: "a", currentToken: "a", isDemo: true)
        #expect(!raised5)
        #expect(!tracker.isRejected)
    }

    @Test func aSuccessfulRequestClearsAPassingRejection() {
        var tracker = SessionRejectionTracker()
        _ = tracker.noteRejected(usedToken: "a", currentToken: "a", isDemo: false)
        tracker.noteAccepted(usedToken: "other", currentToken: "a")
        #expect(tracker.isRejected)
        tracker.noteAccepted(usedToken: "a", currentToken: "a")
        #expect(!tracker.isRejected)
        // Un nouveau refus peut de nouveau prévenir.
        let raised6 = tracker.noteRejected(usedToken: "a", currentToken: "a", isDemo: false)
        #expect(raised6)
    }

    @Test func signingInOrOutStartsAgainFromAHealthySession() {
        var tracker = SessionRejectionTracker()
        _ = tracker.noteRejected(usedToken: "a", currentToken: "a", isDemo: false)
        tracker.reset()
        #expect(!tracker.isRejected)
    }

    @Test func a401IsAlwaysARejectionButA403OnlyOnTheOwnAccountSpace() {
        #expect(SessionRejectionTracker.isRejection(status: 401, path: "users/alice/collection/folders/1/releases/2", username: "alice"))
        #expect(SessionRejectionTracker.isRejection(status: 401, path: "database/search", username: "alice"))
        // 403 d'une écriture avec un jeton révoqué : espace du compte et identité.
        #expect(SessionRejectionTracker.isRejection(status: 403, path: "users/Alice/collection/folders/1/releases/2/instances/3", username: "alice"))
        #expect(SessionRejectionTracker.isRejection(status: 403, path: "oauth/identity", username: "alice"))
        // 403 sur le profil ou la collection privée d'un autre utilisateur : rien à voir avec la session.
        #expect(!SessionRejectionTracker.isRejection(status: 403, path: "users/bob/collection/folders/1/releases", username: "alice"))
        #expect(!SessionRejectionTracker.isRejection(status: 403, path: "users/alice/collection", username: nil))
        #expect(!SessionRejectionTracker.isRejection(status: 404, path: "users/alice/collection", username: "alice"))
    }

    @Test func onlyAWriteOrTheIdentityProvesTheSession() {
        #expect(SessionRejectionTracker.provesSession(method: "POST", path: "users/alice/collection/folders/1/releases/2"))
        #expect(SessionRejectionTracker.provesSession(method: "DELETE", path: "users/alice/wantlist/2"))
        #expect(SessionRejectionTracker.provesSession(method: "GET", path: "oauth/identity"))
        // Une collection publique se lit avec un jeton révoqué : cette réussite ne prouve rien.
        #expect(!SessionRejectionTracker.provesSession(method: "GET", path: "users/alice/collection/folders/0/releases"))
    }
}

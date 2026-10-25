import Testing
@testable import Spinlog

/// Identifiant YouTube extrait d'une URI Discogs (contenu contributif), inséré ensuite dans le
/// HTML du lecteur : seuls les hôtes YouTube exacts et les identifiants de 11 caractères passent.
struct ReleaseVideoTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("http://youtube.com/watch?v=dQw4w9WgXcQ&t=30", "dQw4w9WgXcQ"),
        ("https://m.youtube.com/watch?v=a_b-C1d2E3f", "a_b-C1d2E3f"),
        ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ")
    ])
    func validYouTubeURIsGiveTheID(uri: String, expected: String) {
        #expect(ReleaseVideo.youTubeVideoID(fromURI: uri) == expected)
    }

    @Test(arguments: [
        // Identifiant piégé : sortirait de l'attribut `src` de l'iframe.
        "https://www.youtube.com/watch?v=x\"><script>alert(1)</script>",
        "https://youtu.be/abc%22onload=alert(1)",
        // Hôtes qui contiennent « youtu » sans être YouTube.
        "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
        "https://notyoutu.be/dQw4w9WgXcQ",
        // Longueur ou schéma invalides.
        "https://www.youtube.com/watch?v=short",
        "javascript://youtu.be/dQw4w9WgXcQ",
        "https://vimeo.com/123456"
    ])
    func anythingElseIsRejected(uri: String) {
        #expect(ReleaseVideo.youTubeVideoID(fromURI: uri) == nil)
    }
}

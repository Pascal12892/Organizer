import Foundation

/// Hilfsfunktionen für Security-Scoped Bookmarks. Damit behält die App in der
/// Sandbox den Zugriff auf vom Nutzer gewählte Ordner auch nach einem Neustart.
enum SecurityScopedBookmark {
    static func make(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Löst ein Bookmark auf. `isStale` bedeutet: funktioniert noch, sollte aber neu erzeugt werden.
    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}

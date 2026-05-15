import Foundation

enum LyricsSource: Int, CaseIterable, CustomStringConvertible {
    case genius
    case lrclib
    case musixmatch
    case petit
    case notReplaced
    
    public static var allCases: [LyricsSource] {
        return [.musixmatch, .lrclib, .genius, .petit]
    }

    // swift 5.8 compatible
    var description: String {
    switch self {
    case .genius:
        return "Genius"
    case .lrclib:
        return "LRCLIB"
    case .musixmatch:
        return "Musixmatch"
    case .petit:
        return "PetitLyrics"
    case .notReplaced:
        return "Spotify"
    }
    }

    
    var isReplacingLyrics: Bool { self != .notReplaced }
    
    static var defaultSource: LyricsSource {
        .musixmatch
    }
}

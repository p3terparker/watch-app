import Foundation

// Your Music library in Watch (3.23): the Music app's own library, searched and played by AppleScript addressed to Music
// (by bundle id) — searched only while Music runs and Watch is already allowed; macOS is asked only from a click. Songs go
// in Up Next as `music:<persistent ID>` items that Music itself plays. The scripts and the answer's parsing are Foundation
// only, so test.sh covers them.
struct LibrarySong: Equatable {
    var persistentID: String          // 16 hex digits, as Music reports it
    var title: String
    var artist: String?
    var album: String?
    var duration: Double?

    var queueItem: QueueItem {
        QueueItem(url: QueueItem.musicPrefix + persistentID, title: title, subtitle: artist, duration: duration, source: .music)
    }
}

// What a library search came back with (MusicAppControl.searchLibrary): songs, or why there are none.
enum LibraryAnswer: Equatable { case songs([LibrarySong]), notRunning, needsAccess, denied, failed }

enum MusicLibrary {
    static let bundleID = "com.apple.Music"
    static let limit = 50                       // songs listed per search
    private static let field = "\u{1F}", record = "\u{1E}"   // unit / record separators: never in a song's name

    // Text inside an AppleScript string literal: backslashes and quotes escaped; tabs, newlines and other control
    // characters become spaces, so nothing typed can end the string.
    static func escaped(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default: out += CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
            }
        }
        return out
    }
    // Searches the whole library (names, artists, albums…), the first `limit` songs as id ␟ name ␟ artist ␟ album ␟ seconds ␞.
    static func searchScript(_ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        return """
        tell application id "\(bundleID)"
            set found to (search library playlist 1 for "\(escaped(q))")
            set n to count of found
            if n > \(limit) then set n to \(limit)
            set out to ""
            repeat with i from 1 to n
                try
                    set t to item i of found
                    set out to out & (persistent ID of t) & (character id 31) & (name of t) & (character id 31) & (artist of t) ¬
                        & (character id 31) & (album of t) & (character id 31) & (((duration of t) div 1) as text) & (character id 30)
                end try
            end repeat
            return out
        end tell
        """
    }
    static func parse(_ answer: String) -> [LibrarySong] {
        answer.components(separatedBy: record).compactMap { line in
            let f = line.components(separatedBy: field)
            guard f.count >= 5, isPersistentID(f[0]) else { return nil }
            let title = f[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            func text(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
            return LibrarySong(persistentID: f[0], title: title, artist: text(f[2]), album: text(f[3]),
                               duration: Double(f[4].trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 > 0 ? $0 : nil })
        }
    }
    static func isPersistentID(_ s: String) -> Bool { s.count == 16 && s.allSatisfy { $0.isASCII && $0.isHexDigit } }
    // A queue item's persistent ID ("music:<id>"); nil for "what Music plays" and anything else.
    static func persistentID(_ url: String) -> String? {
        guard url.hasPrefix(QueueItem.musicPrefix) else { return nil }
        let id = String(url.dropFirst(QueueItem.musicPrefix.count))
        return isPersistentID(id) ? id : nil
    }
    // Plays one library song (validated id, so nothing else can reach the script).
    static func playScript(_ persistentID: String) -> String? {
        guard isPersistentID(persistentID) else { return nil }
        return #"tell application id "com.apple.Music" to play (first track of library playlist 1 whose persistent ID is "\#(persistentID)")"#
    }
}

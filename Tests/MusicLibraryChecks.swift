import Foundation

// Your Music library (MusicLibrary.swift): the scripts Watch would send Music, and Music's answer read back. No Music here.
func checkMusicLibrary() {
    let script = MusicLibrary.searchScript("  AC/DC \"Back\" \\ in\tBlack\n ") ?? ""
    expect(script.hasPrefix(#"tell application id "com.apple.Music""#), "addressed to Music by bundle id")
    expect(script.contains(#"search library playlist 1 for "AC/DC \"Back\" \\ in Black""#),
           "the words stay inside one escaped string, control characters as spaces: \(script)")
    expect(script.contains("if n > \(MusicLibrary.limit) then"), "at most \(MusicLibrary.limit) songs")
    expect(MusicLibrary.searchScript("   ") == nil, "nothing to search")
    expect(MusicLibrary.escaped("a\"b\\c\u{7}d") == #"a\"b\\c d"#, "escaping")

    let answer = "0123456789ABCDEF\u{1F}Back in Black\u{1F}AC/DC\u{1F}Back in Black\u{1F}255\u{1E}"
        + "FEDCBA9876543210\u{1F}Untitled\u{1F}\u{1F} \u{1F}0\u{1E}"
        + "not-an-id-here!!\u{1F}Bad\u{1F}A\u{1F}B\u{1F}1\u{1E}"
        + "0123456789ABCDE0\u{1F}  \u{1F}A\u{1F}B\u{1F}1\u{1E}"
        + "00000000000000AA\u{1F}Short"
    let songs = MusicLibrary.parse(answer)
    expect(songs == [LibrarySong(persistentID: "0123456789ABCDEF", title: "Back in Black", artist: "AC/DC", album: "Back in Black", duration: 255),
                     LibrarySong(persistentID: "FEDCBA9876543210", title: "Untitled", artist: nil, album: nil, duration: nil)],
           "songs with a real id and a name; empty fields are nil: \(songs)")
    expect(MusicLibrary.parse("").isEmpty, "no answer, no songs")

    let item = songs[0].queueItem
    expect(item.url == "music:0123456789ABCDEF" && item.source == .music && item.title == "Back in Black" && item.subtitle == "AC/DC"
           && item.duration == 255, "a library song in Up Next is played by Music: \(item)")
    expect(MusicLibrary.persistentID(item.url) == "0123456789ABCDEF", "its id back from the item")
    for url in ["music:", "music:XYZ", "music:0123456789ABCDEF\"", "https://fixture.invalid/0123456789ABCDEF"] {
        expect(MusicLibrary.persistentID(url) == nil, "not a library song: \(url)")
    }
    expect(MusicLibrary.playScript("0123456789ABCDEF")
           == #"tell application id "com.apple.Music" to play (first track of library playlist 1 whose persistent ID is "0123456789ABCDEF")"#,
           "plays that one song")
    for bad in ["0123456789ABCDE\"", "12", "0123456789ABCDEFG", "\") & do shell script \"x"] {
        expect(MusicLibrary.playScript(bad) == nil, "only a real id reaches a script: \(bad)")
    }
}

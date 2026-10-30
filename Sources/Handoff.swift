import Foundation

// The universal queue and the music apps (UpNext.swift). Watch can't see or edit Music's or Spotify's own queue, so while
// one of their songs is the queue's current item it waits for that song to end, pauses the app (which has already moved
// on to its own next song), plays the queue's next item, and hands back to the app when the queue runs out. These rules
// decide what each report from the app means, and where Play Next / Play Later go. Pure, so test.sh covers it.
enum Handoff {
    // How close to its end a song must have been for a change of song to count as it finishing.
    static let endMargin: Double = 3

    enum Event: Equatable {
        case none        // the same song (paused, resumed, sought), or another app's report
        case finished    // it played to its end: pause the app, go on with the queue
        case skipped     // moved on early while the app was in the background (media keys, AirPods, Control Center)
        case detached    // you picked something else in the app itself, or it quit: stop following it — never fight you
    }

    // `song`: the song Watch follows in `app`, as last reported. `report`: the app's new state (nil: it stopped or went
    // quiet). `fallback`: how far into the song Watch reckons it is when the app gave no position.
    static func judge(song: NowPlayingInfo, report: NowPlayingInfo?, app: String, now: Date, fallback: Double?,
                      frontmost: Bool, running: Bool) -> Event {
        let position = song.position(at: now) ?? fallback
        let nearEnd = song.duration.map { (position ?? 0) >= $0 - endMargin } ?? false
        guard let report = report else { return nearEnd ? .finished : (running ? .none : .detached) }
        guard report.appBundleID == app, report.itemKey != song.itemKey else { return .none }
        if nearEnd { return .finished }
        return frontmost ? .detached : .skipped
    }

    // Spotify plays a song or episode by its URI. Only a URI SpotifyLink accepts (letters and digits) goes into the script.
    static func spotifyPlayScript(_ link: String) -> String? {
        guard let uri = SpotifyLink.uri(link) else { return nil }
        return "tell application id \"\(SpotifyLink.bundleID)\" to play track \"\(uri)\""
    }
}

// Where Play Next / Play Later go.
enum QueueRoute: Equatable {
    case add                 // into the queue that's running
    case slotIn(String)      // Music/Spotify is playing: after its song, then back to it
    case start               // a new queue, starting now
    static func pick(queueRunning: Bool, playingApp: String?) -> QueueRoute {
        if queueRunning { return .add }
        if let app = playingApp, AppVolume.supported.contains(app) { return .slotIn(app) }
        return .start
    }
}

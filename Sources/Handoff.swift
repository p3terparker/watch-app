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

// Watch's own playback in macOS's Now Playing (3.24: Control Center, media keys, AirPods): which of Watch's players owns it.
// Something playing wins — the universal queue's own item, else the video window that played most recently; while nothing
// of Watch's plays, the last of them keeps it (so ⏯ resumes it) unless a music app is playing.
enum OwnPlayback {
    enum Source: Equatable { case none, queue, player(Int) }
    struct PlayerState: Equatable { var id: Int; var playing: Bool; var lastPlayed: Date }

    static func pick(queueItem: Bool, queuePlaying: Bool, players: [PlayerState], musicPlaying: Bool) -> Source {
        func latest(_ ps: [PlayerState]) -> PlayerState? { ps.max { $0.lastPlayed < $1.lastPlayed } }
        if queueItem && queuePlaying { return .queue }
        if let p = latest(players.filter { $0.playing }) { return .player(p.id) }
        if musicPlaying { return .none }
        if queueItem { return .queue }
        return latest(players).map { .player($0.id) } ?? .none
    }
}

// Preferences ▸ "Pause Music or Spotify while Watch plays" / "…and resume it afterwards" (3.24).
enum MusicPause {
    // Watch just began playing: the music app to pause — the one playing now, unless Up Next is already handing off with it.
    static func toPause(enabled: Bool, playingApp: String?, queueUsesApp: Bool) -> String? {
        guard enabled, !queueUsesApp, let app = playingApp, AppVolume.supported.contains(app) else { return nil }
        return app
    }
    // The app Watch paused plays again once nothing of Watch's is left (its videos closed, Up Next done) — unless it's
    // already playing again (you resumed it yourself).
    static func shouldResume(enabled: Bool, paused: String?, watchActive: Bool, appPlaying: Bool) -> Bool {
        enabled && paused != nil && !watchActive && !appPlaying
    }
}

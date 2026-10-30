import AppKit
import MediaPlayer

// Watch's own playback in macOS's Now Playing (3.24): Control Center, the menu bar's Now Playing, the keyboard's media keys
// and headphone controls reach whatever of Watch's is playing — the universal queue's own item or a video window
// (OwnPlayback.pick, run by AppDelegate.systemTick). While only another app plays, nothing is published and the commands are
// off, so the keys stay that app's. Watch's own NowPlayingMonitor ignores what Watch publishes (AppDelegate.ownBundleIDs).
final class SystemNowPlaying {
    // A command from the keys / Control Center; false when nothing of Watch's could take it.
    var onCommand: ((NowPlayingRequest) -> Bool)?
    private(set) var published: NowPlayingInfo?
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkData: Data?
    private var artwork: MPMediaItemArtwork?

    func publish(_ info: NowPlayingInfo?) {
        let center = MPNowPlayingInfoCenter.default()
        guard let info = info else {
            guard published != nil else { return }
            published = nil
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            disableCommands()
            return
        }
        enableCommands()
        var d: [String: Any] = [MPMediaItemPropertyTitle: info.title,
                                MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? (info.rate.flatMap { $0 > 0 ? $0 : nil } ?? 1) : 0,
                                MPNowPlayingInfoPropertyElapsedPlaybackTime: info.position(at: Date()) ?? 0]
        if let artist = info.artist { d[MPMediaItemPropertyArtist] = artist }
        if let album = info.album { d[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = info.duration, duration > 0 { d[MPMediaItemPropertyPlaybackDuration] = duration }
        if info.artwork != artworkData {
            artworkData = info.artwork
            artwork = info.artwork.flatMap { NSImage(data: $0) }.map { image in
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        if let art = artwork { d[MPMediaItemPropertyArtwork] = art }
        center.nowPlayingInfo = d
        center.playbackState = info.isPlaying ? .playing : .paused
        published = info
    }

    // Exercised by the isolated UI checks (no media keys there): what a key press would do.
    @discardableResult func handle(_ request: NowPlayingRequest) -> Bool { onCommand?(request) ?? false }

    private func enableCommands() {
        guard targets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ request: @escaping (MPRemoteCommandEvent) -> NowPlayingRequest?) {
            command.isEnabled = true
            let target = command.addTarget { [weak self] event in
                guard let r = request(event), self?.handle(r) == true else { return .commandFailed }
                return .success
            }
            targets.append((command, target))
        }
        on(center.playCommand) { _ in .command(.play) }
        on(center.pauseCommand) { _ in .command(.pause) }
        on(center.togglePlayPauseCommand) { [weak self] _ in .command(self?.published?.isPlaying == true ? .pause : .play) }
        on(center.nextTrackCommand) { _ in .command(.next) }
        on(center.previousTrackCommand) { _ in .command(.previous) }
        on(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { NowPlayingRequest.seek($0.positionTime) }
        }
    }
    private func disableCommands() {
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets = []
    }
}

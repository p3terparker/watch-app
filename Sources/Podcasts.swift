import Foundation

// Podcasts (3.22): Apple Podcasts links, the iTunes Lookup / Search answers and RSS feeds, read into episodes Watch plays
// itself (the universal queue's own audio player, in the music window). No account. The parsing is Foundation only, so
// test.sh covers it; `PodcastDirectory` does the network calls.
struct PodcastEpisode: Equatable {
    var title: String
    var audioURL: String
    var published: Date?
    var duration: Double?
    var artwork: String?
    var show: String?
    var appleID: String?          // the episode's iTunes id (an Apple Podcasts link's `i=`)
    var showID: String?           // its show's iTunes id

    // Its Apple Podcasts page, when both ids are known (a feed's episodes have none).
    var page: String? { showID.flatMap { s in appleID.map { PodcastLinks.episodeLink(show: s, episode: $0) } } }
    // In Up Next: the audio itself, played by Watch; the page for double-click and Copy Link.
    func queueItem() -> QueueItem {
        QueueItem(url: audioURL, title: title, subtitle: show, artwork: artwork, duration: duration, source: .podcast, page: page)
    }
}
struct PodcastShow: Equatable {
    var title: String
    var author: String?
    var feedURL: String?
    var artwork: String?
    var appleID: String?          // the show's iTunes id (an Apple Podcasts link's `id…`)
}

enum PodcastLinks {
    // podcasts.apple.com/<country>/podcast/<slug>/id<show>[?i=<episode>] → the show's id and the episode's, if any.
    static func parse(_ s: String) -> (show: String, episode: String?)? {
        guard let c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host?.lowercased(), host == "podcasts.apple.com" || host == "itunes.apple.com" else { return nil }
        guard let last = c.path.split(separator: "/").last(where: { $0.hasPrefix("id") }) else { return nil }
        let show = String(last.dropFirst(2))
        guard isID(show) else { return nil }
        let episode = c.queryItems?.first { $0.name == "i" }?.value.flatMap { isID($0) ? $0 : nil }
        return (show, episode)
    }
    private static func isID(_ s: String) -> Bool { !s.isEmpty && s.count <= 20 && s.allSatisfy { $0.isASCII && $0.isNumber } }
    static func isEpisode(_ s: String) -> Bool { parse(s)?.episode != nil }
    static func isShow(_ s: String) -> Bool { parse(s).map { $0.episode == nil } ?? false }
    // A link that is probably an RSS feed: …/feed, .rss/.xml, or a feeds.… host.
    static func isFeed(_ s: String) -> Bool {
        guard let u = URL(string: s), let host = u.host?.lowercased(), u.scheme?.hasPrefix("http") == true else { return false }
        let path = u.path.lowercased()
        return host.hasPrefix("feeds.") || host.hasPrefix("feed.") || path.hasSuffix(".rss") || path.hasSuffix(".xml")
            || path.hasSuffix("/feed") || path.hasSuffix("/rss") || path.contains("/feed/")
    }
    static func lookupURL(show: String) -> URL? {
        var c = URLComponents(string: "https://itunes.apple.com/lookup")
        c?.queryItems = [URLQueryItem(name: "id", value: show), URLQueryItem(name: "entity", value: "podcastEpisode"),
                         URLQueryItem(name: "limit", value: "200")]
        return c?.url
    }
    static func episodeLink(show: String, episode: String) -> String { "https://podcasts.apple.com/podcast/id\(show)?i=\(episode)" }
    // The term is escaped by hand, so "&", "+" or "=" in a search can never change the query.
    static func searchURL(_ query: String) -> URL? {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let term = query.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=25&term=" + term)
    }
}

// The iTunes Lookup and Search APIs' JSON.
enum ITunesPodcasts {
    private static func results(_ data: Data) -> [[String: Any]] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["results"] as? [[String: Any]] ?? []
    }
    private static func text(_ d: [String: Any], _ key: String) -> String? {
        guard let s = d[key] as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    private static func id(_ d: [String: Any], _ key: String) -> String? {
        if let n = d[key] as? Int { return String(n) }
        if let n = d[key] as? NSNumber { return n.stringValue }
        return text(d, key)
    }
    static func show(_ d: [String: Any]) -> PodcastShow? {
        guard let title = text(d, "collectionName") ?? text(d, "trackName") else { return nil }
        return PodcastShow(title: title, author: text(d, "artistName"), feedURL: text(d, "feedUrl"),
                           artwork: text(d, "artworkUrl600") ?? text(d, "artworkUrl100"), appleID: id(d, "collectionId"))
    }
    // A show's lookup (`entity=podcastEpisode`): the show first, then its newest episodes.
    static func lookup(_ data: Data) -> (show: PodcastShow?, episodes: [PodcastEpisode]) {
        let all = results(data)
        let show = all.first { ($0["kind"] as? String) == "podcast" || ($0["wrapperType"] as? String) == "track" && $0["episodeUrl"] == nil }
            .flatMap { Self.show($0) }
        let iso = ISO8601DateFormatter()
        let episodes = all.compactMap { d -> PodcastEpisode? in
            guard (d["wrapperType"] as? String) == "podcastEpisode" || (d["kind"] as? String) == "podcast-episode",
                  let title = text(d, "trackName"), let audio = text(d, "episodeUrl") else { return nil }
            let millis = (d["trackTimeMillis"] as? Double) ?? (d["trackTimeMillis"] as? Int).map(Double.init)
            return PodcastEpisode(title: title, audioURL: audio, published: text(d, "releaseDate").flatMap { iso.date(from: $0) },
                                  duration: millis.map { $0 / 1000 }.flatMap { $0 > 0 ? $0 : nil },
                                  artwork: text(d, "artworkUrl600") ?? text(d, "artworkUrl160") ?? show?.artwork,
                                  show: text(d, "collectionName") ?? show?.title, appleID: id(d, "trackId"),
                                  showID: id(d, "collectionId") ?? show?.appleID)
        }
        return (show, episodes)
    }
    // One episode of a show's lookup, by its id (nil when it's older than the newest 200 the lookup lists).
    static func episode(_ id: String, in data: Data) -> PodcastEpisode? { lookup(data).episodes.first { $0.appleID == id } }
    // A podcast search (`media=podcast&entity=podcast`).
    static func search(_ data: Data) -> [PodcastShow] { results(data).compactMap(show) }
}

// An RSS feed: the channel's title and picture, and every item with an audio enclosure, in the feed's order.
enum PodcastFeed {
    static func parse(_ data: Data) -> (show: PodcastShow, episodes: [PodcastEpisode])? {
        let reader = FeedReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !reader.episodes.isEmpty, let title = reader.channelTitle else { return nil }
        let show = PodcastShow(title: title, author: reader.author, feedURL: nil, artwork: reader.channelImage)
        let episodes = reader.episodes.map { e -> PodcastEpisode in
            var e = e
            if e.artwork == nil { e.artwork = reader.channelImage }
            e.show = title
            return e
        }
        return (show, episodes)
    }
    // "1:02:03", "62:03", "3723" (seconds), "3723.5" → seconds.
    static func duration(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        let total = parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        return total > 0 ? total : nil
    }
    // RFC 822 dates as feeds write them ("Thu, 29 Oct 2026 08:00:00 +0000", sometimes with a zone name or no seconds).
    static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm zzz",
                       "d MMM yyyy HH:mm:ss Z"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}

private final class FeedReader: NSObject, XMLParserDelegate {
    var channelTitle: String?
    var channelImage: String?
    var author: String?
    var episodes: [PodcastEpisode] = []
    private var inItem = false, inImage = false
    private var text = ""
    private var item: (title: String?, audio: String?, date: String?, duration: String?, image: String?)?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "item": inItem = true; item = (nil, nil, nil, nil, nil)
        case "image" where !inItem: inImage = true
        case "itunes:image":
            if let href = attributes["href"] { if inItem { item?.image = href } else if channelImage == nil || !inImage { channelImage = href } }
        case "enclosure" where inItem:
            let type = attributes["type"]?.lowercased() ?? ""
            if let url = attributes["url"], type.isEmpty || type.hasPrefix("audio") || type.hasPrefix("video") || item?.audio == nil { item?.audio = url }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        if inItem {
            switch name {
            case "title": item?.title = value
            case "pubDate": item?.date = value
            case "itunes:duration": item?.duration = value
            case "item":
                inItem = false
                if let i = item, let audio = i.audio, let title = i.title, !title.isEmpty {
                    episodes.append(PodcastEpisode(title: title, audioURL: audio, published: i.date.flatMap(PodcastFeed.date),
                                                   duration: i.duration.flatMap(PodcastFeed.duration), artwork: i.image))
                }
                item = nil
            default: break
            }
            return
        }
        switch name {
        case "title" where !inImage && channelTitle == nil && !value.isEmpty: channelTitle = value
        case "url" where inImage && channelImage == nil && !value.isEmpty: channelImage = value
        case "image": inImage = false
        case "itunes:author" where author == nil && !value.isEmpty: author = value
        default: break
        }
    }
}

// The network side: iTunes Search and Lookup (no account) and the shows' own feeds. Completions arrive on the main queue.
enum PodcastDirectory {
    static let timeout: TimeInterval = 20
    private static func get(_ url: URL, completion: @escaping (Data?, String) -> Void) {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.setValue("Watch (macOS)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: r) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = error == nil && (200..<300).contains(status) && data?.isEmpty == false
            let why = error.map { ($0 as NSError).code == NSURLErrorTimedOut ? "The podcast directory didn't answer in time." : $0.localizedDescription }
                ?? (ok ? "" : "The server answered \(status).")
            DispatchQueue.main.async { completion(ok ? data : nil, why) }
        }.resume()
    }
    static func search(_ query: String, completion: @escaping ([PodcastShow]?, String) -> Void) {
        guard let url = PodcastLinks.searchURL(query) else { completion(nil, "That search can't be sent."); return }
        get(url) { data, why in completion(data.map(ITunesPodcasts.search), why) }
    }
    // A show's episodes, newest first: an Apple Podcasts show link (its lookup, else its feed) or a feed link.
    static func episodes(_ link: String, completion: @escaping (PodcastShow?, [PodcastEpisode], String) -> Void) {
        if let ids = PodcastLinks.parse(link), let url = PodcastLinks.lookupURL(show: ids.show) {
            get(url) { data, why in
                let read: (show: PodcastShow?, episodes: [PodcastEpisode]) = data.map { ITunesPodcasts.lookup($0) } ?? (nil, [])
                guard read.episodes.isEmpty, let named = read.show, let feedURL = named.feedURL else {
                    completion(read.show, read.episodes, why); return
                }
                feed(feedURL) { show, episodes, why in      // the lookup lists no episodes: the show's own feed
                    var shown = named
                    if shown.artwork == nil { shown.artwork = show?.artwork }
                    completion(shown, episodes.map { e in var e = e; e.showID = ids.show; return e }, why)
                }
            }
        } else {
            feed(link, completion: completion)
        }
    }
    static func feed(_ link: String, completion: @escaping (PodcastShow?, [PodcastEpisode], String) -> Void) {
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true else { completion(nil, [], "That isn't a feed link."); return }
        get(url) { data, why in
            guard let data = data else { completion(nil, [], why); return }
            guard var read = PodcastFeed.parse(data) else { completion(nil, [], "That page isn't a podcast feed."); return }
            read.show.feedURL = link
            completion(read.show, read.episodes, "")
        }
    }
    // An Apple Podcasts episode link → the episode (from its show's lookup; nil when it isn't among the newest 200).
    static func episode(_ link: String, completion: @escaping (PodcastEpisode?) -> Void) {
        guard let ids = PodcastLinks.parse(link), let episode = ids.episode, let url = PodcastLinks.lookupURL(show: ids.show) else {
            completion(nil); return
        }
        get(url) { data, _ in completion(data.flatMap { ITunesPodcasts.episode(episode, in: $0) }) }
    }
}

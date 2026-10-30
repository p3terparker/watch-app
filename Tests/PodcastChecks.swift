import Foundation

// Podcasts (Podcasts.swift): Apple Podcasts links, the iTunes Lookup/Search answers and RSS feeds. Fixture data only.
func checkPodcasts() {
    // Links.
    let episodeLink = "https://podcasts.apple.com/gb/podcast/the-fixture-hour/id1234567890?i=1000654321098"
    let showLink = "https://podcasts.apple.com/us/podcast/the-fixture-hour/id1234567890"
    expect(PodcastLinks.parse(episodeLink).map { $0.show == "1234567890" && $0.episode == "1000654321098" } == true, "an episode link: show and episode ids")
    expect(PodcastLinks.parse(showLink).map { $0.show == "1234567890" && $0.episode == nil } == true, "a show link: the show's id")
    expect(PodcastLinks.isEpisode(episodeLink) && !PodcastLinks.isShow(episodeLink), "an episode is not a show")
    expect(PodcastLinks.isShow(showLink) && !PodcastLinks.isEpisode(showLink), "a show is not an episode")
    expect(PodcastLinks.isShow("https://podcasts.apple.com/podcast/id42"), "no country or slug")
    for bad in ["https://podcasts.apple.com/us/podcast/x/idABC", "https://podcasts.apple.com/us/browse", "https://example.com/podcast/id123",
                "podcasts.apple.com/us/podcast/x/id123", "not a link"] {
        expect(PodcastLinks.parse(bad) == nil, "not a podcast link: \(bad)")
    }
    expect(PodcastLinks.parse("https://podcasts.apple.com/us/podcast/x/id123?i=12a")?.episode == nil, "a malformed episode id is ignored")
    for feed in ["https://feeds.fixture.invalid/show", "https://fixture.invalid/podcast.rss", "https://fixture.invalid/show/feed/",
                 "https://fixture.invalid/feed", "https://fixture.invalid/episodes.xml"] {
        expect(PodcastLinks.isFeed(feed), "a feed: \(feed)")
    }
    for page in ["https://www.youtube.com/watch?v=abc", "https://fixture.invalid/feedback", "file:///tmp/a.rss", "https://fixture.invalid/"] {
        expect(!PodcastLinks.isFeed(page), "not a feed: \(page)")
    }
    let search = PodcastLinks.searchURL("fixture & friends")?.absoluteString ?? ""
    expect(search.hasPrefix("https://itunes.apple.com/search?") && search.contains("media=podcast") && search.contains("term=fixture%20%26%20friends"),
           "the search query is escaped: \(search)")
    expect(PodcastLinks.lookupURL(show: "1234567890")?.absoluteString == "https://itunes.apple.com/lookup?id=1234567890&entity=podcastEpisode&limit=200",
           "a show's lookup asks for its episodes")
    expect(PodcastLinks.episodeLink(show: "1234567890", episode: "1000654321098") == "https://podcasts.apple.com/podcast/id1234567890?i=1000654321098",
           "an episode's Apple Podcasts link")

    // iTunes Lookup: the show first, then its episodes.
    let lookup = """
    {"resultCount":3,"results":[
     {"wrapperType":"track","kind":"podcast","collectionId":1234567890,"collectionName":"The Fixture Hour","artistName":"Fixture FM",
      "feedUrl":"https://feeds.fixture.invalid/hour","artworkUrl600":"https://img.fixture.invalid/600.jpg","artworkUrl100":"https://img.fixture.invalid/100.jpg"},
     {"wrapperType":"podcastEpisode","kind":"podcast-episode","trackId":1000654321098,"trackName":"Episode 2: Tests","collectionName":"The Fixture Hour",
      "episodeUrl":"https://cdn.fixture.invalid/ep2.mp3","releaseDate":"2026-10-28T08:00:00Z","trackTimeMillis":3723000,
      "artworkUrl600":"https://img.fixture.invalid/ep2.jpg"},
     {"wrapperType":"podcastEpisode","kind":"podcast-episode","trackId":1000654321000,"trackName":"Episode 1","episodeUrl":"https://cdn.fixture.invalid/ep1.mp3"},
     {"wrapperType":"podcastEpisode","kind":"podcast-episode","trackId":1000654320000,"trackName":"No audio"}
    ]}
    """
    let read = ITunesPodcasts.lookup(Data(lookup.utf8))
    expect(read.show == PodcastShow(title: "The Fixture Hour", author: "Fixture FM", feedURL: "https://feeds.fixture.invalid/hour",
                                    artwork: "https://img.fixture.invalid/600.jpg", appleID: "1234567890"), "the show: \(String(describing: read.show))")
    expect(read.episodes.map(\.title) == ["Episode 2: Tests", "Episode 1"], "episodes with audio, newest first: \(read.episodes.map(\.title))")
    let ep2 = read.episodes[0]
    expect(ep2.audioURL == "https://cdn.fixture.invalid/ep2.mp3" && ep2.duration == 3723 && ep2.appleID == "1000654321098" && ep2.showID == "1234567890"
           && ep2.page == "https://podcasts.apple.com/podcast/id1234567890?i=1000654321098"
           && ep2.artwork == "https://img.fixture.invalid/ep2.jpg" && ep2.show == "The Fixture Hour"
           && ep2.published == ISO8601DateFormatter().date(from: "2026-10-28T08:00:00Z"), "episode details: \(ep2)")
    let ep1 = read.episodes[1]
    expect(ep1.artwork == "https://img.fixture.invalid/600.jpg" && ep1.show == "The Fixture Hour" && ep1.duration == nil && ep1.published == nil,
           "an episode without its own picture, show or length takes the show's")
    expect(ITunesPodcasts.episode("1000654321000", in: Data(lookup.utf8))?.title == "Episode 1", "an episode by its id")
    expect(ITunesPodcasts.episode("999", in: Data(lookup.utf8)) == nil, "an episode the lookup doesn't list")
    expect(ITunesPodcasts.lookup(Data("not json".utf8)).episodes.isEmpty && ITunesPodcasts.lookup(Data("{}".utf8)).show == nil, "a bad answer is empty")

    // iTunes Search: shows.
    let found = ITunesPodcasts.search(Data("""
    {"resultCount":2,"results":[
     {"wrapperType":"track","kind":"podcast","collectionId":1,"collectionName":"  Fixture One ","artistName":"A","feedUrl":"https://feeds.fixture.invalid/1","artworkUrl100":"https://img.fixture.invalid/1.jpg"},
     {"wrapperType":"track","kind":"podcast","collectionId":2,"trackName":"Fixture Two"},
     {"wrapperType":"track","kind":"podcast","collectionId":3}
    ]}
    """.utf8))
    expect(found.map(\.title) == ["Fixture One", "Fixture Two"] && found[0].appleID == "1" && found[0].artwork == "https://img.fixture.invalid/1.jpg"
           && found[1].feedURL == nil, "search results: \(found)")

    // RSS.
    let rss = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
      <title>The Fixture Feed</title>
      <itunes:author>Fixture FM</itunes:author>
      <image><url>https://img.fixture.invalid/rss.jpg</url><title>The Fixture Feed (image)</title></image>
      <itunes:image href="https://img.fixture.invalid/itunes.jpg"/>
      <item>
        <title><![CDATA[Episode 3 & more]]></title>
        <pubDate>Thu, 29 Oct 2026 08:00:00 +0000</pubDate>
        <itunes:duration>1:02:03</itunes:duration>
        <itunes:image href="https://img.fixture.invalid/ep3.jpg"/>
        <enclosure url="https://cdn.fixture.invalid/ep3.mp3" length="1" type="audio/mpeg"/>
      </item>
      <item>
        <title>Episode 2</title>
        <pubDate>Wed, 28 Oct 2026 08:00 GMT</pubDate>
        <itunes:duration>62:03</itunes:duration>
        <enclosure url="https://cdn.fixture.invalid/ep2.m4a" type="audio/x-m4a"/>
      </item>
      <item><title>Text only</title></item>
      <item><title>Episode 1</title><itunes:duration>95</itunes:duration><enclosure url="https://cdn.fixture.invalid/ep1.mp3"/></item>
    </channel>
    </rss>
    """
    guard let feed = PodcastFeed.parse(Data(rss.utf8)) else { expect(false, "the fixture feed parses"); return }
    expect(feed.show.title == "The Fixture Feed" && feed.show.author == "Fixture FM" && feed.show.artwork == "https://img.fixture.invalid/itunes.jpg",
           "the channel, with its iTunes picture: \(feed.show)")
    expect(feed.episodes.map(\.title) == ["Episode 3 & more", "Episode 2", "Episode 1"], "items with audio, in the feed's order: \(feed.episodes.map(\.title))")
    expect(feed.episodes.map(\.audioURL) == ["https://cdn.fixture.invalid/ep3.mp3", "https://cdn.fixture.invalid/ep2.m4a", "https://cdn.fixture.invalid/ep1.mp3"],
           "enclosures")
    expect(feed.episodes.map(\.duration) == [3723, 3723, 95], "durations: \(feed.episodes.map(\.duration))")
    expect(feed.episodes[0].artwork == "https://img.fixture.invalid/ep3.jpg" && feed.episodes[1].artwork == "https://img.fixture.invalid/itunes.jpg",
           "an item's own picture, else the show's")
    expect(feed.episodes.allSatisfy { $0.show == "The Fixture Feed" }, "every episode knows its show")
    let calendar = Calendar(identifier: .gregorian)
    expect(feed.episodes[0].published.map { calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: $0).day } == 29, "RFC 822 date")
    expect(feed.episodes[1].published != nil && feed.episodes[2].published == nil, "a zone name and no seconds; no date")
    expect(PodcastFeed.parse(Data("<html><body>not a feed</body></html>".utf8)) == nil, "a web page is not a feed")
    expect(PodcastFeed.duration("") == nil && PodcastFeed.duration("abc") == nil && PodcastFeed.duration("1:2:3:4") == nil && PodcastFeed.duration("0") == nil,
           "bad durations")
    expect(PodcastFeed.duration("3723.5") == 3723.5, "seconds")

    // Queue items for episodes: played by Watch, with the Apple Podcasts page when known.
    let item = PodcastEpisode(title: "E", audioURL: "https://cdn.fixture.invalid/e.mp3", show: "S", appleID: "77", showID: "1234567890").queueItem()
    expect(item.source == .podcast && item.url == "https://cdn.fixture.invalid/e.mp3" && item.subtitle == "S"
           && item.page == "https://podcasts.apple.com/podcast/id1234567890?i=77", "an episode in Up Next: \(item)")
    expect(PodcastEpisode(title: "E", audioURL: "https://cdn.fixture.invalid/e.mp3").queueItem().page == nil, "a feed episode has no Apple page")
    expect(feed.episodes.allSatisfy { $0.page == nil && $0.queueItem().source == .podcast }, "feed episodes play as podcasts, without a page")
    expect(VideoLinks.key(episodeLink) == "podcast:1000654321098" && VideoLinks.key(ep2.page ?? "") == "podcast:1000654321098",
           "one resume key per episode, whatever its link looks like")
    expect(item.resumeKey == "podcast:77" && QueueItem(url: episodeLink).resumeKey == "podcast:1000654321098"
           && PodcastEpisode(title: "E", audioURL: "https://cdn.fixture.invalid/e.mp3").queueItem().resumeKey == "https://cdn.fixture.invalid/e.mp3",
           "an episode resumes by its Apple Podcasts id, else by its audio")
    expect(VideoLinks.key(showLink) == showLink && VideoLinks.site(episodeLink) == "Apple Podcasts", "a show link is just a link; the site's name")
    expect(MediaSource.of(episodeLink) == .podcast && MediaSource.of(showLink) == .web, "an Apple Podcasts episode link is a podcast item")
    expect(OmniboxInput.parse(showLink) == .podcast(showLink) && OmniboxInput.parse("https://feeds.fixture.invalid/show") == .podcast("https://feeds.fixture.invalid/show"),
           "a show link or a feed opens the show's episodes")
    expect(OmniboxInput.parse(episodeLink) == .play(episodeLink), "an episode link plays")
    expect(VideoLinks.classify(episodeLink) == .video && VideoLinks.classify(showLink) == .other, "Recent Links keeps episodes, not shows")
}

import Foundation

/// A narrated article from the site's GSR Audio Articles page (granitestatereport.com/audio-library/).
public struct AudioArticle: Codable, Hashable, Identifiable, Sendable {
    public var title: String
    public var articleURL: URL
    /// As the page writes it: "October 5, 2026".
    public var date: String
    /// The page's label for the voice: "Dexter Dow’s voice" or "Synthetic voice".
    public var voice: String
    /// The page marks recordings made with a synthetic voice; the rest use a voice clone
    /// built from the editor's recordings, as the page's note says.
    public var isSynthetic: Bool
    /// "11:07".
    public var duration: String
    public var audioURL: URL
    /// The page's note under some recordings ("Evidence track: ..."), word for word.
    public var note: String?

    public var id: String { audioURL.absoluteString }
}

/// The Audio Articles page: its note on how the recordings are made, word for word, and
/// every recording, newest first.
public struct AudioLibrary: Hashable, Sendable {
    public var disclosure: String
    public var articles: [AudioArticle]

    /// The narration for an article, matched by its address. Some articles also have an
    /// extra track with a note ("Evidence track"); the full narration is the one without.
    public func narration(for articleURL: URL) -> AudioArticle? {
        let key = Self.key(articleURL)
        let all = articles.filter { Self.key($0.articleURL) == key }
        return all.first { $0.note == nil } ?? all.first
    }

    static func key(_ url: URL) -> String {
        var s = url.absoluteString.lowercased()
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        s = s.replacingOccurrences(of: "http://", with: "https://")
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/// An episode from the site's GSR Podcast page (granitestatereport.com/podcast/).
public struct PodcastEpisode: Hashable, Identifiable, Sendable {
    public struct Line: Hashable, Sendable {
        public var speaker: String?
        public var text: String
    }

    public var title: String
    /// "Made October 11, 2026".
    public var made: String
    /// The page's label for who speaks: "AI hosts" or "Scripted from the articles".
    public var hosts: String
    public var duration: String
    public var summary: String
    public var audioURL: URL
    public var articles: [ReadFirstSection.Link]
    /// The listener's note: where the hosts' wording drifts from the record. Word for word.
    public var note: [String]
    public var transcript: [Line]

    public var id: String { audioURL.absoluteString }
}

/// The Podcast page: its note on how episodes are made, word for word, and the episodes.
public struct Podcast: Hashable, Sendable {
    public var disclosure: String
    public var episodes: [PodcastEpisode]
}

public enum ListenError: Error, Equatable {
    /// The page loaded but no longer reads the way the app expects. The app sends people
    /// to the page instead of showing recordings without the page's note about them.
    case pageChanged(String)
}

/// Reads the Audio Articles and Podcast pages. The pages are the source: the app shows what
/// they list, with the notes they carry, and plays the same files.
public struct ListenClient: Sendable {
    public static let audioLibraryPage = URL(string: "https://granitestatereport.com/audio-library/")!
    public static let podcastPage = URL(string: "https://granitestatereport.com/podcast/")!

    public let transport: HTTPTransport
    public let userAgent: String

    public init(transport: HTTPTransport = URLSessionTransport(), userAgent: String = GSRApp.userAgent) {
        self.transport = transport
        self.userAgent = userAgent
    }

    public func audioLibrary() async throws -> AudioLibrary {
        try Self.parseLibrary(try await page(Self.audioLibraryPage))
    }

    public func podcast() async throws -> Podcast {
        try Self.parsePodcast(try await page(Self.podcastPage))
    }

    private func page(_ url: URL) async throws -> String {
        let req = HTTPRequest(url: url, headers: ["Accept": "text/html", "User-Agent": userAgent], timeout: 30)
        let res = try await transport.send(req)
        guard (200..<300).contains(res.status) else {
            throw DropError.rejected(status: res.status, code: nil, message: "The page did not load (\(res.status)).")
        }
        return String(decoding: res.body, as: UTF8.self)
    }

    // MARK: Parsing

    public static func parseLibrary(_ html: String) throws -> AudioLibrary {
        // The note sits in the paragraph just above the search bar.
        guard let bar = html.range(of: "<div class=\"gsra-bar\""),
              let p = html[..<bar.lowerBound].range(of: "<p>", options: .backwards) else {
            throw ListenError.pageChanged("the note about the voices")
        }
        let disclosure = HTMLText.plain(String(html[p.lowerBound..<bar.lowerBound]))
        guard disclosure.lowercased().contains("voice") else { throw ListenError.pageChanged("the note about the voices") }

        let item = #"<div class="gsra-item[^"]*" data-voice="([^"]*)">\s*<h3><a href="([^"]+)">(.*?)</a></h3>\s*<div class="gsra-meta">(.*?)</div>\s*(?:<p class="gsra-note">(.*?)</p>\s*)?<audio[^>]*\ssrc="([^"]+)""#
        var articles: [AudioArticle] = []
        for m in HTMLScan.all(item, in: html) {
            guard let link = URL(string: HTMLText.decodeEntities(m[2])),
                  let audio = URL(string: HTMLText.decodeEntities(m[6])) else { continue }
            let meta = HTMLText.plain(m[4]).components(separatedBy: " · ")
            articles.append(AudioArticle(title: HTMLText.plain(m[3]), articleURL: link,
                                         date: meta.first ?? "",
                                         voice: meta.count > 2 ? meta[1] : "",
                                         isSynthetic: m[1] == "synthetic",
                                         duration: meta.count > 1 ? meta[meta.count - 1] : "",
                                         audioURL: audio,
                                         note: m[5].isEmpty ? nil : HTMLText.plain(m[5])))
        }
        guard !articles.isEmpty else { throw ListenError.pageChanged("the list of recordings") }
        return AudioLibrary(disclosure: disclosure, articles: articles)
    }

    public static func parsePodcast(_ html: String) throws -> Podcast {
        // The note is the boxed paragraph above the episode list.
        guard let list = html.range(of: "<h2>Episodes</h2>"),
              let box = html[..<list.lowerBound].range(of: "<div class=\"gsr-statute-box\">", options: .backwards),
              let end = html[box.upperBound..<list.lowerBound].range(of: "</div>") else {
            throw ListenError.pageChanged("the note about how episodes are made")
        }
        let disclosure = HTMLText.plain(String(html[box.upperBound..<end.lowerBound]))

        var episodes: [PodcastEpisode] = []
        for m in HTMLScan.all(#"<section class="gsrp-ep"[^>]*>(.*?)</section>"#, in: html) {
            let ep = m[1]
            guard let title = HTMLScan.first(#"<h2>(.*?)</h2>"#, in: ep),
                  let meta = HTMLScan.first(#"<div class="gsra-meta">(.*?)</div>"#, in: ep),
                  let src = HTMLScan.first(#"<audio[^>]*\ssrc="([^"]+)""#, in: ep),
                  let audio = URL(string: HTMLText.decodeEntities(src)) else { continue }
            let parts = HTMLText.plain(meta).components(separatedBy: " · ")
            // The summary is the paragraph between the meta line and the player.
            var summary = ""
            if let m0 = ep.range(of: "<div class=\"gsra-meta\">"), let a0 = ep.range(of: "<audio") , m0.upperBound < a0.lowerBound {
                summary = HTMLScan.first(#"<p>(.*?)</p>"#, in: String(ep[m0.upperBound..<a0.lowerBound])).map(HTMLText.plain) ?? ""
            }
            var articles: [ReadFirstSection.Link] = []
            if let h = ep.range(of: "Articles discussed"), let ul = HTMLScan.first(#"<ul>(.*?)</ul>"#, in: String(ep[h.upperBound...])) {
                for a in HTMLScan.all(#"<a href="([^"]+)"[^>]*>(.*?)</a>"#, in: ul) {
                    if let u = URL(string: HTMLText.decodeEntities(a[1])) {
                        articles.append(.init(text: HTMLText.plain(a[2]), url: u))
                    }
                }
            }
            var note: [String] = []
            if let body = HTMLScan.first(#"<div class="gsrp-note">(.*?)</div>"#, in: ep) {
                for b in HTMLScan.all(#"<(p|li)\b[^>]*>(.*?)</\1>"#, in: body) {
                    let t = HTMLText.plain(b[2])
                    if !t.isEmpty, !t.lowercased().hasPrefix("listener") || b[1] == "li" { note.append(t) }
                }
            }
            var transcript: [PodcastEpisode.Line] = []
            if let tx = HTMLScan.first(#"<details class="gsrp-tx">(.*?)</details>"#, in: ep) {
                for p in HTMLScan.all(#"<p>(.*?)</p>"#, in: tx) {
                    if let s = HTMLScan.all(#"^\s*<strong>(.*?):?</strong>:?\s*(.*)$"#, in: p[1]).first {
                        transcript.append(.init(speaker: HTMLText.plain(s[1]).trimmingCharacters(in: CharacterSet(charactersIn: ":")), text: HTMLText.plain(s[2])))
                    } else {
                        let t = HTMLText.plain(p[1])
                        if !t.isEmpty { transcript.append(.init(speaker: nil, text: t)) }
                    }
                }
            }
            episodes.append(PodcastEpisode(title: HTMLText.plain(title),
                                           made: parts.first ?? "",
                                           hosts: parts.count > 2 ? parts[1] : "",
                                           duration: parts.count > 1 ? parts[parts.count - 1] : "",
                                           summary: summary, audioURL: audio, articles: articles,
                                           note: note, transcript: transcript))
        }
        guard !episodes.isEmpty, !disclosure.isEmpty else { throw ListenError.pageChanged("the list of episodes") }
        return Podcast(disclosure: disclosure, episodes: episodes)
    }
}

/// "11:07" or "1:02:03" in seconds.
public enum Clock {
    public static func seconds(_ s: String) -> TimeInterval? {
        let parts = s.split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), !parts.contains(where: { $0 == nil }) else { return nil }
        return TimeInterval(parts.reduce(0) { $0 * 60 + $1! })
    }

    /// 3725 -> "1:02:05", 65 -> "1:05".
    public static func text(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let t = Int(seconds.rounded(.down))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Small regular-expression helpers for reading the site's own markup.
enum HTMLScan {
    /// Every match, each as [whole match, group 1, group 2, ...]; missing groups are "".
    static func all(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    /// Group 1 of the first match.
    static func first(_ pattern: String, in text: String) -> String? {
        all(pattern, in: text).first.map { $0.count > 1 ? $0[1] : $0[0] }
    }
}

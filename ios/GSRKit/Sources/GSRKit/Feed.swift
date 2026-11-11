import Foundation

/// A published story, from the site's public WordPress REST API.
public struct Story: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var published: Date
    public var link: URL
    public var title: String
    public var excerpt: String
    public var imageURL: URL?
}

/// Reads the latest stories from granitestatereport.com. Public data only; sends nothing
/// about the reader beyond the request itself.
public struct FeedClient: Sendable {
    public let site: URL
    public let transport: HTTPTransport
    public let userAgent: String

    public init(site: URL = GSRContact.site, transport: HTTPTransport = URLSessionTransport(), userAgent: String = GSRApp.userAgent) {
        self.site = site
        self.transport = transport
        self.userAgent = userAgent
    }

    func latestURL(count: Int) -> URL {
        var s = site.absoluteString
        if !s.hasSuffix("/") { s += "/" }
        s += "wp-json/wp/v2/posts?per_page=\(max(1, min(count, 100)))&_fields=id,date_gmt,link,title,excerpt,jetpack_featured_media_url"
        return URL(string: s)!
    }

    public func latest(count: Int = 20) async throws -> [Story] {
        let req = HTTPRequest(url: latestURL(count: count), headers: ["Accept": "application/json", "User-Agent": userAgent], timeout: 30)
        let res = try await transport.send(req)
        guard (200..<300).contains(res.status) else {
            throw DropError.rejected(status: res.status, code: nil, message: "The story list did not load (\(res.status)).")
        }
        return try Self.decode(res.body)
    }

    static func decode(_ data: Data) throws -> [Story] {
        struct Rendered: Decodable { let rendered: String? }
        struct Post: Decodable {
            let id: Int
            let date_gmt: String?
            let link: String
            let title: Rendered?
            let excerpt: Rendered?
            let jetpack_featured_media_url: String?
        }
        let posts = try JSONDecoder().decode([Post].self, from: data)
        return posts.compactMap { p in
            guard let link = URL(string: p.link) else { return nil }
            let image = p.jetpack_featured_media_url.flatMap { $0.isEmpty ? nil : URL(string: $0) }
            return Story(id: p.id,
                         published: p.date_gmt.flatMap(parseGMT) ?? Date(timeIntervalSince1970: 0),
                         link: link,
                         title: HTMLText.plain(p.title?.rendered ?? ""),
                         excerpt: HTMLText.plain(p.excerpt?.rendered ?? ""),
                         imageURL: image)
        }
    }

    /// WordPress `date_gmt` is "2026-09-29T14:13:34", UTC with no zone marker.
    static func parseGMT(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }
}

/// Turns the HTML WordPress returns in titles and excerpts into plain text.
public enum HTMLText {
    public static func plain(_ html: String) -> String {
        var s = html
        // Block-level breaks become spaces; every other tag goes.
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</p>", with: " ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}", "middot": "\u{00B7}",
        "sect": "\u{00A7}", "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
        "bull": "\u{2022}", "laquo": "\u{00AB}", "raquo": "\u{00BB}", "deg": "\u{00B0}",
        "eacute": "\u{00E9}", "egrave": "\u{00E8}", "aacute": "\u{00E1}", "oacute": "\u{00F3}",
        "uuml": "\u{00FC}", "ouml": "\u{00F6}", "auml": "\u{00E4}", "ntilde": "\u{00F1}", "ccedil": "\u{00E7}",
    ]

    /// Decodes `&#8217;`, `&#x2019;`, and the named entities WordPress emits. Unknown
    /// entities are left as written.
    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let body = s[s.index(after: i)..<semi]
                var replacement: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    if let v = UInt32(body.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
                } else if body.hasPrefix("#") {
                    if let v = UInt32(body.dropFirst()), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
                } else {
                    replacement = named[String(body)]
                }
                if let r = replacement {
                    out += r
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}

public enum ByteFormat {
    /// "1.5 MB", the way the page's `human()` writes sizes (1024-based, one decimal).
    public static func human(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var b = Double(bytes)
        var i = 0
        while b >= 1024 && i < 3 {
            b /= 1024
            i += 1
        }
        if i == 0 { return "\(bytes) \(units[0])" }
        return String(format: "%.1f %@", b, units[i])
    }
}

/// Names for files the app makes itself ("photo-3f9a1c2e.jpg"): a word and a short random
/// tag. Never a date or time: the name goes to the server with the file, and a capture
/// time in the name would undo removing it from the file.
public enum FileNaming {
    public static func stamped(_ prefix: String, ext: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased()).\(ext)"
    }
}

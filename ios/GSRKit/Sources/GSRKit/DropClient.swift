import Foundation

/// Size limits the drop box sends back from `start`.
public struct DropLimits: Codable, Hashable, Sendable {
    /// Bytes per upload piece.
    public var chunk: Int
    public var maxFile: Int64
    public var maxFiles: Int
    public var maxTotal: Int64

    /// The values the web page starts with before the server answers (GSR Drop Box 1.0.0).
    public static let pageDefaults = DropLimits(chunk: 4_194_304, maxFile: 2_147_483_648, maxFiles: 50, maxTotal: 10_737_418_240)

    public init(chunk: Int, maxFile: Int64, maxFiles: Int, maxTotal: Int64) {
        self.chunk = chunk
        self.maxFile = maxFile
        self.maxFiles = maxFiles
        self.maxTotal = maxTotal
    }
}

/// The server's id for an uploaded file. Kept in whatever JSON type the server used,
/// so `remove` sends it back exactly as `add` returned it.
public enum DropFileID: Codable, Hashable, Sendable, CustomStringConvertible {
    case number(Int64)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int64.self) {
            self = .number(n)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        }
    }

    public var description: String {
        switch self {
        case .number(let n): return String(n)
        case .string(let s): return s
        }
    }
}

public enum DropError: Error, Hashable, Sendable {
    /// A 4xx the client cannot fix by retrying. `message` is the server's own words.
    case rejected(status: Int, code: String?, message: String?)
    /// 5xx other than 507, or 429. Worth retrying.
    case serverBusy(status: Int, message: String?)
    /// 507: the site's storage is full.
    case storageFull(message: String?)
    /// 410: the upload session is gone; start a new one.
    case sessionExpired(message: String?)
    /// 409 with the byte count the server already holds for this file.
    case offsetMismatch(received: Int64)
    /// No HTTP response at all (offline, timeout, connection dropped).
    case network(String)
    /// A response the client could not read.
    case badResponse(String)

    public var isRetryable: Bool {
        switch self {
        case .serverBusy, .network: return true
        default: return false
        }
    }

    /// What to show the sender. Uses the server's message when it sent one, as the page does.
    public var userMessage: String {
        switch self {
        case .rejected(let status, _, let message): return message ?? "Server said \(status)"
        case .serverBusy(let status, let message): return message ?? "Server said \(status)"
        case .storageFull(let message): return message ?? "The drop box is full right now. Try again later, or use Signal or the mail."
        case .sessionExpired(let message): return message ?? "The upload session ran out. Starting a new one."
        case .offsetMismatch: return "Picking up where the upload left off."
        case .network: return "Could not reach Granite State Report. Check your connection."
        case .badResponse: return "The server sent an answer the app could not read."
        }
    }
}

/// Speaks the GSR Drop Box REST API (`/wp-json/gsr-drop/v1/`), request for request as the
/// site's own `dropbox.js` does. See `ios/reference/gsr-dropbox-1.0.0.js`.
public struct DropClient: Sendable {
    public let api: URL
    public let transport: HTTPTransport
    public let userAgent: String

    public init(api: URL = DropCatalog.bundled.api, transport: HTTPTransport = URLSessionTransport(), userAgent: String = GSRApp.userAgent) {
        self.api = api
        self.transport = transport
        self.userAgent = userAgent
    }

    public struct Session: Hashable, Sendable {
        public var token: String
        public var limits: DropLimits
    }

    /// `POST start {form, website}`. `website` is the page's honeypot field and is always empty.
    public func start(form: String) async throws -> Session {
        struct Body: Encodable { let form: String; let website: String }
        struct Reply: Decodable {
            let token: String
            let chunk: Int?
            let maxFile: Int64?
            let maxFiles: Int?
            let maxTotal: Int64?
        }
        let r: Reply = try await postJSON("start", Body(form: form, website: ""))
        let d = DropLimits.pageDefaults
        let limits = DropLimits(
            chunk: (r.chunk ?? 0) > 0 ? r.chunk! : d.chunk,
            maxFile: (r.maxFile ?? 0) > 0 ? r.maxFile! : d.maxFile,
            maxFiles: (r.maxFiles ?? 0) > 0 ? r.maxFiles! : d.maxFiles,
            maxTotal: (r.maxTotal ?? 0) > 0 ? r.maxTotal! : d.maxTotal
        )
        return Session(token: r.token, limits: limits)
    }

    /// `POST add {token, name, size, type}` → the server's id for the file.
    public func add(token: String, name: String, size: Int64, type: String) async throws -> DropFileID {
        struct Body: Encodable { let token: String; let name: String; let size: Int64; let type: String }
        struct Reply: Decodable { let id: DropFileID }
        let r: Reply = try await postJSON("add", Body(token: token, name: name, size: size, type: type))
        return r.id
    }

    /// `POST chunk?token&file&offset` with raw bytes → how many bytes the server now holds.
    /// A 409 carrying `received` throws `.offsetMismatch(received)` so the caller can resync.
    public func chunk(token: String, file: DropFileID, offset: Int64, data: Data) async throws -> Int64 {
        let url = endpoint("chunk", query: [("token", token), ("file", file.description), ("offset", String(offset))])
        var req = HTTPRequest(url: url, method: "POST", headers: baseHeaders, body: data, timeout: 120)
        req.headers["Content-Type"] = "application/octet-stream"
        let res = try await send(req)
        struct Reply: Decodable { let received: Int64? }
        let reply = try? JSONDecoder().decode(Reply.self, from: res.body)
        if res.status == 409, let received = reply?.received {
            throw DropError.offsetMismatch(received: received)
        }
        try Self.check(res)
        guard let received = reply?.received else {
            throw DropError.badResponse("chunk reply has no received count")
        }
        return received
    }

    /// `POST remove {token, file}`.
    public func remove(token: String, file: DropFileID) async throws {
        struct Body: Encodable { let token: String; let file: DropFileID }
        let _: Ignored = try await postJSON("remove", Body(token: token, file: file))
    }

    /// `POST finish {token, main, fields}`: sends the note and closes the submission.
    public func finish(token: String, main: String, fields: [String: FieldValue]) async throws {
        struct Body: Encodable { let token: String; let main: String; let fields: [String: FieldValue] }
        let _: Ignored = try await postJSON("finish", Body(token: token, main: main, fields: fields))
    }

    // MARK: - Plumbing

    private struct Ignored: Decodable {}

    var baseHeaders: [String: String] {
        ["Accept": "application/json", "User-Agent": userAgent]
    }

    func endpoint(_ path: String, query: [(String, String)] = []) -> URL {
        var s = api.absoluteString
        if !s.hasSuffix("/") { s += "/" }
        s += path
        if !query.isEmpty {
            s += "?" + query.map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }.joined(separator: "&")
        }
        return URL(string: s)!
    }

    /// Percent-encodes everything but unreserved characters, like `encodeURIComponent`
    /// minus its few extras, so a `+` or `&` in a token can never be misread.
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func postJSON<B: Encodable, R: Decodable>(_ path: String, _ body: B) async throws -> R {
        var req = HTTPRequest(url: endpoint(path), method: "POST", headers: baseHeaders, body: try JSONEncoder().encode(body))
        req.headers["Content-Type"] = "application/json"
        let res = try await send(req)
        try Self.check(res)
        if R.self == Ignored.self { return Ignored() as! R }
        do {
            return try JSONDecoder().decode(R.self, from: res.body)
        } catch {
            throw DropError.badResponse("\(path): \(error)")
        }
    }

    private func send(_ req: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(req)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw DropError.network(String(describing: error))
        }
    }

    /// Maps a non-2xx response to the error the page would act on.
    static func check(_ res: HTTPResponse) throws {
        guard !(200..<300).contains(res.status) else { return }
        struct WPError: Decodable { let code: String?; let message: String? }
        let e = try? JSONDecoder().decode(WPError.self, from: res.body)
        switch res.status {
        case 410: throw DropError.sessionExpired(message: e?.message)
        case 507: throw DropError.storageFull(message: e?.message)
        case 429, 500...599: throw DropError.serverBusy(status: res.status, message: e?.message)
        default: throw DropError.rejected(status: res.status, code: e?.code, message: e?.message)
        }
    }
}

/// Facts about the app the network layer needs.
public enum GSRApp {
    /// The marketing version from the running bundle's Info.plist (the app and its share
    /// extension carry the same one), so the server log names the build.
    public static let version: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    public static var userAgent: String { "GSR-iOS/\(version)" }
}

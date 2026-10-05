import Foundation
@testable import GSRKit

/// An in-memory GSR Drop Box that answers the way `dropbox.js` expects the real one to:
/// `start` → token and limits, `add` → id, `chunk` → received (409 with received on a wrong
/// offset), `remove`, `finish`. Faults can be injected per request.
final class MockDropServer: HTTPTransport, @unchecked Sendable {
    struct FileRecord {
        var name: String
        var size: Int64
        var type: String
        var data = Data()
        var removed = false
    }
    struct SessionRecord {
        var form: String
        var files: [Int: FileRecord] = [:]
        var finished: (main: String, fields: [String: Any])?
        var expired = false
    }

    enum Fault {
        case status(Int, String?)       // reply with this status and optional message
        case network                    // throw as a dropped connection would
        case wrongOffset(Int64)         // reply 409 with this received count
        case expire                     // mark the session gone and reply 410
        case answerLost                 // do the work, then drop the connection before replying
    }

    private let lock = NSLock()
    var limits = DropLimits(chunk: 8, maxFile: 1_000, maxFiles: 50, maxTotal: 10_000)
    var sessions: [String: SessionRecord] = [:]
    var nextToken = 1
    var nextFile = 1
    /// Faults keyed by endpoint name, consumed in order.
    var faults: [String: [Fault]] = [:]
    var requests: [HTTPRequest] = []
    var idsAsStrings = false

    func inject(_ endpoint: String, _ f: Fault...) {
        lock.lock(); defer { lock.unlock() }
        faults[endpoint, default: []].append(contentsOf: f)
    }

    var finishedSessions: [SessionRecord] {
        lock.lock(); defer { lock.unlock() }
        return sessions.values.filter { $0.finished != nil }
    }

    func count(_ endpoint: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.url.path.hasSuffix("/" + endpoint) }.count
    }

    /// Called (outside the lock) before each request is handled; tests use it to act mid-send.
    var onRequest: (@Sendable (HTTPRequest) async -> Void)?

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await Task.sleep(nanoseconds: 1_000) // let other tasks interleave
        if let hook = onRequest { await hook(request) }
        return try lock.withLock { try handle(request) }
    }

    private func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        requests.append(request)
        let endpoint = request.url.lastPathComponent
        if var list = faults[endpoint], !list.isEmpty {
            let f = list.removeFirst()
            faults[endpoint] = list
            switch f {
            case .answerLost:
                _ = try route(request, endpoint: endpoint)
                throw URLError(.networkConnectionLost)
            case .status(let s, let m): return json(s, ["code": "mock", "message": m as Any? ?? NSNull()])
            case .network: throw URLError(.networkConnectionLost)
            case .wrongOffset(let r): return json(409, ["received": r])
            case .expire:
                if let t = token(of: request) { sessions[t]?.expired = true }
                return json(410, ["code": "gsrdb_gone", "message": "That upload session has ended."])
            }
        }
        return try route(request, endpoint: endpoint)
    }

    private func route(_ request: HTTPRequest, endpoint: String) throws -> HTTPResponse {
        guard request.method == "POST" else { return json(405, ["message": "POST only"]) }
        switch endpoint {
        case "start":
            let body = obj(request)
            guard let form = body["form"] as? String, ["tips", "story", "inside", "nothing"].contains(form) else {
                return json(400, ["code": "gsrdb_form", "message": "Unknown form."])
            }
            guard (body["website"] as? String ?? "x").isEmpty else { return json(400, ["message": "spam"]) }
            let t = "tok\(nextToken)+/="  // characters that must be escaped in a query string
            nextToken += 1
            sessions[t] = SessionRecord(form: form)
            return json(200, ["token": t, "chunk": limits.chunk, "maxFile": limits.maxFile,
                              "maxFiles": limits.maxFiles, "maxTotal": limits.maxTotal])
        case "add":
            let body = obj(request)
            guard let t = body["token"] as? String, let s = sessions[t], !s.expired else { return gone() }
            let id = nextFile
            nextFile += 1
            sessions[t]!.files[id] = FileRecord(name: body["name"] as? String ?? "", size: (body["size"] as? NSNumber)?.int64Value ?? -1,
                                                type: body["type"] as? String ?? "")
            return json(200, ["id": idsAsStrings ? String(id) as Any : id as Any])
        case "chunk":
            let q = query(request)
            guard let t = q["token"], let s = sessions[t], !s.expired else { return gone() }
            guard let fid = Int(q["file"] ?? ""), var f = s.files[fid], !f.removed else { return json(404, ["message": "No such file."]) }
            let offset = Int64(q["offset"] ?? "") ?? -1
            guard request.headers["Content-Type"] == "application/octet-stream" else { return json(415, ["message": "bytes only"]) }
            if offset != Int64(f.data.count) { return json(409, ["received": f.data.count]) }
            let body = request.body ?? Data()
            if body.count > limits.chunk { return json(413, ["message": "Piece too big."]) }
            if Int64(f.data.count + body.count) > f.size { return json(400, ["message": "More bytes than the file size."]) }
            f.data.append(body)
            sessions[t]!.files[fid] = f
            return json(200, ["received": f.data.count])
        case "remove":
            let body = obj(request)
            guard let t = body["token"] as? String, sessions[t] != nil else { return gone() }
            let fid = (body["file"] as? NSNumber)?.intValue ?? Int(body["file"] as? String ?? "") ?? -1
            sessions[t]!.files[fid]?.removed = true
            return json(200, ["ok": true])
        case "finish":
            let body = obj(request)
            guard let t = body["token"] as? String, let s = sessions[t], !s.expired, s.finished == nil else { return gone() }
            for (_, f) in s.files where !f.removed && Int64(f.data.count) != f.size {
                return json(400, ["message": "A file is incomplete."])
            }
            sessions[t]!.finished = (body["main"] as? String ?? "", body["fields"] as? [String: Any] ?? [:])
            return json(200, ["ok": true])
        default:
            return json(404, ["message": "No route."])
        }
    }

    // MARK: helpers (lock held)

    private func gone() -> HTTPResponse { json(410, ["code": "gsrdb_gone", "message": "That upload session has ended."]) }

    private func json(_ status: Int, _ obj: [String: Any]) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["content-type": "application/json"],
                     body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }

    private func obj(_ r: HTTPRequest) -> [String: Any] {
        (r.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    private func query(_ r: HTTPRequest) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: r.url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            out[item.name] = item.value
        }
        return out
    }

    private func token(of r: HTTPRequest) -> String? {
        query(r)["token"] ?? obj(r)["token"] as? String
    }

    /// Every finished file's bytes, by name.
    func receivedFiles() -> [String: Data] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: Data] = [:]
        for s in sessions.values where s.finished != nil {
            for f in s.files.values where !f.removed { out[f.name] = f.data }
        }
        return out
    }
}

struct InstantSleeper: Sleeper {
    final class Log: @unchecked Sendable {
        let lock = NSLock()
        var waits: [Double] = []
    }
    let log = Log()
    func sleep(seconds: Double) async throws {
        log.lock.withLock { log.waits.append(seconds) }
        try Task.checkCancellation()
    }
}

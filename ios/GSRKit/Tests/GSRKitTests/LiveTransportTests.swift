import Foundation
import XCTest
@testable import GSRKit

/// Sends a real submission over HTTP with URLSessionTransport to ios/tools/mock_drop_server.py.
/// Skipped unless GSR_MOCK_DROP_URL is set (the CI core job sets it).
final class LiveTransportTests: XCTestCase {
    func testRealHTTPSubmissionRoundTrip() async throws {
        guard let raw = ProcessInfo.processInfo.environment["GSR_MOCK_DROP_URL"], let api = URL(string: raw) else {
            throw XCTSkip("Set GSR_MOCK_DROP_URL to run against ios/tools/mock_drop_server.py")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gsr-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try OutboxStore(root: dir)
        let form = try XCTUnwrap(DropCatalog.bundled.form("story"))
        var s = try store.create(form: form)
        s.main = "Live transport test: a note with ünïcödé, & an ampersand + a plus."
        s.fields["maycontact"] = .flag(true)
        s.fields["town"] = .text("Northfield")
        // 200 KB, so it goes in several 64 KB pieces.
        var bytes = Data(count: 200_000)
        for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: i &* 31) }
        let src = dir.appendingPathComponent("evidence.bin")
        try bytes.write(to: src)
        try store.addFile(to: &s, from: src, displayName: "evidence & notes.bin")
        try store.save(s)

        let up = SubmissionUploader(submission: s, form: form, store: store,
                                    client: DropClient(api: api, transport: URLSessionTransport(), userAgent: "GSR-iOS/test"))
        let result = try await up.send()
        XCTAssertEqual(result, .sent(failedFiles: 0))

        let stateURL = URL(string: "/_state", relativeTo: api)!.absoluteURL
        let res = try await URLSessionTransport().send(HTTPRequest(url: stateURL))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: res.body) as? [String: [String: Any]])
        let mine = try XCTUnwrap(state.values.first { ($0["finished"] as? [String: Any])?["main"] as? String == s.main })
        XCTAssertEqual(mine["form"] as? String, "story")
        let fields = try XCTUnwrap((mine["finished"] as? [String: Any])?["fields"] as? [String: Any])
        XCTAssertEqual(fields["maycontact"] as? Bool, true)
        XCTAssertEqual(fields["town"] as? String, "Northfield")
        let files = try XCTUnwrap(mine["files"] as? [String: [String: Any]])
        let file = try XCTUnwrap(files.values.first)
        XCTAssertEqual(file["name"] as? String, "evidence & notes.bin")
        XCTAssertEqual(file["received"] as? Int, 200_000)
        XCTAssertEqual(file["size"] as? Int, 200_000)
    }

    func testRealHTTPErrorShape() async throws {
        guard let raw = ProcessInfo.processInfo.environment["GSR_MOCK_DROP_URL"], let api = URL(string: raw) else {
            throw XCTSkip("Set GSR_MOCK_DROP_URL to run against ios/tools/mock_drop_server.py")
        }
        let client = DropClient(api: api, transport: URLSessionTransport())
        do {
            _ = try await client.start(form: "no-such-form")
            XCTFail("expected a refusal")
        } catch let e as DropError {
            XCTAssertEqual(e, .rejected(status: 400, code: "gsrdb_form", message: "Unknown form."))
        }
    }
}

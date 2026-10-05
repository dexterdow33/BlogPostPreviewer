import XCTest
@testable import GSRKit

final class CatalogTests: XCTestCase {
    func testBundledCatalogHasTheFourDropBoxes() throws {
        let c = DropCatalog.bundled
        XCTAssertEqual(c.api.absoluteString, "https://granitestatereport.com/wp-json/gsr-drop/v1/")
        XCTAssertEqual(c.forms.map(\.form), ["tips", "story", "inside", "nothing"])
        for f in c.forms {
            XCTAssertFalse(f.mainLabel.isEmpty, f.form)
            XCTAssertFalse(f.sendLabel.isEmpty, f.form)
            XCTAssertFalse(f.readFirst.isEmpty, f.form)
            XCTAssertTrue(f.pageURL.absoluteString.hasPrefix("https://granitestatereport.com/"), f.form)
        }
    }

    func testDefaultsMatchWhatThePageWouldSend() throws {
        let tips = try XCTUnwrap(DropCatalog.bundled.form("tips"))
        XCTAssertEqual(tips.defaultFields["identity"], .text("Do not use my name or anything that identifies me"))
        XCTAssertEqual(tips.defaultFields["where"], .text(""))
        let story = try XCTUnwrap(DropCatalog.bundled.form("story"))
        XCTAssertEqual(story.defaultFields["maycontact"], .flag(false))
        XCTAssertEqual(story.defaultFields["kind"], .text(""), "Skip this sends an empty string")
    }

    func testFieldValueJSONTypes() throws {
        let data = try JSONEncoder().encode(["a": FieldValue.text("x"), "b": .flag(true)])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"a\":\"x\""), text)
        XCTAssertTrue(text.contains("\"b\":true"), "checkboxes go as JSON booleans: \(text)")
    }

    func testHasContentFollowsThePageRule() throws {
        let story = try XCTUnwrap(DropCatalog.bundled.form("story"))
        var s = Submission(form: story)
        XCTAssertFalse(s.hasContent(in: story))
        s.fields["maycontact"] = .flag(true)
        s.fields["kind"] = .text("Something else")
        XCTAssertFalse(s.hasContent(in: story), "checkboxes and selects do not count")
        s.fields["town"] = .text("  ")
        XCTAssertFalse(s.hasContent(in: story))
        s.fields["town"] = .text("Concord")
        XCTAssertTrue(s.hasContent(in: story))
    }

    func testFieldsForSendingCoversEveryKey() throws {
        let story = try XCTUnwrap(DropCatalog.bundled.form("story"))
        var s = Submission(form: story)
        s.fields = [:]
        let out = s.fieldsForSending(in: story)
        XCTAssertEqual(Set(out.keys), Set(story.fields.map(\.key)))
        XCTAssertEqual(out["maycontact"], .flag(false))
        XCTAssertEqual(out["name"], .text(""))
    }
}

final class FormatTests: XCTestCase {
    func testHumanMatchesThePage() {
        XCTAssertEqual(ByteFormat.human(0), "0 bytes")
        XCTAssertEqual(ByteFormat.human(1023), "1023 bytes")
        XCTAssertEqual(ByteFormat.human(1536), "1.5 KB")
        XCTAssertEqual(ByteFormat.human(4_194_304), "4.0 MB")
        XCTAssertEqual(ByteFormat.human(2_147_483_648), "2.0 GB")
        XCTAssertEqual(ByteFormat.human(10_737_418_240), "10.0 GB")
    }

    func testHTMLText() {
        XCTAssertEqual(HTMLText.plain("<p>Working tools for New Hampshire&#8217;s Right-to-Know law&nbsp;&amp; more&hellip;</p>\n"),
                       "Working tools for New Hampshire\u{2019}s Right-to-Know law & more\u{2026}")
        XCTAssertEqual(HTMLText.plain("A &#x2014; B &bogus; C"), "A \u{2014} B &bogus; C")
        XCTAssertEqual(HTMLText.plain("Tom &amp; Jerry<br/>Part 2"), "Tom & Jerry Part 2")
    }

    func testCleanName() {
        XCTAssertEqual(OutboxStore.cleanName("../../etc/passwd"), "-..-etc-passwd")
        XCTAssertEqual(OutboxStore.cleanName("..hidden.pdf"), "hidden.pdf")
        XCTAssertEqual(OutboxStore.cleanName(""), "file")
        let long = String(repeating: "a", count: 300) + ".mov"
        XCTAssertEqual(OutboxStore.cleanName(long).count, 120)
        XCTAssertTrue(OutboxStore.cleanName(long).hasSuffix(".mov"))
    }

    func testStampedNameCarriesNoTime() {
        let name = FileNaming.stamped("photo", ext: "jpg")
        XCTAssertNotNil(name.range(of: #"^photo-[0-9a-f]{8}\.jpg$"#, options: .regularExpression), name)
        XCTAssertNotEqual(name, FileNaming.stamped("photo", ext: "jpg"))
    }

    func testMIME() {
        XCTAssertEqual(MIMEType.forExtension("HEIC"), "image/heic")
        XCTAssertEqual(MIMEType.forExtension("weird"), "")
        XCTAssertEqual(MIMEType.kind(mime: "video/quicktime", ext: "mov"), .video)
        XCTAssertEqual(MIMEType.kind(mime: "", ext: "pdf"), .document)
        XCTAssertEqual(MIMEType.kind(mime: "", ext: "zzz"), .other)
    }
}

final class FeedTests: XCTestCase {
    func testDecodesWordPressPosts() throws {
        let json = """
        [{"id":8938,"date_gmt":"2026-09-29T14:13:34","link":"https://granitestatereport.com/2026/09/29/gsr-tools/",
          "title":{"rendered":"GSR Tools"},"excerpt":{"rendered":"<p>Working tools for New Hampshire&#8217;s law.</p>\\n"},
          "jetpack_featured_media_url":"https://i0.wp.com/x.jpg"},
         {"id":2,"date_gmt":null,"link":"https://granitestatereport.com/b/","title":{"rendered":"B &amp; C"},
          "excerpt":{"rendered":""},"jetpack_featured_media_url":""}]
        """
        let stories = try FeedClient.decode(Data(json.utf8))
        XCTAssertEqual(stories.count, 2)
        XCTAssertEqual(stories[0].title, "GSR Tools")
        XCTAssertEqual(stories[0].excerpt, "Working tools for New Hampshire\u{2019}s law.")
        XCTAssertEqual(stories[0].published, FeedClient.parseGMT("2026-09-29T14:13:34"))
        XCTAssertEqual(stories[0].published.timeIntervalSince1970, 1_790_691_214)
        XCTAssertNil(stories[1].imageURL)
        XCTAssertEqual(stories[1].title, "B & C")
    }

    func testLatestURL() {
        let f = FeedClient(transport: MockDropServer())
        XCTAssertEqual(f.latestURL(count: 20).absoluteString,
                       "https://granitestatereport.com/wp-json/wp/v2/posts?per_page=20&_fields=id,date_gmt,link,title,excerpt,jetpack_featured_media_url")
    }
}

final class DropClientTests: XCTestCase {
    func testQueryEncodingIsStrict() {
        XCTAssertEqual(DropClient.encode("a+b/c=d&e f"), "a%2Bb%2Fc%3Dd%26e%20f")
        let c = DropClient(transport: MockDropServer())
        XCTAssertEqual(c.endpoint("chunk", query: [("token", "t+1"), ("file", "3"), ("offset", "0")]).absoluteString,
                       "https://granitestatereport.com/wp-json/gsr-drop/v1/chunk?token=t%2B1&file=3&offset=0")
    }

    func testStartSendsEmptyHoneypotAndReadsLimits() async throws {
        let server = MockDropServer()
        let c = DropClient(transport: server, userAgent: "GSR-iOS/test")
        let s = try await c.start(form: "tips")
        XCTAssertEqual(s.limits.chunk, 8)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: server.requests[0].body!) as? [String: Any])
        XCTAssertEqual(body["form"] as? String, "tips")
        XCTAssertEqual(body["website"] as? String, "")
        XCTAssertEqual(server.requests[0].headers["Content-Type"], "application/json")
        XCTAssertEqual(server.requests[0].headers["User-Agent"], "GSR-iOS/test")
    }

    func testErrorMapping() async throws {
        let server = MockDropServer()
        let c = DropClient(transport: server)
        do { _ = try await c.start(form: "nope"); XCTFail() } catch let e as DropError {
            XCTAssertEqual(e, .rejected(status: 400, code: "gsrdb_form", message: "Unknown form."))
            XCTAssertEqual(e.userMessage, "Unknown form.")
            XCTAssertFalse(e.isRetryable)
        }
        server.inject("start", .status(503, nil), .status(507, "Full."), .network)
        do { _ = try await c.start(form: "tips"); XCTFail() } catch let e as DropError {
            XCTAssertEqual(e, .serverBusy(status: 503, message: nil)); XCTAssertTrue(e.isRetryable)
            XCTAssertEqual(e.userMessage, "Server said 503")
        }
        do { _ = try await c.start(form: "tips"); XCTFail() } catch let e as DropError { XCTAssertEqual(e, .storageFull(message: "Full.")) }
        do { _ = try await c.start(form: "tips"); XCTFail() } catch let e as DropError {
            guard case .network = e else { return XCTFail("\(e)") }
            XCTAssertTrue(e.isRetryable)
        }
    }

    func testStringIDsRoundTrip() async throws {
        let server = MockDropServer()
        server.idsAsStrings = true
        let c = DropClient(transport: server)
        let s = try await c.start(form: "tips")
        let id = try await c.add(token: s.token, name: "a.txt", size: 3, type: "text/plain")
        XCTAssertEqual(id, .string("1"))
        let got = try await c.chunk(token: s.token, file: id, offset: 0, data: Data("abc".utf8))
        XCTAssertEqual(got, 3)
        try await c.remove(token: s.token, file: id)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: server.requests.last!.body!) as? [String: Any])
        XCTAssertEqual(body["file"] as? String, "1")
    }
}

final class UploaderTests: XCTestCase {
    var dir: URL!
    var store: OutboxStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gsr-tests-\(UUID().uuidString)")
        store = try OutboxStore(root: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func form(_ name: String = "tips") -> DropForm { DropCatalog.bundled.form(name)! }

    private func makeFile(_ name: String, _ bytes: Int) throws -> URL {
        let url = dir.appendingPathComponent("src-\(name)")
        var d = Data(count: bytes)
        for i in 0..<bytes { d[i] = UInt8(truncatingIfNeeded: i * 7 + name.count) }
        try d.write(to: url)
        return url
    }

    private func uploader(_ s: Submission, _ server: MockDropServer, preparer: ItemPreparer? = nil,
                          sleeper: InstantSleeper = InstantSleeper()) -> SubmissionUploader {
        SubmissionUploader(submission: s, form: form(s.form), store: store,
                           client: DropClient(transport: server), preparer: preparer, sleeper: sleeper)
    }

    func testSendsFilesInPiecesThenFinishes() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "The planning board minutes leave out the vote."
        s.fields["where"] = .text("Northfield")
        let a = try makeFile("a.pdf", 21)
        let b = try makeFile("b.jpg", 8)
        try store.addFile(to: &s, from: a, displayName: "a.pdf")
        try store.addFile(to: &s, from: b, displayName: "b.jpg")
        try store.addData(to: &s, Data(), fileName: "empty.txt")
        let up = uploader(s, server)
        let result = try await up.send()
        XCTAssertEqual(result, .sent(failedFiles: 0))
        let files = server.receivedFiles()
        XCTAssertEqual(files["a.pdf"], try Data(contentsOf: a))
        XCTAssertEqual(files["b.jpg"], try Data(contentsOf: b))
        XCTAssertEqual(files["empty.txt"], Data())
        XCTAssertEqual(server.count("chunk"), 3 + 1, "21 bytes in 8-byte pieces is 3; 8 bytes is 1; empty sends none")
        let fin = try XCTUnwrap(server.finishedSessions.first?.finished)
        XCTAssertEqual(fin.main, "The planning board minutes leave out the vote.")
        XCTAssertEqual(fin.fields["where"] as? String, "Northfield")
        XCTAssertEqual(fin.fields["identity"] as? String, "Do not use my name or anything that identifies me")
        let done = await up.submission
        XCTAssertEqual(done.phase, .sent)
        XCTAssertEqual(try store.load(s.id).phase, .sent, "saved to disk")
    }

    func testTextOnlySendStartsASessionAndFinishes() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form("story"))
        s.main = "Just words."
        s.fields["maycontact"] = .flag(true)
        _ = try await uploader(s, server).send()
        XCTAssertEqual(server.count("start"), 1)
        XCTAssertEqual(server.count("add"), 0)
        let fin = try XCTUnwrap(server.finishedSessions.first?.finished)
        XCTAssertEqual(fin.fields["maycontact"] as? Bool, true)
        XCTAssertEqual(server.finishedSessions.first?.form, "story")
    }

    func testEmptySubmissionIsRefusedLocally() async throws {
        let server = MockDropServer()
        let s = try store.create(form: form())
        do { _ = try await uploader(s, server).send(); XCTFail() } catch {}
        XCTAssertEqual(server.requests.count, 0)
    }

    func testRetriesDroppedConnectionsWithBackoff() async throws {
        let server = MockDropServer()
        server.inject("chunk", .network, .status(502, nil), .network)
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("a.bin", 20), displayName: "a.bin")
        let sleeper = InstantSleeper()
        _ = try await uploader(s, server, sleeper: sleeper).send()
        XCTAssertEqual(server.receivedFiles()["a.bin"]?.count, 20)
        XCTAssertEqual(sleeper.log.waits, [2, 4, 8])
    }

    func testResyncsOnWrongOffset() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("a.bin", 30), displayName: "a.bin")
        server.inject("chunk", .wrongOffset(0))
        _ = try await uploader(s, server).send()
        XCTAssertEqual(server.receivedFiles()["a.bin"]?.count, 30)
    }

    func testResumesAfterInterruptionFromSavedProgress() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        let src = try makeFile("big.mov", 40)
        try store.addFile(to: &s, from: src, displayName: "big.mov")
        // First attempt: the third piece never gets an answer and the app gives up.
        server.inject("chunk", .status(200, nil)) // placeholder consumed below
        server.faults["chunk"] = []
        let sleeper = InstantSleeper()
        let first = SubmissionUploader(submission: s, form: form(), store: store, client: DropClient(transport: server),
                                       sleeper: sleeper, maxTries: 0)
        server.inject("chunk", .status(200, nil)) // a 200 with no "received" is unreadable
        do { _ = try await first.send(); XCTFail("should not finish") } catch {}
        var saved = try store.load(s.id)
        XCTAssertEqual(saved.phase, .draft)
        XCTAssertNotNil(saved.token)
        // Now the app is relaunched and the send resumes from the saved state.
        saved = try store.load(s.id)
        let item = try XCTUnwrap(saved.items.first)
        XCTAssertEqual(item.state, .failed, "a piece the server answered with nonsense fails the file")
        let second = SubmissionUploader(submission: saved, form: form(), store: store, client: DropClient(transport: server), sleeper: sleeper)
        await second.retry(itemID: item.id)
        _ = try await second.send()
        XCTAssertEqual(server.receivedFiles()["big.mov"], try Data(contentsOf: src))
        XCTAssertEqual(server.count("start"), 1, "the saved session is reused")
        XCTAssertEqual(server.count("add"), 1, "the saved file id is reused")
    }

    func testCancelledSendResumesWhereItStopped() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        let src = try makeFile("v.mov", 64)
        try store.addFile(to: &s, from: src, displayName: "v.mov")
        let up = uploader(s, server)
        let task = Task { try await up.send() }
        // Let a few pieces go, then cancel.
        while server.count("chunk") < 3 { try await Task.sleep(nanoseconds: 1_000_000) }
        task.cancel()
        _ = try? await task.value
        let paused = await up.submission
        XCTAssertEqual(paused.phase, .draft)
        let sentBefore = paused.items[0].sent
        XCTAssertGreaterThan(sentBefore, 0)
        _ = try await up.send()
        XCTAssertEqual(server.receivedFiles()["v.mov"], try Data(contentsOf: src))
        XCTAssertLessThanOrEqual(server.count("chunk"), 64 / 8 + 2, "did not start over")
    }

    func testExpiredSessionStartsOverAndStillDelivers() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("a.bin", 24), displayName: "a.bin")
        s.main = "note"
        server.inject("finish", .expire)
        _ = try await uploader(s, server).send()
        XCTAssertEqual(server.count("start"), 2)
        XCTAssertEqual(server.finishedSessions.count, 1)
        XCTAssertEqual(server.receivedFiles()["a.bin"]?.count, 24)
    }

    func testGivesUpAfterRepeatedExpiry() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "note"
        server.inject("finish", .expire, .expire, .expire)
        do { _ = try await uploader(s, server).send(); XCTFail() } catch let e as DropError {
            guard case .sessionExpired = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(try store.load(s.id).phase, .draft)
        XCTAssertNotNil(try store.load(s.id).lastError)
    }

    func testLimitsRefuseFilesLikeThePage() async throws {
        let server = MockDropServer()
        server.limits = DropLimits(chunk: 8, maxFile: 10, maxFiles: 2, maxTotal: 15)
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("1", 9), displayName: "one")
        try store.addFile(to: &s, from: try makeFile("2", 11), displayName: "too-big")
        try store.addFile(to: &s, from: try makeFile("3", 7), displayName: "over-total")
        try store.addFile(to: &s, from: try makeFile("4", 5), displayName: "two")
        try store.addFile(to: &s, from: try makeFile("5", 1), displayName: "over-count")
        let up = uploader(s, server)
        let r = try await up.send()
        XCTAssertEqual(r, .sent(failedFiles: 3))
        let items = await up.submission.items
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.displayName, $0) })
        XCTAssertEqual(byName["one"]?.state, .done)
        XCTAssertEqual(byName["two"]?.state, .done)
        XCTAssertEqual(byName["too-big"]?.error, "Larger than 10 bytes. Use a share link or mail it on a drive.")
        XCTAssertEqual(byName["over-total"]?.error, "Would put this send over 15 bytes. Send these first.")
        XCTAssertEqual(byName["over-count"]?.error, "Over the 2-file limit for one send. Send these, then the rest.")
        XCTAssertEqual(Set(server.receivedFiles().keys), ["one", "two"])
    }

    func testStorageFullStopsTheSend() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("a", 9), displayName: "a")
        server.inject("chunk", .status(507, "The drop box is full."))
        do { _ = try await uploader(s, server).send(); XCTFail() } catch let e as DropError {
            XCTAssertEqual(e, .storageFull(message: "The drop box is full."))
        }
        XCTAssertEqual(try store.load(s.id).lastError, "The drop box is full.")
        XCTAssertEqual(server.count("finish"), 0)
    }

    func testRemovingADraftFileDeletesIt() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        let item = try store.addFile(to: &s, from: try makeFile("a", 9), displayName: "a")
        let path = store.originalURL(s, item).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let up = uploader(s, server)
        await up.remove(itemID: item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let items = await up.submission.items
        XCTAssertTrue(items.isEmpty)
    }

    struct Cleaner: ItemPreparer {
        let fail: Bool
        func prepare(_ item: SubmissionItem, source: URL, folder: URL) async throws -> PreparedFile {
            if fail { throw CocoaError(.fileReadCorruptFile) }
            let name = "clean-" + item.storedName
            try Data("CLEAN".utf8).write(to: folder.appendingPathComponent(name))
            return PreparedFile(name: name, contentType: "image/jpeg", displayName: item.displayName)
        }
    }

    func testPhotosAreCleanedBeforeUpload() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("p.jpg", 30), displayName: "p.jpg")
        try store.addFile(to: &s, from: try makeFile("d.pdf", 5), displayName: "d.pdf")
        let up = uploader(s, server, preparer: Cleaner(fail: false))
        _ = try await up.send()
        XCTAssertEqual(server.receivedFiles()["p.jpg"], Data("CLEAN".utf8), "the cleaned copy uploads")
        XCTAssertEqual(server.receivedFiles()["d.pdf"]?.count, 5, "documents are untouched")
        let item = await up.submission.items.first { $0.displayName == "p.jpg" }
        XCTAssertEqual(item?.cleaned, true)
    }

    func testAPhotoThatCannotBeCleanedIsHeldBack() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        let src = try makeFile("p.jpg", 30)
        let item = try store.addFile(to: &s, from: src, displayName: "p.jpg")
        s.main = "note"
        try store.save(s)
        let up = uploader(s, server, preparer: Cleaner(fail: true))
        do { _ = try await up.send(); XCTFail("must stop for the sender's decision") } catch let e as DropError {
            guard case .rejected(_, "uncleaned", _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(server.count("finish"), 0, "not closed without the sender's say")
        XCTAssertEqual(server.count("add"), 0, "never sent with its location")
        let held = await up.submission.items[0]
        XCTAssertTrue(held.cleaningFailed)
        XCTAssertEqual(held.state, .failed)
        // The sender chooses to send it as it is.
        await up.sendWithoutCleaning(itemID: item.id)
        _ = try await up.send()
        XCTAssertEqual(server.receivedFiles()["p.jpg"], try Data(contentsOf: src))
        XCTAssertEqual(server.count("start"), 1, "the same session carries on")
    }

    func testScrubOffSendsOriginals() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form(), scrubMedia: false)
        let src = try makeFile("p.jpg", 12)
        try store.addFile(to: &s, from: src, displayName: "p.jpg")
        _ = try await uploader(s, server, preparer: Cleaner(fail: false)).send()
        XCTAssertEqual(server.receivedFiles()["p.jpg"], try Data(contentsOf: src))
    }

    func testOutboxListsOnlyUnsentWithContent() throws {
        var a = try store.create(form: form())
        a.main = "words"
        try store.save(a)
        _ = try store.create(form: form()) // empty
        var c = try store.create(form: form())
        c.main = "sent"
        c.phase = .sent
        try store.save(c)
        XCTAssertEqual(store.unsent().map(\.id), [a.id])
        store.delete(a.id)
        XCTAssertTrue(store.unsent().isEmpty)
        store.wipe()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testUpdatesStreamReportsProgress() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("a", 32), displayName: "a")
        let up = uploader(s, server)
        let stream = await up.updates()
        let collector = Task { () -> [Int] in
            var seen: [Int] = []
            for await snap in stream {
                seen.append(snap.percent)
                if snap.phase == .sent { break }
            }
            return seen
        }
        _ = try await up.send()
        let seen = await collector.value
        XCTAssertEqual(seen.last, 100)
        XCTAssertEqual(seen, seen.sorted(), "progress never goes backwards")
    }

    // MARK: Fixes from review, one test each

    /// Runs `body` inside the preparer, so a test can act while a send is cleaning a file.
    final class HookPreparer: ItemPreparer, @unchecked Sendable {
        var body: (@Sendable (SubmissionItem) async throws -> Void)?
        func prepare(_ item: SubmissionItem, source: URL, folder: URL) async throws -> PreparedFile {
            try await body?(item)
            let name = "clean-" + item.storedName
            try Data("CLEAN".utf8).write(to: folder.appendingPathComponent(name))
            return PreparedFile(name: name)
        }
    }

    func testASentSubmissionIsNeverWrittenBack() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "a note with my contact details"
        s.fields["contact"] = .text("me@example.org")
        try store.save(s)
        let up = uploader(s, server)
        _ = try await up.send()
        store.delete(s.id)
        // What closing the screen used to do.
        await up.update(main: "a note with my contact details", fields: s.fields, scrubMedia: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(s.id).path), "deleted means deleted")
        XCTAssertTrue(store.all().isEmpty)
    }

    func testADeletedDraftIsNeverWrittenBack() async throws {
        var s = try store.create(form: form())
        s.main = "draft"
        try store.save(s)
        let up = uploader(s, MockDropServer())
        store.delete(s.id)
        await up.update(main: "draft, edited", fields: s.fields, scrubMedia: true)
        XCTAssertTrue(store.all().isEmpty)
        do { _ = try await up.addData(Data("x".utf8), fileName: "late.txt"); XCTFail("no folder to add to") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(s.id).path))
    }

    func testRemovingAFileWhileItIsBeingCleanedKeepsItOut() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "note"
        let item = try store.addFile(to: &s, from: try makeFile("p.jpg", 30), displayName: "p.jpg")
        try store.save(s)
        let prep = HookPreparer()
        let up = uploader(s, server, preparer: prep)
        prep.body = { _ in await up.remove(itemID: item.id) }
        let r = try await up.send()
        XCTAssertEqual(r, .sent(failedFiles: 0))
        XCTAssertNil(server.receivedFiles()["p.jpg"], "the × wins")
        let state = await up.submission.items.first?.state
        XCTAssertEqual(state, .removed)
    }

    func testRemovingAFileMidUploadKeepsItOutAndTellsTheBox() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "note"
        let item = try store.addFile(to: &s, from: try makeFile("v.mov", 64), displayName: "v.mov")
        try store.save(s)
        let up = uploader(s, server)
        let count = Counter()
        server.onRequest = { req in
            if req.url.lastPathComponent == "chunk", count.next() == 2 { await up.remove(itemID: item.id) }
        }
        let r = try await up.send()
        XCTAssertEqual(r, .sent(failedFiles: 0))
        XCTAssertTrue(server.receivedFiles().isEmpty, "a removed file does not go with finish")
        XCTAssertGreaterThanOrEqual(server.count("remove"), 1)
        XCTAssertLessThan(server.count("chunk"), 64 / 8)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> Int { lock.withLock { n += 1; return n } }
    }

    func testFilesAddedDuringASendGoToo() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("p.jpg", 20), displayName: "p.jpg")
        try store.save(s)
        let prep = HookPreparer()
        let up = uploader(s, server, preparer: prep)
        let late = try makeFile("late.pdf", 12)
        prep.body = { item in
            if item.displayName == "p.jpg" { _ = try await up.addFile(from: late, displayName: "late.pdf") }
        }
        let r = try await up.send()
        XCTAssertEqual(r, .sent(failedFiles: 0))
        XCTAssertEqual(server.receivedFiles()["late.pdf"], try Data(contentsOf: late))
        XCTAssertEqual(server.finishedSessions.count, 1)
    }

    func testALostFinishAnswerIsNotSentTwice() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "only once, please"
        try store.save(s)
        server.inject("finish", .answerLost)
        do { _ = try await uploader(s, server).send(); XCTFail("the app cannot know it arrived") } catch let e as DropError {
            guard case .rejected(410, "maybe-sent", _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(server.finishedSessions.count, 1, "the editor has it once")
        XCTAssertEqual(server.count("start"), 1, "no second session behind the sender's back")
    }

    func testAPausedFinishIsNotRepeatedBlind() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "note"
        // finish went out and was processed, but the app was closed before the answer.
        s.token = nil
        try store.save(s)
        let first = uploader(s, server)
        server.inject("finish", .answerLost)
        let sleeper = InstantSleeper()
        let killed = SubmissionUploader(submission: s, form: form(), store: store, client: DropClient(transport: server),
                                        sleeper: sleeper, maxTries: 0)
        _ = first
        do { _ = try await killed.send() } catch {}
        // The next launch resumes from what was saved.
        let saved = try store.load(s.id)
        let again = SubmissionUploader(submission: saved, form: form(), store: store, client: DropClient(transport: server), sleeper: sleeper)
        do { _ = try await again.send(); XCTFail() } catch let e as DropError {
            guard case .rejected(410, "maybe-sent", _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(server.finishedSessions.count, 1)
    }

    func testAConnectionGiveUpStopsTheSendAndKeepsTheFile() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "note"
        let src = try makeFile("a.bin", 16)
        try store.addFile(to: &s, from: src, displayName: "a.bin")
        try store.save(s)
        server.inject("chunk", .network, .network, .network)
        let up = SubmissionUploader(submission: s, form: form(), store: store, client: DropClient(transport: server),
                                    sleeper: InstantSleeper(), maxTries: 2)
        do { _ = try await up.send(); XCTFail("must not finish without the file") } catch let e as DropError {
            guard case .network = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(server.count("finish"), 0)
        let item = await up.submission.items[0]
        XCTAssertEqual(item.state, .queued, "ready for the next press")
        _ = try await up.send()
        XCTAssertEqual(server.receivedFiles()["a.bin"], try Data(contentsOf: src))
    }

    func testEveryFileRefusedAndNoNoteSendsNothing() async throws {
        let server = MockDropServer()
        server.limits = DropLimits(chunk: 8, maxFile: 4, maxFiles: 50, maxTotal: 100)
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("big", 9), displayName: "big")
        try store.save(s)
        do { _ = try await uploader(s, server).send(); XCTFail() } catch let e as DropError {
            guard case .rejected(_, "nothing-left", _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(server.count("finish"), 0, "no empty message")
        XCTAssertEqual(store.unsent().count, 1, "the refused file is still offered on the phone")
    }

    func testRefusedFilesMoveToANewDraftAfterTheSend() async throws {
        let server = MockDropServer()
        server.limits = DropLimits(chunk: 8, maxFile: 10, maxFiles: 50, maxTotal: 100)
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("ok", 9), displayName: "ok.pdf")
        let bigSrc = try makeFile("big", 12)
        try store.addFile(to: &s, from: bigSrc, displayName: "big.mov")
        try store.save(s)
        let up = uploader(s, server)
        let r = try await up.send()
        XCTAssertEqual(r, .sent(failedFiles: 1))
        let sent = await up.submission
        let next = try XCTUnwrap(store.finishSent(sent, form: form()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(s.id).path), "the sent one is gone")
        XCTAssertEqual(next.items.map(\.displayName), ["big.mov"])
        XCTAssertEqual(next.items.first?.state, .queued)
        XCTAssertEqual(try Data(contentsOf: store.originalURL(next, next.items[0])), try Data(contentsOf: bigSrc))
        XCTAssertEqual(store.unsent().map(\.id), [next.id])
    }

    func testAPauseWhileCleaningIsNotACleaningFailure() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        try store.addFile(to: &s, from: try makeFile("v.mov", 20), displayName: "v.mov")
        try store.save(s)
        let prep = HookPreparer()
        // Media code that wraps cancellation in its own error, as AVFoundation does.
        prep.body = { _ in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { throw CocoaError(.userCancelled) }
        }
        let up = uploader(s, server, preparer: prep)
        let task = Task { try await up.send() }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        _ = try? await task.value
        let item = await up.submission.items[0]
        XCTAssertFalse(item.cleaningFailed)
        XCTAssertEqual(item.state, .queued)
    }

    func testTurningCleaningOnDropsAPartlyUploadedOriginal() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form(), scrubMedia: false)
        s.main = "note"
        try store.addFile(to: &s, from: try makeFile("p.jpg", 64), displayName: "p.jpg")
        try store.save(s)
        let up = uploader(s, server, preparer: Cleaner(fail: false))
        let task = Task { try await up.send() }
        while server.count("chunk") < 2 { try await Task.sleep(nanoseconds: 1_000_000) }
        task.cancel()
        _ = try? await task.value
        await up.update(main: "note", fields: s.fields, scrubMedia: true)
        _ = try await up.send()
        XCTAssertEqual(server.receivedFiles()["p.jpg"], Data("CLEAN".utf8), "the clean copy went, not the original")
        XCTAssertGreaterThanOrEqual(server.count("remove"), 1, "the partial original was dropped")
    }

    func testSwitchingFormsBeforeAnythingGoes() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form("tips"))
        s.main = "note"
        try store.save(s)
        let up = uploader(s, server)
        let ok = await up.switchForm(to: form("nothing"))
        XCTAssertTrue(ok)
        XCTAssertEqual(try store.load(s.id).form, "nothing")
        XCTAssertEqual(try store.load(s.id).fields["how"], .text(""))
        _ = try await up.send()
        XCTAssertEqual(server.finishedSessions.first?.form, "nothing")
        let late = await up.switchForm(to: form("story"))
        XCTAssertFalse(late, "too late once sent")
    }

    func testStaleStatesFromAClosedAppAreCleared() async throws {
        let server = MockDropServer()
        var s = try store.create(form: form())
        s.main = "note"
        try store.addFile(to: &s, from: try makeFile("a.bin", 10), displayName: "a.bin")
        s.items[0].state = .preparing
        s.phase = .sending
        try store.save(s)
        let r = try await uploader(try store.load(s.id), server).send()
        XCTAssertEqual(r, .sent(failedFiles: 0))
        XCTAssertEqual(server.receivedFiles()["a.bin"]?.count, 10)
    }

    func testOriginalNameSurvivesCleaningRename() throws {
        let item = SubmissionItem(displayName: "IMG_1.jpg", storedName: "ABCDEF12-IMG_1.HEIC", contentType: "image/jpeg", kind: .photo, size: 1)
        XCTAssertEqual(item.originalName, "IMG_1.HEIC")
    }
}

extension Submission {
    func with(_ change: (inout Submission) -> Void) -> Submission {
        var c = self
        change(&c)
        return c
    }
}

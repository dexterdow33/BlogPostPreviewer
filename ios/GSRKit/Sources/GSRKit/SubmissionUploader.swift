import Foundation

/// Gets a file ready to upload. The app uses it to remove location and device details
/// from photos and videos; GSRKit itself never changes a file.
public protocol ItemPreparer: Sendable {
    /// Writes a cleaned copy of `source` into `folder`. Throw to stop this file from
    /// uploading (the sender then decides what to do).
    func prepare(_ item: SubmissionItem, source: URL, folder: URL) async throws -> PreparedFile
}

/// A cleaned copy, and what changed if the format had to change (HEIC re-encoded as JPEG).
public struct PreparedFile: Hashable, Sendable {
    /// File name inside the submission folder.
    public var name: String
    /// New MIME type, when the format changed.
    public var contentType: String?
    /// New name for the editor, when the extension changed.
    public var displayName: String?

    public init(name: String, contentType: String? = nil, displayName: String? = nil) {
        self.name = name
        self.contentType = contentType
        self.displayName = displayName
    }
}

/// Waits. Tests swap in one that does not.
public protocol Sleeper: Sendable {
    func sleep(seconds: Double) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}
    public func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Sends one submission to the drop box the way the site's page does: a session from
/// `start`, each file registered with `add` and sent in pieces with `chunk` (two files at
/// a time), then `finish` with the note and fields.
///
/// Differences from the page, all in the sender's favor:
/// - Nothing uploads until Send is pressed.
/// - Progress is saved after every piece, so a send interrupted by a closed app or a
///   dead battery picks up where it stopped (the server's 409 reply resyncs the offset).
/// - If the session expires (410), it starts a new one and uploads the files again
///   instead of losing them.
public actor SubmissionUploader {
    public nonisolated let id: UUID
    public private(set) var submission: Submission
    private let form: DropForm
    private let store: OutboxStore
    private let client: DropClient
    private let preparer: ItemPreparer?
    private let sleeper: Sleeper
    private let maxConcurrent: Int
    private let maxTries: Int
    private let maxSessionRestarts: Int
    private var observers: [UUID: AsyncStream<Submission>.Continuation] = [:]
    private var sending = false

    public init(submission: Submission, form: DropForm, store: OutboxStore, client: DropClient = DropClient(),
                preparer: ItemPreparer? = nil, sleeper: Sleeper = TaskSleeper(),
                maxConcurrent: Int = 2, maxTries: Int = 8, maxSessionRestarts: Int = 2) {
        self.id = submission.id
        self.submission = submission
        self.form = form
        self.store = store
        self.client = client
        self.preparer = preparer
        self.sleeper = sleeper
        self.maxConcurrent = max(1, maxConcurrent)
        self.maxTries = maxTries
        self.maxSessionRestarts = maxSessionRestarts
    }

    // MARK: Observing

    /// The submission after every change, starting with its current state.
    public func updates() -> AsyncStream<Submission> {
        let key = UUID()
        let (stream, cont) = AsyncStream<Submission>.makeStream(bufferingPolicy: .bufferingNewest(1))
        cont.yield(submission)
        observers[key] = cont
        cont.onTermination = { [weak self] _ in
            Task { await self?.dropObserver(key) }
        }
        return stream
    }

    private func dropObserver(_ key: UUID) {
        observers[key] = nil
    }

    private func publish(save: Bool = true) {
        if save { try? store.save(submission) }
        for c in observers.values { c.yield(submission) }
    }

    // MARK: Editing while not sending

    /// Replaces the note, fields, and cleaning choice. Ignored while a send is running.
    public func update(main: String, fields: [String: FieldValue], scrubMedia: Bool) {
        guard !sending else { return }
        submission.main = main
        submission.fields = fields
        submission.scrubMedia = scrubMedia
        publish()
    }

    /// Copies (or moves) a file into the submission. Allowed during a send too: it
    /// uploads with the next send, as on the page.
    @discardableResult
    public func addFile(from source: URL, displayName: String? = nil, contentType: String? = nil,
                        kind: SubmissionItem.Kind? = nil, move: Bool = false) throws -> SubmissionItem {
        let item = try store.addFile(to: &submission, from: source, displayName: displayName,
                                     contentType: contentType, kind: kind, move: move)
        publish(save: false)
        return item
    }

    /// Adds bytes as a file (a camera photo, a pasted image).
    @discardableResult
    public func addData(_ data: Data, fileName: String, contentType: String? = nil,
                        kind: SubmissionItem.Kind? = nil) throws -> SubmissionItem {
        let item = try store.addData(to: &submission, data, fileName: fileName, contentType: contentType, kind: kind)
        publish(save: false)
        return item
    }

    /// Takes a file out. Before a send it is deleted from the phone; during one it stops
    /// uploading and the drop box is told to drop it, as the page's × button does.
    public func remove(itemID: UUID) {
        guard let i = submission.items.firstIndex(where: { $0.id == itemID }) else { return }
        let item = submission.items[i]
        if item.serverID == nil && !sending {
            try? store.removeItem(itemID, from: &submission)
            publish(save: false)
            return
        }
        submission.items[i].state = .removed
        publish()
        if let token = submission.token, let fid = item.serverID {
            let client = self.client
            Task { try? await client.remove(token: token, file: fid) }
        }
    }

    /// Puts a file that gave up back in line. It uploads on the next send.
    public func retry(itemID: UUID) {
        guard let i = submission.items.firstIndex(where: { $0.id == itemID }),
              submission.items[i].state == .failed else { return }
        submission.items[i].state = .queued
        submission.items[i].error = nil
        publish()
    }

    /// Lets a file that could not be cleaned upload as it is. The sender has to ask.
    public func sendWithoutCleaning(itemID: UUID) {
        guard let i = submission.items.firstIndex(where: { $0.id == itemID }) else { return }
        submission.items[i].preparedName = nil
        submission.items[i].cleaned = false
        submission.items[i].cleaningFailed = false
        submission.items[i].error = nil
        submission.items[i].state = .queued
        submission.items[i].size = OutboxStore.size(of: store.originalURL(submission, submission.items[i]))
        submission.items[i].sendAsIs = true
        publish()
    }

    // MARK: Sending

    public enum SendResult: Equatable, Sendable {
        /// The drop box confirmed it. `failedFiles` did not go (each item says why).
        case sent(failedFiles: Int)
    }

    /// Uploads every file and sends the note. Returns once the drop box confirms.
    /// Throws (and leaves the submission resumable) when the send cannot finish:
    /// offline, the box is full, or the server refused the note. Cancel the calling task
    /// to pause; call again to resume.
    public func send() async throws -> SendResult {
        guard !sending else { throw DropError.rejected(status: 0, code: "busy", message: "Already sending.") }
        if submission.phase == .sent {
            return .sent(failedFiles: submission.items.filter { $0.state == .failed }.count)
        }
        guard submission.hasContent(in: form) else {
            throw DropError.rejected(status: 0, code: "empty", message: "Add a file or a few words first.")
        }
        sending = true
        defer { sending = false }
        submission.phase = .sending
        submission.lastError = nil
        publish()

        var restarts = 0
        while true {
            do {
                try await uploadAll()
                if submission.items.contains(where: { $0.cleaningFailed && $0.state == .failed }) {
                    // Do not close the submission without the sender's say on these files.
                    throw DropError.rejected(status: 0, code: "uncleaned",
                                             message: "A photo or video could not be cleaned. Remove it or choose Send as is, then press Send again.")
                }
                submission.phase = .finishing
                publish()
                let token = try await sessionToken()
                let client = self.client
                let main = submission.main
                let fields = submission.fieldsForSending(in: form)
                try await withRetries {
                    try await client.finish(token: token, main: main, fields: fields)
                }
                submission.phase = .sent
                submission.sentAt = Date()
                publish()
                return .sent(failedFiles: submission.items.filter { $0.state == .failed }.count)
            } catch DropError.sessionExpired {
                restarts += 1
                guard restarts <= maxSessionRestarts else {
                    return try fail(DropError.sessionExpired(message: "The drop box kept closing the upload. Try again in a few minutes."))
                }
                submission.token = nil
                submission.limits = nil
                for i in submission.items.indices { submission.items[i].resetForNewSession() }
                publish()
                continue
            } catch is CancellationError {
                submission.phase = .draft
                submission.lastError = nil
                for i in submission.items.indices where [.uploading, .retrying, .preparing].contains(submission.items[i].state) {
                    submission.items[i].state = .queued
                }
                publish()
                throw CancellationError()
            } catch {
                return try fail(error)
            }
        }
    }

    private func fail(_ error: Error) throws -> SendResult {
        submission.phase = .draft
        submission.lastError = (error as? DropError)?.userMessage ?? "Could not send. Check your connection and press the button again."
        for i in submission.items.indices where [.uploading, .retrying, .preparing].contains(submission.items[i].state) {
            submission.items[i].state = .queued
        }
        publish()
        throw error
    }

    private func sessionToken() async throws -> String {
        if let t = submission.token { return t }
        let form = self.form.form
        let client = self.client
        let s = try await withRetries { try await client.start(form: form) }
        submission.token = s.token
        submission.limits = s.limits
        publish()
        return s.token
    }

    /// Applies the server's limits the way the page does, in the order files were added:
    /// over the file count, over the per-file size, or over the total, and that file is
    /// refused with a reason.
    private func applyLimits(_ limits: DropLimits) {
        var count = 0
        var total: Int64 = 0
        for i in submission.items.indices {
            let it = submission.items[i]
            guard it.state != .removed, it.state != .failed else { continue }
            if count >= limits.maxFiles {
                refuse(i, "Over the \(limits.maxFiles)-file limit for one send. Send these, then the rest.")
            } else if it.size > limits.maxFile {
                refuse(i, "Larger than \(ByteFormat.human(limits.maxFile)). Use a share link or mail it on a drive.")
            } else if total + it.size > limits.maxTotal {
                refuse(i, "Would put this send over \(ByteFormat.human(limits.maxTotal)). Send these first.")
            } else {
                count += 1
                total += it.size
            }
        }
    }

    private func refuse(_ index: Int, _ why: String) {
        submission.items[index].state = .failed
        submission.items[index].error = why
    }

    private func uploadAll() async throws {
        // Clean first, so the limits apply to the bytes that will actually upload.
        try await prepareAll()
        let pending = submission.items.filter { $0.state != .removed && $0.state != .failed && $0.state != .done }
        guard !pending.isEmpty else { return }
        let token = try await sessionToken()
        applyLimits(submission.limits ?? .pageDefaults)
        publish()
        let ids = submission.items.filter { $0.state == .queued || $0.state == .uploading || $0.state == .retrying }.map(\.id)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func launch() {
                guard next < ids.count else { return }
                let id = ids[next]
                next += 1
                group.addTask { try await self.upload(itemID: id, token: token) }
            }
            for _ in 0..<min(maxConcurrent, ids.count) { launch() }
            while try await group.next() != nil { launch() }
        }
    }

    private func prepareAll() async throws {
        guard submission.scrubMedia, let preparer else { return }
        for item in submission.items where item.canBeCleaned && !item.cleaned && item.preparedName == nil
            && item.state != .removed && item.state != .failed && item.state != .done
            && item.serverID == nil && !item.sendAsIs {
            try Task.checkCancellation()
            setItem(item.id) { $0.state = .preparing; $0.error = nil }
            publish(save: false)
            do {
                let source = store.originalURL(submission, item)
                let p = try await preparer.prepare(item, source: source, folder: store.folder(submission.id))
                let size = OutboxStore.size(of: store.folder(submission.id).appendingPathComponent(p.name))
                setItem(item.id) {
                    $0.preparedName = p.name
                    $0.cleaned = true
                    $0.size = size
                    $0.state = .queued
                    if let t = p.contentType { $0.contentType = t }
                    if let n = p.displayName { $0.displayName = n }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Never send a file with its location when the sender asked for it gone.
                setItem(item.id) {
                    $0.state = .failed
                    $0.cleaningFailed = true
                    $0.error = "Could not remove the location and device details from this file, so it was held back. Remove it, or choose Send as is."
                }
            }
            publish()
        }
    }

    private func upload(itemID: UUID, token: String) async throws {
        guard let start = item(itemID), start.state != .removed, start.state != .failed, start.state != .done else { return }
        let limits = submission.limits ?? .pageDefaults

        // Register the file.
        var fileID: DropFileID
        if let existing = start.serverID {
            fileID = existing
        } else {
            setItem(itemID) { $0.state = .uploading }
            publish(save: false)
            do {
                let cur = item(itemID) ?? start
                let client = self.client
                fileID = try await withRetries {
                    try await client.add(token: token, name: cur.displayName, size: cur.size, type: cur.contentType)
                }
            } catch let e as DropError where !isSessionExpired(e) {
                if case .storageFull = e { throw e }
                setItem(itemID) { $0.state = .failed; $0.error = e.userMessage }
                publish()
                return
            }
            if item(itemID)?.state == .removed {
                let client = self.client
                Task { try? await client.remove(token: token, file: fileID) }
                return
            }
            setItem(itemID) { $0.serverID = fileID; $0.sent = 0 }
            publish()
        }

        // Send the pieces.
        let url = store.uploadURL(submission, item(itemID) ?? start)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            setItem(itemID) { $0.state = .failed; $0.error = "The app's copy of this file is missing. Remove it and add it again." }
            publish()
            return
        }
        defer { try? handle.close() }

        var tries = 0
        while true {
            try Task.checkCancellation()
            guard let cur = item(itemID), cur.state != .removed else { return }
            if cur.size == 0 || cur.sent >= cur.size { break }
            let end = min(cur.size, cur.sent + Int64(limits.chunk))
            let data: Data
            do {
                try handle.seek(toOffset: UInt64(cur.sent))
                data = try handle.read(upToCount: Int(end - cur.sent)) ?? Data()
            } catch {
                setItem(itemID) { $0.state = .failed; $0.error = "Could not read this file on the phone." }
                publish()
                return
            }
            if data.isEmpty {
                setItem(itemID) { $0.state = .failed; $0.error = "This file got shorter while it was uploading. Remove it and add it again." }
                publish()
                return
            }
            do {
                let received = try await client.chunk(token: token, file: fileID, offset: cur.sent, data: data)

                if received <= cur.sent {
                    // The server took the bytes but did not move forward. Count it as a failed try.
                    throw DropError.serverBusy(status: 200, message: nil)
                }
                tries = 0
                setItem(itemID) { $0.sent = min(received, $0.size); $0.state = .uploading; $0.error = nil }
                publish()
            } catch DropError.offsetMismatch(let received) {
                tries += 1
                if tries > maxTries {
                    setItem(itemID) { $0.state = .failed; $0.error = "The upload kept losing its place. Try again." }
                    publish()
                    return
                }
                setItem(itemID) { $0.sent = max(0, min(received, $0.size)) }
                publish()
            } catch let e as DropError where e.isRetryable {
                tries += 1
                if tries > maxTries {
                    setItem(itemID) { $0.state = .failed; $0.error = "The connection kept dropping. Try again, or use a share link." }
                    publish()
                    return
                }
                setItem(itemID) { $0.state = .retrying }
                publish(save: false)
                try await sleeper.sleep(seconds: min(30, pow(2, Double(tries))))
            } catch let e as DropError {
                if isSessionExpired(e) { throw e }
                if case .storageFull = e { throw e }
                setItem(itemID) { $0.state = .failed; $0.error = e.userMessage }
                publish()
                return
            }
        }
        setItem(itemID) { $0.state = .done; $0.sent = $0.size; $0.error = nil }
        publish()
    }

    private func isSessionExpired(_ e: DropError) -> Bool {
        if case .sessionExpired = e { return true }
        return false
    }

    /// Retries network drops and busy servers with the page's backoff (2, 4, 8 … 30 s).
    private func withRetries<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        var tries = 0
        while true {
            do {
                return try await op()
            } catch let e as DropError where e.isRetryable {
                tries += 1
                if tries > maxTries { throw e }
                try await sleeper.sleep(seconds: min(30, pow(2, Double(tries))))
            }
        }
    }

    private func item(_ id: UUID) -> SubmissionItem? {
        submission.items.first { $0.id == id }
    }

    private func setItem(_ id: UUID, _ change: (inout SubmissionItem) -> Void) {
        guard let i = submission.items.firstIndex(where: { $0.id == id }) else { return }
        change(&submission.items[i])
    }
}

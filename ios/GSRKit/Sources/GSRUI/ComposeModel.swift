#if os(iOS)
import Foundation
import GSRKit
import GSRMedia
import SwiftUI
import UniformTypeIdentifiers

/// Lets the app keep a send alive when the sender leaves it (a background task, and on
/// iOS 26 a continued-processing task with progress on the Lock Screen). The share
/// extension passes none: its sheet stays open while it sends.
@MainActor
public protocol SendActivity: AnyObject {
    /// A send started. Call `stop` if the system takes the time back (the sender can stop
    /// an iOS 26 background send from its progress view); the send pauses and resumes later.
    func sendBegan(title: String, stop: @escaping () -> Void)
    func sendProgressed(_ fraction: Double)
    func sendEnded(success: Bool)
}

/// One open submission on screen. Owns the uploader and mirrors its state for SwiftUI.
@MainActor
public final class ComposeModel: ObservableObject, Identifiable {
    public private(set) var form: DropForm
    public let store: OutboxStore
    public nonisolated let id: UUID

    @Published public private(set) var submission: Submission
    @Published public var main: String { didSet { draftChanged() } }
    @Published public var fields: [String: FieldValue] { didSet { draftChanged() } }
    @Published public var scrubMedia: Bool { didSet { draftChanged() } }
    @Published public private(set) var isSending = false
    @Published public private(set) var isImporting = false
    /// The line under the Send button, as on the page.
    @Published public private(set) var status: String?
    @Published public private(set) var statusIsBad = false
    @Published public private(set) var result: SubmissionUploader.SendResult?
    /// After a send: refused files moved to a new draft so they can go next.
    @Published public private(set) var leftover: Submission?

    public weak var activity: SendActivity?

    private var uploader: SubmissionUploader
    private let client: DropClient
    private let preparer: ItemPreparer?
    private var watchTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var importing = 0
    /// Sent or thrown away: nothing may write this submission to disk again.
    private var closed = false

    public init(form: DropForm, submission: Submission, store: OutboxStore,
                client: DropClient = DropClient(), preparer: ItemPreparer? = MediaCleaner()) {
        self.form = form
        self.store = store
        self.client = client
        self.preparer = preparer
        self.id = submission.id
        self.submission = submission
        self.main = submission.main
        self.fields = submission.fields
        self.scrubMedia = submission.scrubMedia
        self.uploader = SubmissionUploader(submission: submission, form: form, store: store, client: client, preparer: preparer)
        if submission.phase == .sent { result = .sent(failedFiles: submission.items.filter { $0.state == .failed }.count) }
        status = submission.lastError
        statusIsBad = submission.lastError != nil
        watch()
    }

    /// A new, empty submission for a form, saved in the outbox.
    public static func start(form: DropForm, store: OutboxStore, origin: Submission.Origin = .app) throws -> ComposeModel {
        let s = try store.create(form: form, origin: origin)
        return ComposeModel(form: form, submission: s, store: store)
    }

    /// Reopens an unsent submission from the outbox.
    public static func resume(_ id: UUID, store: OutboxStore, catalog: DropCatalog = .bundled) -> ComposeModel? {
        guard let s = try? store.load(id), let form = catalog.form(s.form) else { return nil }
        return ComposeModel(form: form, submission: s, store: store)
    }

    private func watch() {
        watchTask?.cancel()
        let up = uploader
        watchTask = Task { [weak self] in
            for await snap in await up.updates() {
                guard let self else { return }
                self.submission = snap
                if self.isSending {
                    self.status = self.progressLine(snap)
                    self.activity?.sendProgressed(Double(snap.percent) / 100)
                }
            }
        }
    }

    // MARK: Derived

    public var liveItems: [SubmissionItem] { submission.items.filter { $0.state != .removed } }

    public var hasContent: Bool {
        var probe = submission
        probe.main = main
        probe.fields = fields
        return probe.hasContent(in: form)
    }

    public var canSend: Bool { !isSending && !isImporting && result == nil && hasContent }

    /// Something to send, or a held-back file the sender still has to decide about.
    public var isWorthKeeping: Bool { hasContent || submission.items.contains { $0.state == .failed } }

    /// True once anything has gone to the server, so the form can no longer change.
    public var isCommitted: Bool { submission.token != nil || submission.phase != .draft }

    private func progressLine(_ s: Submission) -> String {
        switch s.phase {
        case .finishing: return "Sending…"
        case .sent: return "Sent."
        default:
            if s.items.contains(where: { $0.state == .preparing }) { return "Removing hidden details from photos and videos…" }
            return s.liveItems.isEmpty ? "Sending…" : "Uploading: \(s.percent)%."
        }
    }

    // MARK: Draft

    private func draftChanged() {
        guard !isSending, !closed, result == nil else { return }
        saveTask?.cancel()
        let up = uploader, m = main, f = fields, scrub = scrubMedia
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await up.update(main: m, fields: f, scrubMedia: scrub)
        }
    }

    /// Writes the note and fields to the outbox now (before leaving the screen).
    public func saveNow() async {
        saveTask?.cancel()
        guard !isSending, !closed, result == nil else { return }
        await uploader.update(main: main, fields: fields, scrubMedia: scrubMedia)
    }

    /// Moves an unsent, never-started submission to another drop box. Files and the note
    /// stay; the details reset to the new form's.
    public func switchForm(to newForm: DropForm) async {
        guard !isCommitted, !isSending, newForm.form != form.form else { return }
        saveTask?.cancel()
        let up = uploader
        await up.update(main: main, fields: fields, scrubMedia: scrubMedia)
        guard await up.switchForm(to: newForm) else { return }
        form = newForm
        // Its debounced save goes to the same uploader, which already has the new form.
        fields = newForm.defaultFields
    }

    // MARK: Files

    /// Hold these around a batch (several shared or picked files) so Send stays off until
    /// the last one is in.
    public func beginImport() {
        importing += 1
        isImporting = true
    }

    public func endImport() {
        importing = max(0, importing - 1)
        isImporting = importing > 0
    }

    /// Copies (or moves) a file in. Shows a status line if it cannot be read.
    public func addFile(_ url: URL, displayName: String? = nil, move: Bool = false) async {
        beginImport()
        defer { endImport() }
        let ext = url.pathExtension
        let type = UTType(filenameExtension: ext)
        let mime = type?.preferredMIMEType ?? MIMEType.forExtension(ext)
        do {
            try await uploader.addFile(from: url, displayName: displayName, contentType: mime, kind: Self.kind(for: type, mime: mime, ext: ext), move: move)
            clearStatus()
        } catch {
            if move { try? FileManager.default.removeItem(at: url) }
            say("Could not add \(displayName ?? url.lastPathComponent).", bad: true)
        }
    }

    public func addData(_ data: Data, fileName: String) async {
        beginImport()
        defer { endImport() }
        let ext = (fileName as NSString).pathExtension
        let type = UTType(filenameExtension: ext)
        let mime = type?.preferredMIMEType ?? MIMEType.forExtension(ext)
        do {
            try await uploader.addData(data, fileName: fileName, contentType: mime, kind: Self.kind(for: type, mime: mime, ext: ext))
            clearStatus()
        } catch {
            say("Could not add \(fileName).", bad: true)
        }
    }

    /// Adds pasted or shared text to the end of the note, as the page does.
    public func appendText(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        main += main.isEmpty ? t : "\n\n" + t
    }

    static func kind(for type: UTType?, mime: String, ext: String) -> SubmissionItem.Kind {
        if let t = type {
            if t.conforms(to: .image) { return .photo }
            if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
            if t.conforms(to: .audio) { return .audio }
            if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .spreadsheet)
                || t.conforms(to: .presentation) || t.conforms(to: .compositeContent) || t.conforms(to: .archive) {
                return .document
            }
        }
        return MIMEType.kind(mime: mime, ext: ext)
    }

    public func remove(_ item: SubmissionItem) {
        let up = uploader
        Task { await up.remove(itemID: item.id) }
    }

    public func retry(_ item: SubmissionItem) {
        let up = uploader
        Task { await up.retry(itemID: item.id) }
    }

    public func sendAsIs(_ item: SubmissionItem) {
        let up = uploader
        Task { await up.sendWithoutCleaning(itemID: item.id) }
    }

    // MARK: Sending

    public func send() {
        guard canSend else { return }
        saveTask?.cancel()
        isSending = true
        say("Starting…", bad: false)
        let activity = self.activity
        activity?.sendBegan(title: form.sendLabel, stop: { [weak self] in self?.pause() })
        let up = uploader, m = main, f = fields, scrub = scrubMedia
        let store = self.store, id = self.id, sendLabel = form.sendLabel, sentForm = self.form
        sendTask = Task { [weak self] in
            await up.update(main: m, fields: f, scrubMedia: scrub)
            var ok = false
            do {
                let r = try await up.send()
                ok = true
                // The drop box has it. The phone keeps nothing of it; files the box refused
                // move to a new draft so they can go next.
                self?.closed = true
                let sent = await up.submission
                let next = store.finishSent(sent, form: sentForm)
                store.delete(id)
                self?.leftover = next
                self?.result = r
                self?.say(nil, bad: false)
            } catch is CancellationError {
                self?.say("Paused. Press \(sendLabel) to pick up where it stopped.", bad: false)
            } catch {
                let msg = (error as? DropError)?.userMessage ?? "Could not send. Check your connection and press the button again."
                self?.say(msg, bad: true)
            }
            self?.isSending = false
            activity?.sendEnded(success: ok)
        }
    }

    /// Stops uploading. Progress is kept; Send picks up where it stopped.
    public func pause() {
        sendTask?.cancel()
    }

    /// Stops uploading and waits until the stop is saved, and until files still being
    /// added are in (up to ten seconds), so the outbox holds a clean, resumable state.
    public func settle() async {
        sendTask?.cancel()
        await sendTask?.value
        var waited = 0
        while isImporting && waited < 100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        await saveNow()
    }

    /// Throws the submission away and deletes its files from the phone.
    public func discard() {
        closed = true
        sendTask?.cancel()
        saveTask?.cancel()
        watchTask?.cancel()
        store.delete(id)
    }

    /// Shows a problem on the status line (a file that could not be read, say).
    public func reportProblem(_ message: String) {
        say(message, bad: true)
    }

    private func say(_ text: String?, bad: Bool) {
        status = text
        statusIsBad = bad
    }

    private func clearStatus() {
        if !isSending { say(nil, bad: false) }
    }

    /// "3 files and your note reached the editor." The page's words after a send.
    public var sentMessage: String {
        let n = submission.items.filter { $0.state == .done }.count
        let files = "\(n) file\(n == 1 ? "" : "s")"
        let hasNote = !submission.main.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var s: String
        if n == 0 {
            s = "Your message reached the editor."
        } else if hasNote {
            s = "\(files) and your note reached the editor."
        } else {
            s = "\(files) reached the editor."
        }
        if let left = leftover?.items.count, left > 0 {
            s += " \(left) file\(left == 1 ? " was" : "s were") not sent: the drop box refused \(left == 1 ? "it" : "them") (too large, or over the limit for one send). \(left == 1 ? "It waits" : "They wait") under Not sent yet."
        }
        return s + " Nothing is published without being checked first."
    }
}
#endif

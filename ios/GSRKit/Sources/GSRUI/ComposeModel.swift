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

    public weak var activity: SendActivity?

    private var uploader: SubmissionUploader
    private let client: DropClient
    private let preparer: ItemPreparer?
    private var watchTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var importing = 0

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
        guard !isSending else { return }
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
        guard !isSending else { return }
        await uploader.update(main: main, fields: fields, scrubMedia: scrubMedia)
    }

    /// Moves an unsent, never-started submission to another drop box. Files and the note
    /// stay; the details reset to the new form's.
    public func switchForm(to newForm: DropForm) async {
        guard !isCommitted, !isSending, newForm.form != form.form else { return }
        await saveNow()
        var s = await uploader.submission
        s.form = newForm.form
        s.fields = newForm.defaultFields
        try? store.save(s)
        form = newForm
        fields = s.fields
        submission = s
        uploader = SubmissionUploader(submission: s, form: newForm, store: store, client: client, preparer: preparer)
        watch()
    }

    // MARK: Files

    private func beginImport() {
        importing += 1
        isImporting = true
    }

    private func endImport() {
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
        let store = self.store, id = self.id, sendLabel = form.sendLabel
        sendTask = Task { [weak self] in
            await up.update(main: m, fields: f, scrubMedia: scrub)
            var ok = false
            do {
                let r = try await up.send()
                ok = true
                // The drop box has it. The phone keeps nothing.
                store.delete(id)
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

    /// Throws the submission away and deletes its files from the phone.
    public func discard() {
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
        var s = n > 0 ? "\(n) file\(n == 1 ? "" : "s") and your note reached the editor." : "Your message reached the editor."
        if case .sent(let failed)? = result, failed > 0 {
            s += " \(failed) file\(failed == 1 ? "" : "s") could not be sent; see the note above it."
        }
        return s + " Nothing is published without being checked first."
    }
}
#endif

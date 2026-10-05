import Foundation

/// Unsent submissions on disk: `<root>/<submission id>/submission.json` plus the files.
///
/// The app and its share extension share one outbox in their App Group container, so
/// something started in the share sheet can be finished in the app. Each submission's
/// folder is deleted as soon as the drop box confirms it: the phone keeps no record of
/// what was sent.
public final class OutboxStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    private let lock = NSLock()

    public init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        Self.excludeFromBackup(root)
    }

    #if canImport(Darwin)
    /// The outbox in the App Group container shared by the app and the share extension.
    public static func shared(appGroup: String) throws -> OutboxStore {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "App Group \(appGroup) is not available"])
        }
        return try OutboxStore(root: base.appendingPathComponent("Outbox", isDirectory: true))
    }
    #endif

    // MARK: Submissions

    public func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func jsonURL(_ id: UUID) -> URL {
        folder(id).appendingPathComponent("submission.json")
    }

    /// Starts a new submission for a form and saves it.
    @discardableResult
    public func create(form: DropForm, origin: Submission.Origin = .app, scrubMedia: Bool = true) throws -> Submission {
        let s = Submission(form: form, origin: origin, scrubMedia: scrubMedia)
        try fm.createDirectory(at: folder(s.id), withIntermediateDirectories: true)
        try save(s)
        return s
    }

    public func save(_ s: Submission) throws {
        var s = s
        s.updatedAt = Date()
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(s)
        lock.lock(); defer { lock.unlock() }
        // Only create(form:) makes a folder. A late save must never bring a sent or deleted
        // submission back onto the phone.
        guard fm.fileExists(atPath: folder(s.id).path) else { throw CocoaError(.fileNoSuchFile) }
        try Self.write(data, to: jsonURL(s.id))
    }

    public func load(_ id: UUID) throws -> Submission {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        lock.lock(); defer { lock.unlock() }
        return try dec.decode(Submission.self, from: Data(contentsOf: jsonURL(id)))
    }

    /// Every readable submission, newest first. Folders that do not decode are skipped.
    public func all() -> [Submission] {
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap { UUID(uuidString: $0) }
            .compactMap { try? load($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Submissions worth offering to finish: not sent, and holding a file or some text.
    public func unsent(catalog: DropCatalog = .bundled) -> [Submission] {
        all().filter { s in
            guard s.phase != .sent, let form = catalog.form(s.form) else { return false }
            return s.isWorthKeeping(in: form)
        }
    }

    /// After a confirmed send: files the drop box refused (over a limit, say) move to a new
    /// draft so the sender can send them next, and the sent submission is deleted. Returns
    /// the new draft, if there is one.
    @discardableResult
    public func finishSent(_ sent: Submission, form: DropForm) -> Submission? {
        defer { delete(sent.id) }
        let left = sent.items.filter { $0.state == .failed }
        guard !left.isEmpty, var next = try? create(form: form, origin: sent.origin, scrubMedia: sent.scrubMedia) else {
            return nil
        }
        for it in left {
            _ = try? addFile(to: &next, from: originalURL(sent, it), displayName: it.originalName, kind: it.kind, move: true)
        }
        if next.items.isEmpty {
            delete(next.id)
            return nil
        }
        return next
    }

    /// Deletes a submission and every file in it.
    public func delete(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        try? fm.removeItem(at: folder(id))
    }

    /// Deletes everything in the outbox.
    public func wipe() {
        lock.lock(); defer { lock.unlock() }
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
    }

    // MARK: Files

    /// The file that uploads for an item: the cleaned copy if there is one.
    public func uploadURL(_ s: Submission, _ item: SubmissionItem) -> URL {
        folder(s.id).appendingPathComponent(item.preparedName ?? item.storedName)
    }

    public func originalURL(_ s: Submission, _ item: SubmissionItem) -> URL {
        folder(s.id).appendingPathComponent(item.storedName)
    }

    /// Copies (or moves) a file into the submission and adds an item for it. Saves.
    @discardableResult
    public func addFile(to s: inout Submission, from source: URL, displayName: String? = nil,
                        contentType: String? = nil, kind: SubmissionItem.Kind? = nil, move: Bool = false) throws -> SubmissionItem {
        let name = Self.cleanName(displayName ?? source.lastPathComponent)
        let id = UUID()
        let stored = "\(id.uuidString.prefix(8))-\(name)"
        let dest = folder(s.id).appendingPathComponent(stored)
        guard fm.fileExists(atPath: folder(s.id).path) else { throw CocoaError(.fileNoSuchFile) }
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        if move {
            do { try fm.moveItem(at: source, to: dest) } catch { try fm.copyItem(at: source, to: dest) }
        } else {
            try fm.copyItem(at: source, to: dest)
        }
        Self.protect(dest)
        let ext = (name as NSString).pathExtension
        let type = contentType ?? MIMEType.forExtension(ext)
        let item = SubmissionItem(id: id, displayName: name, storedName: stored, contentType: type,
                                  kind: kind ?? MIMEType.kind(mime: type, ext: ext), size: Self.size(of: dest))
        s.items.append(item)
        try save(s)
        return item
    }

    /// Writes bytes into the submission as a new item (a pasted image, a camera photo). Saves.
    @discardableResult
    public func addData(to s: inout Submission, _ data: Data, fileName: String,
                        contentType: String? = nil, kind: SubmissionItem.Kind? = nil) throws -> SubmissionItem {
        let tmp = folder(s.id).appendingPathComponent(".incoming-\(UUID().uuidString)")
        guard fm.fileExists(atPath: folder(s.id).path) else { throw CocoaError(.fileNoSuchFile) }
        try Self.write(data, to: tmp)
        return try addFile(to: &s, from: tmp, displayName: fileName, contentType: contentType, kind: kind, move: true)
    }

    /// Takes an item out of a draft and deletes its files. Saves.
    public func removeItem(_ itemID: UUID, from s: inout Submission) throws {
        guard let i = s.items.firstIndex(where: { $0.id == itemID }) else { return }
        let item = s.items[i]
        try? fm.removeItem(at: originalURL(s, item))
        if let p = item.preparedName { try? fm.removeItem(at: folder(s.id).appendingPathComponent(p)) }
        s.items.remove(at: i)
        try save(s)
    }

    // MARK: Helpers

    public static func size(of url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }

    /// A file name safe on disk and readable to the editor: no slashes or control
    /// characters, no leading dots, at most 120 characters, extension kept.
    public static func cleanName(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "file" }
        if s.count > 120 {
            let ext = (s as NSString).pathExtension
            let stem = (s as NSString).deletingPathExtension
            let keep = 120 - (ext.isEmpty ? 0 : ext.count + 1)
            s = String(stem.prefix(max(1, keep))) + (ext.isEmpty ? "" : "." + ext)
        }
        return s
    }

    static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        // Readable after the first unlock, so a send can keep going with the screen locked.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    static func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    static func excludeFromBackup(_ url: URL) {
        #if canImport(Darwin)
        // Unsent tips should not ride along in iCloud or computer backups.
        var u = url
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
        #endif
    }
}

/// File type helpers that work without UniformTypeIdentifiers (so they run on Linux).
/// The app prefers `UTType.preferredMIMEType` when it has a type; this is the fallback.
public enum MIMEType {
    static let table: [String: String] = [
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif",
        "heic": "image/heic", "heif": "image/heif", "webp": "image/webp", "tif": "image/tiff", "tiff": "image/tiff",
        "dng": "image/x-adobe-dng",
        "mov": "video/quicktime", "mp4": "video/mp4", "m4v": "video/x-m4v", "3gp": "video/3gpp",
        "m4a": "audio/mp4", "mp3": "audio/mpeg", "wav": "audio/wav", "aac": "audio/aac", "caf": "audio/x-caf",
        "pdf": "application/pdf", "txt": "text/plain", "rtf": "application/rtf", "csv": "text/csv",
        "html": "text/html", "htm": "text/html", "eml": "message/rfc822", "zip": "application/zip",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "pages": "application/vnd.apple.pages", "numbers": "application/vnd.apple.numbers",
        "key": "application/vnd.apple.keynote",
    ]

    /// "" when unknown, which is what a browser sends for a file type it does not know.
    public static func forExtension(_ ext: String) -> String {
        table[ext.lowercased()] ?? ""
    }

    public static func kind(mime: String, ext: String) -> SubmissionItem.Kind {
        let m = mime.isEmpty ? forExtension(ext) : mime.lowercased()
        if m.hasPrefix("image/") { return .photo }
        if m.hasPrefix("video/") { return .video }
        if m.hasPrefix("audio/") { return .audio }
        if m.hasPrefix("application/") || m.hasPrefix("text/") || m.hasPrefix("message/") { return .document }
        return .other
    }
}

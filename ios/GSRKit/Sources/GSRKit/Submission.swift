import Foundation

/// One thing a sender is putting together for one drop box: the note, the optional
/// fields, and the files. Saved in the outbox as it changes, so nothing is lost if the
/// app is closed, and deleted from the phone once the drop box confirms it.
public struct Submission: Codable, Hashable, Identifiable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable {
        /// Being written. Nothing has left the phone.
        case draft
        /// Send was pressed; files are uploading.
        case sending
        /// Files are up; the note is being sent.
        case finishing
        /// The drop box confirmed it.
        case sent
    }

    public enum Origin: String, Codable, Hashable, Sendable {
        case app
        case shareExtension
    }

    public var id: UUID
    /// The drop box's form name ("tips", "story", "inside", "nothing").
    public var form: String
    public var origin: Origin
    public var createdAt: Date
    public var updatedAt: Date
    /// The big text box.
    public var main: String
    /// The "Add details" fields, keyed as the page keys them.
    public var fields: [String: FieldValue]
    public var items: [SubmissionItem]
    /// Remove location and device details from photos and videos before they upload.
    public var scrubMedia: Bool
    public var phase: Phase
    /// Upload session from `start`. Kept so a send can resume after the app is closed.
    public var token: String?
    public var limits: DropLimits?
    /// Why the last send stopped, in words for the sender.
    public var lastError: String?
    public var sentAt: Date?
    /// Set when `finish` goes out with the current token and cleared when it is answered.
    /// If it is still set at the next try, the box may already have the submission.
    public var finishTriedAt: Date?

    public init(id: UUID = UUID(), form: DropForm, origin: Origin = .app, scrubMedia: Bool = true, now: Date = Date()) {
        self.id = id
        self.form = form.form
        self.origin = origin
        self.createdAt = now
        self.updatedAt = now
        self.main = ""
        self.fields = form.defaultFields
        self.items = []
        self.scrubMedia = scrubMedia
        self.phase = .draft
    }

    /// Files still in the send: not removed by the sender and not refused.
    public var liveItems: [SubmissionItem] {
        items.filter { $0.state != .removed && $0.state != .failed }
    }

    /// The page enables Send once there is a file or anything typed (selects and
    /// checkboxes do not count). Same rule here.
    public func hasContent(in form: DropForm) -> Bool {
        if !liveItems.isEmpty { return true }
        if !main.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return form.fields.contains { f in fields[f.key]?.isTyped(for: f.kind) ?? false }
    }

    /// Worth keeping on the phone: something to send, or a file held back that the sender
    /// still has to decide about.
    public func isWorthKeeping(in form: DropForm) -> Bool {
        hasContent(in: form) || items.contains { $0.state == .failed }
    }

    /// Bytes uploaded and bytes to upload, across live items.
    public var progress: (sent: Int64, total: Int64) {
        var sent: Int64 = 0, total: Int64 = 0
        for it in liveItems {
            total += it.size
            sent += it.state == .done ? it.size : min(it.sent, it.size)
        }
        return (sent, total)
    }

    /// Whole-number percent, as the page shows it ("Finishing uploads: 42%").
    public var percent: Int {
        let p = progress
        return p.total > 0 ? Int((Double(p.sent) * 100 / Double(p.total)).rounded(.down)) : 100
    }

    /// The fields exactly as the page would post them: every key the form has, typed
    /// fields as strings, checkboxes as booleans.
    public func fieldsForSending(in form: DropForm) -> [String: FieldValue] {
        var out: [String: FieldValue] = [:]
        for f in form.fields {
            let v = fields[f.key] ?? f.defaultValue
            switch f.kind {
            case .checkbox: out[f.key] = .flag(v.flag)
            default: out[f.key] = .text(v.text)
            }
        }
        return out
    }
}

public struct SubmissionItem: Codable, Hashable, Identifiable, Sendable {
    public enum State: String, Codable, Hashable, Sendable {
        /// Waiting to upload.
        case queued
        /// Removing location and device details.
        case preparing
        case uploading
        /// The connection dropped; trying again.
        case retrying
        case done
        /// Refused or gave up. `error` says why. Not part of the send.
        case failed
        /// The sender took it out.
        case removed
    }

    public enum Kind: String, Codable, Hashable, Sendable {
        case photo, video, audio, document, other
    }

    public var id: UUID
    /// The name the editor sees.
    public var displayName: String
    /// File inside the submission's outbox folder.
    public var storedName: String
    /// Cleaned copy inside the same folder, once made.
    public var preparedName: String?
    /// MIME type sent as `type`, as a browser would ("image/jpeg"). May be empty.
    public var contentType: String
    public var kind: Kind
    /// Size of the file that uploads: the cleaned copy once it exists, else the original.
    public var size: Int64
    public var serverID: DropFileID?
    /// Bytes the server confirmed.
    public var sent: Int64
    public var state: State
    public var error: String?
    /// True once location and device details were removed from this file.
    public var cleaned: Bool
    /// Removing location and device details failed, so the file is held back until the
    /// sender removes it or chooses to send it as it is.
    public var cleaningFailed: Bool
    /// The sender chose to send this file without cleaning it.
    public var sendAsIs: Bool
    /// The upload gave up because the connection kept dropping. The send stops instead of
    /// finishing without it, and the next send tries again.
    public var connectionFailed: Bool

    public init(id: UUID = UUID(), displayName: String, storedName: String, contentType: String, kind: Kind, size: Int64) {
        self.id = id
        self.displayName = displayName
        self.storedName = storedName
        self.contentType = contentType
        self.kind = kind
        self.size = size
        self.sent = 0
        self.state = .queued
        self.cleaned = false
        self.cleaningFailed = false
        self.sendAsIs = false
        self.connectionFailed = false
    }

    /// The name the file had when it was added, before any cleaning changed its extension.
    public var originalName: String {
        // storedName is "<8 characters of the id>-<name>"
        let parts = storedName.split(separator: "-", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : displayName
    }

    /// Photos and videos can carry location and device details worth removing.
    public var canBeCleaned: Bool { kind == .photo || kind == .video }

    /// Back to the start, for a new upload session.
    mutating func resetForNewSession() {
        serverID = nil
        sent = 0
        if state != .removed && state != .failed { state = .queued }
    }
}

import Foundation

/// The GSR Drop Box forms, as the live pages at granitestatereport.com define them.
///
/// The server files every submission under its form name and stores the fields the
/// page sends, so the app sends exactly what the pages send: the same form names,
/// field keys, and option values. `ios/tools/forms_from_site.py` reads them off the
/// pages into `forms.json` and `FormsJSON.generated.swift`; nothing here is typed by hand.
public struct DropCatalog: Codable, Hashable, Sendable {
    /// Base URL of the drop box REST API, ending in a slash.
    public var api: URL
    public var source: String
    public var forms: [DropForm]

    /// The catalog compiled into the app.
    public static let bundled: DropCatalog = {
        do {
            return try JSONDecoder().decode(DropCatalog.self, from: Data(bundledFormsJSON.utf8))
        } catch {
            preconditionFailure("FormsJSON.generated.swift does not decode: \(error)")
        }
    }()

    /// The door with this id ("tips", "story", "inside", "nothing", "research", "wildlife",
    /// "unexplained").
    public func form(_ id: String) -> DropForm? {
        forms.first { $0.id == id }
    }
}

/// One drop box: a page on the site and the form at the bottom of it.
public struct DropForm: Codable, Hashable, Identifiable, Sendable {
    /// The app's name for this door. For the first four pages it is the server's form name;
    /// Research Files, Wild New Hampshire, and Something You Can't Explain carry the Send a
    /// Tip box, so the server files them as "tips" and only the app tells them apart.
    public var id: String
    /// The server's name for the form ("tips", "story", "inside", "nothing").
    public var form: String
    public var slug: String
    public var pageURL: URL
    public var title: String
    public var dek: String?
    public var pageVersion: PageVersion?
    /// The prompt above the big text box.
    public var mainLabel: String
    /// The Send button's words on the page ("Send the tip").
    public var sendLabel: String
    /// The notice above the Send button, word for word. `nil` when the page has none.
    public var consent: String?
    /// Sections the app shows first, before anything else (who to call in an emergency).
    public var topSections: [ReadFirstSection]
    /// The page sections a sender is asked to read or accept, word for word.
    public var readFirst: [ReadFirstSection]
    /// The optional fields under "Add details", in page order.
    public var fields: [DropField]
    /// The site's Send menu entry for this page, when it has one.
    public var menu: MenuEntry?
    /// The page's Quick details panel, on the sighting pages.
    public var quick: QuickDetails?
    /// The page asks for the original file because it "can carry the date, the time, and the
    /// place". Drafts for it start with photo and video cleaning off.
    public var asksForOriginals: Bool

    /// The "Add details" fields the sender sees. The sighting pages hide the Send a Tip box's
    /// own "where" field because their Quick details ask for it; it still goes out, empty.
    public var visibleFields: [DropField] {
        let hidden = Set(quick?.hiddenFields ?? [])
        return fields.filter { !hidden.contains($0.key) }
    }

    /// The value every field starts with, as the page's controls start.
    public var defaultFields: [String: FieldValue] {
        var out: [String: FieldValue] = [:]
        for f in fields { out[f.key] = f.defaultValue }
        return out
    }
}

public struct MenuEntry: Codable, Hashable, Sendable {
    public var label: String
    public var blurb: String
}

/// The Quick details panel the site's script adds to the sighting pages (#gsr-sight-js).
/// On Send it writes a label and the filled-in details at the top of the note:
///
///     [Unexplained · In the sky]
///     When: Oct. 4, 9:40 p.m.
///     Where: Gilford, Route 11
///     Sent from: /unexplained/
///
/// so the editor can tell these from ordinary tips. The app writes the same lines.
public struct QuickDetails: Codable, Hashable, Sendable {
    public struct Field: Codable, Hashable, Sendable {
        /// The name written in the note ("When").
        public var key: String
        public var label: String
        public var placeholder: String
    }
    public var heading: String
    public var note: String
    public var tag: String
    public var chipsLabel: String?
    public var chips: [String]
    public var fields: [Field]
    /// Keys of the box's own fields the panel replaces.
    public var hiddenFields: [String]
    /// The page path the site writes on the "Sent from" line.
    public var sentFrom: String
}

public struct PageVersion: Codable, Hashable, Sendable {
    public var number: String
    public var date: String
}

public struct ReadFirstSection: Codable, Hashable, Sendable {
    public var heading: String
    public var blocks: [Block]

    public struct Block: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable {
            case paragraph = "p"
            case listItem = "li"
            /// A boxed callout on the page.
            case box
        }
        public var kind: Kind
        public var text: String
        /// Links inside the text, in order: phone numbers, pages, statutes.
        public var links: [Link]?
    }

    public struct Link: Codable, Hashable, Sendable {
        /// The linked words, exactly as they appear in `text`.
        public var text: String
        public var url: URL
    }
}

public struct DropField: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case text, email, url, textarea, select, checkbox
    }
    public struct Option: Codable, Hashable, Sendable {
        public var label: String
        /// What the page sends when this option is chosen ("" for "Skip this").
        public var value: String
    }

    public var key: String
    public var kind: Kind
    public var label: String
    public var options: [Option]?
    public var rows: Int?
    /// JSON `default`: a string for text-like fields and selects, a bool for checkboxes.
    public var defaultValue: FieldValue

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, kind, label, options, rows
        case defaultValue = "default"
    }
}

/// A field value as the page sends it: checkboxes as JSON booleans, everything else as strings.
public enum FieldValue: Codable, Hashable, Sendable {
    case text(String)
    case flag(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .flag(b)
        } else {
            self = .text(try c.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .flag(let b): try c.encode(b)
        }
    }

    public var text: String {
        switch self {
        case .text(let s): return s
        case .flag(let b): return b ? "true" : "false"
        }
    }

    public var flag: Bool {
        switch self {
        case .flag(let b): return b
        case .text(let s): return !s.isEmpty
        }
    }

    /// True when the sender typed something. Mirrors the page's `hasText()`: selects and
    /// checkboxes never count, because they always have a value.
    public func isTyped(for kind: DropField.Kind) -> Bool {
        switch (kind, self) {
        case (.select, _), (.checkbox, _): return false
        case (_, .text(let s)): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }
}

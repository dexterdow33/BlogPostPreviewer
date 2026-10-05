#if os(iOS)
import GSRKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Ways to add a file. The share extension offers fewer than the app.
public enum AttachSource: String, CaseIterable, Identifiable, Hashable, Sendable {
    case camera, video, photos, files, scan, voice
    public var id: String { rawValue }
}

/// How the site's Send a Tip hub labels each door (granitestatereport.com/tips/, v1.3).
public enum Doors {
    public struct Door {
        public let label: String
        public let blurb: String
        public let symbol: String
    }

    public static func door(_ form: String) -> Door {
        switch form {
        case "story":
            return Door(label: "For anyone", blurb: "Something a town, agency, court, school, or police department did to you or in front of you.", symbol: "person.wave.2")
        case "nothing":
            return Door(label: "For documents", blurb: "A memo, email, contract, or report from a public body, with the safest ways to send it.", symbol: "doc.text")
        case "inside":
            return Door(label: "For public employees", blurb: "You work in New Hampshire government and saw waste, misconduct, or a broken law. Read what the law says about speaking up first.", symbol: "building.columns")
        default:
            return Door(label: "Quick tip", blurb: "Short on time? Send a quick tip. It reaches the same editor.", symbol: "paperplane")
        }
    }
}

/// The screen for one drop box: files, the note, the optional details, the page's own
/// terms word for word, and the Send button with the page's own words on it.
public struct ComposeView: View {
    @ObservedObject var model: ComposeModel
    let sources: [AttachSource]
    let showsHeader: Bool
    let onSendAnother: (() -> Void)?
    let onDone: (() -> Void)?
    @Binding var pendingAction: AttachSource?

    @State private var cover: Cover?
    @State private var sheet: Sheet?
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showDetails = false
    @State private var showReadFirst = true

    enum Cover: Identifiable {
        case camera(CameraPicker.Mode), scan
        var id: String {
            switch self {
            case .camera(let m): return "camera-\(m == .photo ? "photo" : "video")"
            case .scan: return "scan"
            }
        }
    }

    enum Sheet: Identifiable {
        case voice, page(URL)
        var id: String {
            switch self {
            case .voice: return "voice"
            case .page(let u): return u.absoluteString
            }
        }
    }

    public init(model: ComposeModel, sources: [AttachSource] = AttachSource.allCases, showsHeader: Bool = true,
                pendingAction: Binding<AttachSource?> = .constant(nil),
                onSendAnother: (() -> Void)? = nil, onDone: (() -> Void)? = nil) {
        self.model = model
        self.sources = sources
        self.showsHeader = showsHeader
        self._pendingAction = pendingAction
        self.onSendAnother = onSendAnother
        self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsHeader { header }
                if model.result != nil {
                    sentPanel
                } else {
                    SafetyNote(pageURL: model.form.pageURL) { sheet = .page($0) }
                    attachments
                    note
                    details
                    cleaning
                    readFirst
                    sendArea
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(GSRTheme.paper2.ignoresSafeArea())
        .fullScreenCover(item: $cover) { c in
            switch c {
            case .camera(let mode):
                CameraPicker(mode: mode, onPhoto: { data in
                    Task { await model.addData(data, fileName: FileNaming.stamped("photo", ext: "jpg")) }
                }, onVideo: { url in
                    Task {
                        await model.addFile(url, displayName: FileNaming.stamped("video", ext: url.pathExtension.isEmpty ? "mov" : url.pathExtension), move: true)
                    }
                })
                .ignoresSafeArea()
            case .scan:
                DocumentScanner { pdf in
                    Task { await model.addData(pdf, fileName: FileNaming.stamped("scan", ext: "pdf")) }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .voice:
                VoiceNoteSheet { url in Task { await model.addFile(url, move: true) } }
            case .page(let url):
                SafariView(url: url).ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls { await ItemProviderLoader.copyFileURL(url, into: model) }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 50,
                      selectionBehavior: .ordered, matching: .any(of: [.images, .videos]),
                      preferredItemEncoding: .current)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await model.addPicked(items) }
        }
        .onAppear(perform: runPendingAction)
        .onChange(of: pendingAction) { _, _ in runPendingAction() }
    }

    private func runPendingAction() {
        guard let a = pendingAction else { return }
        pendingAction = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(a) }
    }

    private func open(_ source: AttachSource) {
        switch source {
        case .camera: if CameraPicker.isAvailable { cover = .camera(.photo) }
        case .video: if CameraPicker.isAvailable { cover = .camera(.video) }
        case .scan: if DocumentScanner.isAvailable { cover = .scan }
        case .photos: showPhotos = true
        case .files: showFiles = true
        case .voice: sheet = .voice
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(Doors.door(model.form.form).label)
            Text(model.form.title)
                .font(GSRTheme.serif(.largeTitle, bold: true))
                .foregroundStyle(GSRTheme.navy)
                .accessibilityAddTraits(.isHeader)
            if let dek = model.form.dek {
                Text(dek)
                    .font(GSRTheme.serif(.title3, italic: true))
                    .foregroundStyle(GSRTheme.ink2)
            }
        }
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Files")
            Text("Any file type, up to 2 GB each and 50 at a time. Nothing has to be typed.")
                .font(.footnote)
                .foregroundStyle(GSRTheme.ink2)
            AttachBar(sources: sources, disabled: model.isSending, open: open) { providers in
                Task { await ItemProviderLoader.load(providers, into: model) }
            }
            if model.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Adding…").font(.footnote).foregroundStyle(GSRTheme.ink2)
                }
            }
            ForEach(model.liveItems) { item in
                AttachmentRow(item: item, sending: model.isSending,
                              remove: { model.remove(item) },
                              retry: { model.retry(item) },
                              sendAsIs: { model.sendAsIs(item) })
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Your note")
            Text(model.form.mainLabel)
                .font(GSRTheme.serif(.callout))
                .foregroundStyle(GSRTheme.ink)
            TextEditor(text: $model.main)
                .font(GSRTheme.serif(.body))
                .frame(minHeight: 160)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(GSRTheme.paper)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(GSRTheme.rule2))
                .disabled(model.isSending)
                .accessibilityLabel(model.form.mainLabel)
        }
    }

    private var details: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(model.form.fields) { field in
                    FieldEditor(field: field, value: binding(field))
                        .disabled(model.isSending)
                }
            }
            .padding(.top, 12)
        } label: {
            Text("Add details (all optional)")
                .font(GSRTheme.serif(.headline, bold: true))
                .foregroundStyle(GSRTheme.navy)
        }
        .tint(GSRTheme.rust)
    }

    private func binding(_ f: DropField) -> Binding<FieldValue> {
        Binding(get: { model.fields[f.key] ?? f.defaultValue },
                set: { model.fields[f.key] = $0 })
    }

    @ViewBuilder
    private var cleaning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $model.scrubMedia) {
                Text("Remove hidden details from photos and videos")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(GSRTheme.ink)
            }
            .tint(GSRTheme.rust)
            .disabled(model.isSending)
            Text(model.scrubMedia
                 ? "Location, phone model, and the time taken come out before anything uploads. Documents keep their own details (author names, edit history); this app cannot clean those."
                 : "Photos and videos upload as they are, with whatever location and device details they carry. That can help prove what you saw. It can also point to you.")
                .font(.footnote)
                .foregroundStyle(model.scrubMedia ? GSRTheme.ink2 : GSRTheme.rust)
        }
        .padding(14)
        .background(GSRTheme.paper)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(GSRTheme.rule))
    }

    private var readFirst: some View {
        DisclosureGroup(isExpanded: $showReadFirst) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.form.readFirst, id: \.heading) { section in
                    ReadFirstSectionView(section: section)
                }
                Button {
                    sheet = .page(model.form.pageURL)
                } label: {
                    Label("Read the whole \(model.form.title) page", systemImage: "safari")
                        .font(.footnote.weight(.semibold))
                }
                .tint(GSRTheme.rust)
            }
            .padding(.top, 10)
        } label: {
            Text(model.form.readFirst.map(\.heading).joined(separator: " · "))
                .font(GSRTheme.serif(.headline, bold: true))
                .foregroundStyle(GSRTheme.navy)
        }
        .tint(GSRTheme.rust)
    }

    private var sendArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let consent = model.form.consent {
                Text(consent)
                    .font(GSRTheme.serif(.footnote, italic: true))
                    .foregroundStyle(GSRTheme.ink2)
            }
            if model.isSending {
                ProgressView(value: Double(model.submission.percent), total: 100)
                    .tint(GSRTheme.rust)
                    .accessibilityLabel("Upload progress")
                    .accessibilityValue("\(model.submission.percent) percent")
                Button("Pause") { model.pause() }
                    .buttonStyle(GSRButtonStyle(prominent: false))
            } else {
                Button(model.form.sendLabel) { model.send() }
                    .buttonStyle(GSRButtonStyle())
                    .disabled(!model.canSend)
            }
            if let status = model.status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(model.statusIsBad ? GSRTheme.rust : GSRTheme.ink2)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if model.isSending {
                Text("You can switch apps; the send keeps going for as long as your phone allows. If it stops, open GSR and it picks up where it left off.")
                    .font(.caption)
                    .foregroundStyle(GSRTheme.ink3)
            }
        }
    }

    private var sentPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sent. Thank you.")
                .font(GSRTheme.serif(.largeTitle, bold: true))
                .foregroundStyle(GSRTheme.navy)
                .accessibilityAddTraits(.isHeader)
            Text(model.sentMessage)
                .font(GSRTheme.serif(.body))
                .foregroundStyle(GSRTheme.ink)
            Text("The app has deleted its copy. Originals in your Photos or Files stay where they were.")
                .font(.footnote)
                .foregroundStyle(GSRTheme.ink2)
            if let again = onSendAnother {
                Button("Send something else", action: again)
                    .buttonStyle(GSRButtonStyle(prominent: false))
            }
            if let done = onDone {
                Button("Done", action: done)
                    .buttonStyle(GSRButtonStyle())
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Pieces

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(GSRTheme.serif(.title3, bold: true))
                .foregroundStyle(GSRTheme.navy)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(GSRTheme.rust).frame(height: 2)
        }
    }
}

/// What the app tells a sender before anything leaves the phone. Adapted from "Before you
/// send anything" on granitestatereport.com/tips/ for what the app does.
public struct SafetyNote: View {
    let pageURL: URL
    let openPage: (URL) -> Void
    @State private var expanded = false

    public init(pageURL: URL, openPage: @escaping (URL) -> Void) {
        self.pageURL = pageURL
        self.openPage = openPage
    }

    public static let points: [String] = [
        "This app is not anonymous. It sends to the same drop box as the website: what you send is stored on the site's server with the host, WordPress.com, and a notice is emailed to the newsroom's Gmail account, with the files attached when they total under 15 MB. The host logs IP addresses.",
        "Never use a work phone, work email, or work Wi-Fi. Your employer can see what crosses them.",
        "Files carry hidden data. This app removes location and device details from photos and videos unless you turn that off. It cannot clean documents: author names and edit history stay in them. A screenshot or a photo of a printout carries less.",
        "For anything sensitive, use Signal or the mail, not this app. Both are on the Contact tab.",
        "Nothing leaves your phone until you press Send. Once the drop box confirms it, the app deletes its copy.",
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.shield")
                    Text("Before you send anything")
                        .font(.system(.subheadline).weight(.bold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.footnote)
                }
                .foregroundStyle(GSRTheme.ink)
            }
            .accessibilityHint(expanded ? "Hides the safety notes" : "Shows the safety notes")
            Text(Self.points[0])
                .font(.footnote)
                .foregroundStyle(GSRTheme.ink)
            if expanded {
                ForEach(Self.points.dropFirst(), id: \.self) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(p)
                    }
                    .font(.footnote)
                    .foregroundStyle(GSRTheme.ink)
                }
                Button("How GSR handles what you send") { openPage(GSRContact.tipsPage) }
                    .font(.footnote.weight(.semibold))
                    .tint(GSRTheme.rust)
            }
        }
        .padding(14)
        .background(GSRTheme.rustSoft)
        .overlay(alignment: .leading) { Rectangle().fill(GSRTheme.rust).frame(width: 4) }
    }
}

struct AttachBar: View {
    let sources: [AttachSource]
    let disabled: Bool
    let open: (AttachSource) -> Void
    let paste: ([NSItemProvider]) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(sources) { s in
                Button { open(s) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: symbol(s)).font(.title3)
                        Text(title(s)).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(isAvailable(s) ? GSRTheme.navy : GSRTheme.ink3)
                    .background(GSRTheme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(GSRTheme.rule2))
                }
                .disabled(disabled || !isAvailable(s))
                .accessibilityLabel(title(s))
            }
            PasteButton(supportedContentTypes: [.movie, .image, .pdf, .data, .url, .plainText]) { providers in
                DispatchQueue.main.async { paste(providers) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.roundedRectangle(radius: 6))
            .tint(GSRTheme.navy)
            .disabled(disabled)
        }
    }

    func isAvailable(_ s: AttachSource) -> Bool {
        switch s {
        case .camera, .video: return CameraPicker.isAvailable
        case .scan: return DocumentScanner.isAvailable
        default: return true
        }
    }

    func title(_ s: AttachSource) -> String {
        switch s {
        case .camera: return "Take a photo"
        case .video: return "Record video"
        case .photos: return "Photos"
        case .files: return "Files"
        case .scan: return "Scan a document"
        case .voice: return "Voice note"
        }
    }

    func symbol(_ s: AttachSource) -> String {
        switch s {
        case .camera: return "camera"
        case .video: return "video"
        case .photos: return "photo.on.rectangle"
        case .files: return "folder"
        case .scan: return "doc.viewfinder"
        case .voice: return "mic"
        }
    }
}

struct AttachmentRow: View {
    let item: SubmissionItem
    let sending: Bool
    let remove: () -> Void
    let retry: () -> Void
    let sendAsIs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(GSRTheme.navy)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(item.state == .failed ? GSRTheme.rust : GSRTheme.ink2)
                }
                Spacer(minLength: 4)
                if item.state != .done {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(GSRTheme.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.displayName)")
                }
            }
            if item.state == .uploading || item.state == .retrying {
                ProgressView(value: Double(min(item.sent, item.size)), total: Double(max(item.size, 1)))
                    .tint(GSRTheme.rust)
            }
            if item.state == .failed && !sending {
                HStack(spacing: 16) {
                    if item.cleaningFailed {
                        Button("Send as is", action: sendAsIs)
                    } else if item.serverID != nil || item.error?.contains("connection") == true || item.error?.contains("losing") == true {
                        Button("Try again", action: retry)
                    }
                }
                .font(.caption.weight(.semibold))
                .tint(GSRTheme.rust)
            }
        }
        .padding(12)
        .background(GSRTheme.paper)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(item.state == .failed ? GSRTheme.rust : GSRTheme.rule))
        .accessibilityElement(children: .combine)
    }

    var symbol: String {
        switch item.kind {
        case .photo: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .document: return "doc"
        case .other: return "doc.zipper"
        }
    }

    /// "1.5 MB · 42%", as the page writes it.
    var meta: String {
        let size = ByteFormat.human(item.size)
        switch item.state {
        case .failed: return size + " · " + (item.error ?? "Upload failed.")
        case .done: return size + " · Uploaded" + (item.cleaned ? " (cleaned)" : "")
        case .uploading:
            let pct = item.size > 0 ? Int(Double(item.sent) * 100 / Double(item.size)) : 100
            return size + " · \(pct)%"
        case .retrying: return size + " · Connection hiccup, retrying"
        case .preparing: return size + " · Removing hidden details"
        case .queued: return size + (sending ? " · Waiting" : "")
        case .removed: return size
        }
    }
}

struct FieldEditor: View {
    let field: DropField
    @Binding var value: FieldValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if field.kind != .checkbox {
                Text(field.label)
                    .font(.footnote)
                    .foregroundStyle(GSRTheme.ink2)
            }
            control
        }
    }

    private var text: Binding<String> {
        Binding(get: { value.text }, set: { value = .text($0) })
    }

    private var contentType: UITextContentType? {
        switch field.kind {
        case .email: return .emailAddress
        case .url: return .URL
        default: return nil
        }
    }

    @ViewBuilder
    private var control: some View {
        switch field.kind {
        case .checkbox:
            Toggle(isOn: Binding(get: { value.flag }, set: { value = .flag($0) })) {
                Text(field.label).font(.subheadline)
            }
            .tint(GSRTheme.rust)
        case .select:
            Picker(field.label, selection: text) {
                ForEach(field.options ?? [], id: \.self) { o in
                    Text(o.label).tag(o.value)
                }
            }
            .pickerStyle(.menu)
            .tint(GSRTheme.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(GSRTheme.paper)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(GSRTheme.rule2))
        case .textarea:
            TextField("", text: text, axis: .vertical)
                .lineLimit((field.rows ?? 3)...max(field.rows ?? 3, 10))
                .padding(8)
                .background(GSRTheme.paper)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(GSRTheme.rule2))
                .accessibilityLabel(field.label)
        case .email, .url, .text:
            TextField("", text: text)
                .keyboardType(field.kind == .email ? .emailAddress : field.kind == .url ? .URL : .default)
                .textInputAutocapitalization(field.kind == .text ? .sentences : .never)
                .autocorrectionDisabled(field.kind != .text)
                .textContentType(contentType)
                .padding(8)
                .background(GSRTheme.paper)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(GSRTheme.rule2))
                .accessibilityLabel(field.label)
        }
    }
}

/// One of the page's read-first sections, word for word.
struct ReadFirstSectionView: View {
    let section: ReadFirstSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.heading)
                .font(GSRTheme.serif(.headline, bold: true))
                .foregroundStyle(GSRTheme.navy)
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .listItem:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(GSRTheme.rust)
                        Text(block.text)
                    }
                    .font(GSRTheme.serif(.subheadline))
                case .paragraph:
                    Text(block.text).font(GSRTheme.serif(.subheadline))
                case .box:
                    Text(block.text)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GSRTheme.paper3)
                        .overlay(alignment: .leading) { Rectangle().fill(GSRTheme.navy).frame(width: 3) }
                }
            }
        }
        .foregroundStyle(GSRTheme.ink)
    }
}
#endif

import GSRKit
import GSRUI
import SwiftUI

/// The Send tab: the four drop boxes, quick ways to capture something, and anything
/// started but not sent.
struct SendHomeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var app: AppModel

    /// Quick tip first, then the hub's three doors in the order the site lists them.
    private let order = ["tips", "story", "nothing", "inside"]

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Masthead()
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker("Send a tip")
                        Text("Something wrong in a New Hampshire public body?")
                            .font(GSRTheme.serif(.title, bold: true))
                            .foregroundStyle(GSRTheme.navy)
                        Text("Tell Granite State Report. Send words, photos, video, documents, or a voice note. Nothing has to be typed, and nothing leaves your phone until you press Send.")
                            .font(GSRTheme.serif(.body))
                            .foregroundStyle(GSRTheme.ink)
                    }

                    if let err = app.storeError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(GSRTheme.rust)
                    }

                    if !app.unsent.isEmpty { unsentList }

                    quickCapture

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("Pick the right door")
                        ForEach(order, id: \.self) { name in
                            if let form = app.catalog.form(name) {
                                DoorCard(form: form) { router.openCompose(form: name) }
                            }
                        }
                    }

                    Text("Signal and the mail are safer than any app or form. Both are on the Contact tab.")
                        .font(GSRTheme.serif(.footnote, italic: true))
                        .foregroundStyle(GSRTheme.ink2)
                }
                .padding(18)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(GSRTheme.paper2.ignoresSafeArea())
            .navigationTitle("Send")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRouter.Route.self) { route in
                ComposeScreen(route: route)
            }
        }
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Capture it now")
            HStack(spacing: 10) {
                QuickButton(title: "Photo or video", symbol: "camera", enabled: CameraPicker.isAvailable) {
                    router.openCompose(form: "tips", action: .camera)
                }
                QuickButton(title: "Scan a document", symbol: "doc.viewfinder", enabled: DocumentScanner.isAvailable) {
                    router.openCompose(form: "nothing", action: .scan)
                }
                QuickButton(title: "Voice note", symbol: "mic", enabled: true) {
                    router.openCompose(form: "tips", action: .voice)
                }
            }
            Text("Or share straight from Photos, Files, Mail, or any app: tap Share, then Send to GSR.")
                .font(.footnote)
                .foregroundStyle(GSRTheme.ink2)
        }
    }

    private var unsentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Not sent yet")
            ForEach(app.unsent) { s in
                let title = app.catalog.form(s.form)?.title ?? s.form
                let files = s.liveItems.count
                Button {
                    router.resume(s.id)
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(GSRTheme.serif(.headline, bold: true)).foregroundStyle(GSRTheme.navy)
                            Text(summary(s, files: files)).font(.footnote).foregroundStyle(GSRTheme.ink2)
                            if let e = s.lastError {
                                Text(e).font(.footnote).foregroundStyle(GSRTheme.rust)
                            }
                        }
                        Spacer()
                        Text("Finish").font(.subheadline.weight(.semibold)).foregroundStyle(GSRTheme.rust)
                    }
                    .padding(14)
                    .background(GSRTheme.paper)
                    .overlay(alignment: .leading) { Rectangle().fill(GSRTheme.rust).frame(width: 4) }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete from this phone", role: .destructive) { app.discard(s.id) }
                }
            }
        }
    }

    private func summary(_ s: Submission, files: Int) -> String {
        var parts: [String] = []
        if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s")") }
        if !s.main.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("a note") }
        if s.origin == .shareExtension { parts.append("from the share sheet") }
        if s.phase != .draft || s.token != nil { parts.append("partly uploaded") }
        let what = parts.isEmpty ? "Started" : parts.joined(separator: ", ")
        return what + " · " + s.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(GSRTheme.serif(.title2, bold: true))
                .foregroundStyle(GSRTheme.navy)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(GSRTheme.rust).frame(height: 2)
        }
    }
}

struct DoorCard: View {
    let form: DropForm
    let open: () -> Void

    var body: some View {
        let door = Doors.door(form.form)
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: door.symbol)
                    .font(.title2)
                    .foregroundStyle(GSRTheme.rust)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Kicker(door.label)
                    Text(form.title)
                        .font(GSRTheme.serif(.title3, bold: true))
                        .foregroundStyle(GSRTheme.navy)
                    Text(door.blurb)
                        .font(GSRTheme.serif(.subheadline))
                        .foregroundStyle(GSRTheme.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(GSRTheme.ink3).padding(.top, 4)
            }
            .padding(16)
            .background(GSRTheme.paper)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(GSRTheme.rule2))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(form.title) drop box")
    }
}

struct QuickButton: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .foregroundStyle(enabled ? Color.white : GSRTheme.ink3)
            .background(RoundedRectangle(cornerRadius: 6).fill(enabled ? GSRTheme.navy : GSRTheme.paper3))
        }
        .disabled(!enabled)
    }
}

/// One drop box, opened from the Send tab.
struct ComposeScreen: View {
    let route: AppRouter.Route
    @EnvironmentObject private var app: AppModel
    @State private var model: ComposeModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                ComposeContainer(model: model)
            } else if failed {
                Text("This could not be opened. It may have been sent or deleted already.")
                    .font(GSRTheme.serif(.body))
                    .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil else { return }
            model = app.model(for: route)
            failed = model == nil
        }
    }
}

struct ComposeContainer: View {
    @ObservedObject var model: ComposeModel
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var router: AppRouter
    @State private var confirmDelete = false

    var body: some View {
        ComposeView(model: model,
                    pendingAction: $router.pendingAction,
                    onSendAnother: { router.openCompose(form: model.form.form) },
                    onDone: { router.path = [] })
            .navigationTitle(model.form.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.result == nil {
                        Menu {
                            Button("Delete this from the phone", role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(model.isSending)
                        .accessibilityLabel("More")
                    }
                }
            }
            .confirmationDialog("Delete this? The files and note are removed from this phone. Nothing is sent.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    app.discard(model)
                    router.path = []
                }
            }
            .onChange(of: model.result) { _, r in
                if r != nil { app.release(model) }
            }
            .onDisappear {
                Task { await model.saveNow() }
                app.refreshUnsent()
            }
    }
}

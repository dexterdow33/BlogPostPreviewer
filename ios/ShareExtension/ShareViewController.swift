import GSRKit
import GSRUI
import SwiftUI
import UIKit

/// "Send to GSR" in the share sheet. Whatever was shared (photos, videos, files, a link,
/// text) goes into a new submission in the shared outbox. The sender can send it from
/// here with the sheet open, or leave it for the GSR app to finish.
final class ShareViewController: UIViewController {
    private var model: ComposeModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255, alpha: 1)

        guard let store = try? AppGroup.outbox(),
              let form = DropCatalog.bundled.form("tips"),
              let model = try? ComposeModel.start(form: form, store: store, origin: .shareExtension) else {
            show(ShareFailedView(close: { [weak self] in self?.finish() }))
            return
        }
        self.model = model
        show(ShareRootView(model: model) { [weak self] keep in self?.close(keep: keep) })

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let sharedText = items.compactMap { $0.attributedContentText?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        Task { @MainActor in
            for t in sharedText { model.appendText(t) }
            await ItemProviderLoader.load(providers, into: model)
        }
    }

    private func show<V: View>(_ root: V) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// `keep`: leave the submission in the outbox for the app. Otherwise delete whatever
    /// the extension copied (a finished send has already deleted it).
    private func close(keep: Bool) {
        guard let model else { return finish() }
        if keep {
            Task { @MainActor in
                await model.saveNow()
                self.finish()
            }
        } else {
            if model.result == nil { model.discard() }
            finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

struct ShareRootView: View {
    @ObservedObject var model: ComposeModel
    let close: (_ keepForApp: Bool) -> Void
    @State private var formName = "tips"
    @State private var confirmCancel = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.result == nil && !model.isCommitted && !model.isSending {
                    HStack {
                        Text("Send to")
                            .font(.subheadline)
                            .foregroundStyle(GSRTheme.ink2)
                        Picker("Drop box", selection: $formName) {
                            ForEach(DropCatalog.bundled.forms) { f in
                                Text(f.title).tag(f.form)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(GSRTheme.navy)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(GSRTheme.paper)
                }
                ComposeView(model: model, sources: [.photos, .files], showsHeader: false,
                            onDone: { close(false) })
            }
            .navigationTitle("Send to GSR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.result == nil {
                        Button("Cancel") {
                            if model.hasContent { confirmCancel = true } else { close(false) }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.result == nil {
                        Button("Finish in app") {
                            model.pause()
                            close(true)
                        }
                        .disabled(!model.hasContent)
                    }
                }
            }
            .confirmationDialog("Leave without sending?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Keep it for the GSR app") {
                    model.pause()
                    close(true)
                }
                Button("Delete it", role: .destructive) { close(false) }
            } message: {
                Text("Kept items wait under Not sent yet in the GSR app. Deleted items are removed from this phone; nothing is sent.")
            }
            .onChange(of: formName) { _, name in
                guard let f = DropCatalog.bundled.form(name) else { return }
                Task { await model.switchForm(to: f) }
            }
        }
        .tint(GSRTheme.rust)
    }
}

struct ShareFailedView: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Send to GSR could not open its storage on this phone.")
                .font(GSRTheme.serif(.title3, bold: true))
                .foregroundStyle(GSRTheme.navy)
                .multilineTextAlignment(.center)
            Text("Open the GSR app instead, or email \(GSRContact.email).")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Close", action: close).buttonStyle(GSRButtonStyle())
        }
        .padding(28)
    }
}

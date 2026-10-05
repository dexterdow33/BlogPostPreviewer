import GSRKit
import GSRUI
import SwiftUI

/// Where the app is: which tab, and which drop box is open on the Send tab.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Hashable { case send, latest, contact }

    enum Route: Hashable {
        /// A drop box. `nonce` makes each opening a fresh screen.
        case compose(form: String, nonce: UUID)
        /// An unsent submission from the outbox.
        case resume(UUID)
    }

    @Published var tab: Tab = .send
    @Published var path: [Route] = []
    /// A picker to open as soon as the compose screen appears (from a quick action or Siri).
    @Published var pendingAction: AttachSource?

    private init() {
        // App Store screenshots: the CI workflow launches the simulator build with
        // -GSRScreenshotTab latest|contact or -GSRScreenshotForm <form> to open a screen.
        let d = UserDefaults.standard
        switch d.string(forKey: "GSRScreenshotTab") {
        case "latest": tab = .latest
        case "contact": tab = .contact
        default: break
        }
        if let form = d.string(forKey: "GSRScreenshotForm") {
            path = [.compose(form: form, nonce: UUID())]
        }
    }

    func openCompose(form: String, action: AttachSource? = nil) {
        tab = .send
        pendingAction = action
        path = [.compose(form: form, nonce: UUID())]
    }

    func resume(_ id: UUID) {
        tab = .send
        path = [.resume(id)]
    }

    @discardableResult
    func handleShortcut(_ type: String) -> Bool {
        switch type {
        case "com.granitestatereport.app.tip": openCompose(form: "tips")
        case "com.granitestatereport.app.scan": openCompose(form: "nothing", action: .scan)
        case "com.granitestatereport.app.video": openCompose(form: "tips", action: .video)
        default: return false
        }
        return true
    }
}

/// The outbox and the open submissions. Keeps a submission's model alive while it sends,
/// even after its screen closes.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let catalog = DropCatalog.bundled
    let store: OutboxStore?
    let storeError: String?
    @Published private(set) var unsent: [Submission] = []

    private var models: [UUID: ComposeModel] = [:]
    /// The draft each drop box reopens to until it is sent or deleted.
    private var draftByForm: [String: UUID] = [:]
    private let sender = BackgroundSender()

    private init() {
        do {
            store = try AppGroup.outbox()
            storeError = nil
        } catch {
            store = nil
            storeError = "The app could not open its storage on this phone. Use Signal or the mail instead. Both are on the Contact tab."
        }
        sweepEmptyDrafts()
        refreshUnsent()
    }

    func refreshUnsent() {
        unsent = store?.unsent(catalog: catalog) ?? []
    }

    /// Empty drafts left by screens opened and closed without anything in them, and anything
    /// already sent (left only if the app was closed between the confirmation and the delete).
    private func sweepEmptyDrafts() {
        guard let store else { return }
        for s in store.all() {
            if s.phase == .sent {
                store.delete(s.id)
            } else if s.phase == .draft, s.token == nil, let form = catalog.form(s.form), !s.isWorthKeeping(in: form) {
                store.delete(s.id)
            }
        }
    }

    func model(for route: AppRouter.Route) -> ComposeModel? {
        guard let store else { return nil }
        switch route {
        case .compose(let formName, _):
            guard let form = catalog.form(formName) else { return nil }
            if let id = draftByForm[formName], let m = models[id], m.result == nil { return m }
            // Reopen this drop box's newest unsent draft started in the app, if there is one.
            if let s = store.unsent(catalog: catalog).first(where: { $0.form == formName && $0.origin == .app && $0.phase == .draft }),
               let m = adopt(ComposeModel.resume(s.id, store: store, catalog: catalog)) {
                draftByForm[formName] = m.id
                return m
            }
            guard let m = adopt(try? ComposeModel.start(form: form, store: store)) else { return nil }
            draftByForm[formName] = m.id
            return m
        case .resume(let id):
            if let m = models[id] { return m }
            return adopt(ComposeModel.resume(id, store: store, catalog: catalog))
        }
    }

    private func adopt(_ m: ComposeModel?) -> ComposeModel? {
        guard let m else { return nil }
        m.activity = sender
        models[m.id] = m
        return m
    }

    /// The submission was sent or thrown away: forget it.
    func release(_ m: ComposeModel) {
        models[m.id] = nil
        draftByForm = draftByForm.filter { $0.value != m.id }
        refreshUnsent()
    }

    func discard(_ m: ComposeModel) {
        m.discard()
        release(m)
    }

    func discard(_ id: UUID) {
        if let m = models[id] {
            discard(m)
        } else {
            store?.delete(id)
            refreshUnsent()
        }
    }

    /// Deletes everything the app holds on this phone. Stops any send in progress.
    func wipe() {
        AppRouter.shared.path = []
        for m in models.values { m.discard() }
        models.removeAll()
        draftByForm.removeAll()
        store?.wipe()
        // Picker and recorder copies waiting in the app's temporary folder go too.
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path)) ?? [] {
            try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent(name))
        }
        refreshUnsent()
    }

    var isSendingAnything: Bool { models.values.contains { $0.isSending } }
}

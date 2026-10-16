import AppIntents
import GSRUI

/// Siri, Spotlight, the Shortcuts app, and the Action Button can open a drop box directly.

struct SendTipIntent: AppIntent {
    static let title: LocalizedStringResource = "Send a Tip"
    static let description = IntentDescription("Opens the Granite State Report quick tip box.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openCompose(form: "tips")
        return .result()
    }
}

struct ScanDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Document for GSR"
    static let description = IntentDescription("Opens the document scanner and puts the scan in the Nothing to See Here drop box.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openCompose(form: "nothing", action: .scan)
        return .result()
    }
}

struct RecordVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a Video for GSR"
    static let description = IntentDescription("Opens the camera to record a video for a Granite State Report tip.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openCompose(form: "tips", action: .video)
        return .result()
    }
}

struct GSRShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendTipIntent(),
                    phrases: ["Send a tip to \(.applicationName)", "Send \(.applicationName) a tip"],
                    shortTitle: "Send a Tip",
                    systemImageName: "paperplane")
        AppShortcut(intent: ScanDocumentIntent(),
                    phrases: ["Scan a document for \(.applicationName)"],
                    shortTitle: "Scan a Document",
                    systemImageName: "doc.viewfinder")
        AppShortcut(intent: RecordVideoIntent(),
                    phrases: ["Record a video for \(.applicationName)"],
                    shortTitle: "Record a Video",
                    systemImageName: "video")
    }
}

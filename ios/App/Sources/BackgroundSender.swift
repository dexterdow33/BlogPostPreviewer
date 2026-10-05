import BackgroundTasks
import GSRUI
import UIKit

/// Keeps a send going after the sender leaves the app.
///
/// - Every iOS version: a background task buys the time iOS allows after leaving the app.
/// - iOS 26 and later: a continued-processing task, started from the Send button, keeps
///   the upload running with its progress shown by the system, until it finishes or the
///   sender stops it there.
///
/// If iOS stops the app anyway, the send stays in the outbox with its progress saved, and
/// opening the app picks it up where it stopped.
@MainActor
final class BackgroundSender: SendActivity {
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var continued: AnyObject?
    private var stopHandler: (() -> Void)?
    private var running = 0

    func sendBegan(title: String, stop: @escaping () -> Void) {
        running += 1
        stopHandler = stop
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Send to Granite State Report") { [weak self] in
                // Time is up. Progress is saved; the send resumes when the app comes back.
                self?.endBackgroundTask()
            }
        }
        if #available(iOS 26.0, *), continued == nil {
            submitContinuedTask(title: title)
        }
    }

    func sendProgressed(_ fraction: Double) {
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = Int64(max(0, min(1, fraction)) * 1000)
        }
    }

    func sendEnded(success: Bool) {
        running = max(0, running - 1)
        guard running == 0 else { return }
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask {
            if success { task.progress.completedUnitCount = 1000 }
            task.setTaskCompleted(success: success)
        }
        continued = nil
        stopHandler = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    @available(iOS 26.0, *)
    private func submitContinuedTask(title: String) {
        // Info.plist allows "<bundle id>.send.*". Each send gets its own identifier,
        // registered just before it is submitted, as continued-processing tasks allow.
        let base = Bundle.main.bundleIdentifier ?? "com.granitestatereport.app"
        let identifier = "\(base).send.\(UUID().uuidString.prefix(8))"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            task.progress.totalUnitCount = 1000
            task.expirationHandler = {
                // The sender stopped it from the system's progress view, or iOS ran out
                // of patience. Pause; the outbox keeps the progress.
                Task { @MainActor in BackgroundSender.handleExpiry() }
            }
            Task { @MainActor in BackgroundSender.attach(task) }
        }
        guard registered else { return }
        // The Lock Screen can be read without unlocking the phone: say nothing about where
        // the upload is going.
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Uploading",
                                                       subtitle: "Open the app to see progress")
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not available right now (or on the simulator). The send carries on in the
            // foreground and with the ordinary background task.
        }
    }

    // The launch handler runs on a background queue; these hop back to the one sender.
    private static weak var current: BackgroundSender?

    @available(iOS 26.0, *)
    private static func attach(_ task: BGContinuedProcessingTask) {
        guard let me = current, me.running > 0 else {
            task.setTaskCompleted(success: true)
            return
        }
        me.continued = task
    }

    private static func handleExpiry() {
        guard let me = current else { return }
        me.stopHandler?()
        if #available(iOS 26.0, *), let task = me.continued as? BGContinuedProcessingTask {
            task.setTaskCompleted(success: false)
        }
        me.continued = nil
    }

    init() {
        BackgroundSender.current = self
    }
}

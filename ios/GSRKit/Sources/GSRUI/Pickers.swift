#if os(iOS)
import AVFoundation
import CoreTransferable
import GSRKit
import PhotosUI
import SafariServices
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Camera

/// The system camera, for a photo or a video. Photos come back without location data
/// (the camera picker does not add any); the app saves them as JPEG.
public struct CameraPicker: UIViewControllerRepresentable {
    public enum Mode { case photo, video }
    let mode: Mode
    let onPhoto: (Data) -> Void
    let onVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(mode: Mode, onPhoto: @escaping (Data) -> Void, onVideo: @escaping (URL) -> Void) {
        self.mode = mode
        self.onPhoto = onPhoto
        self.onVideo = onVideo
    }

    public static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        p.cameraCaptureMode = mode == .video ? .video : .photo
        p.videoQuality = .typeHigh
        p.videoMaximumDuration = 30 * 60
        p.delegate = context.coordinator
        return p
    }

    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        public func imagePickerController(_ picker: UIImagePickerController,
                                          didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                // The picker's file lives in a temporary folder; copy it before it goes.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                    parent.onVideo(copy)
                }
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onPhoto(data)
            }
            parent.dismiss()
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Document scanner

/// The system document scanner. Pages come back as one PDF.
public struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(onScan: @escaping (Data) -> Void) { self.onScan = onScan }

    public static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController()
        c.delegate = context.coordinator
        return c
    }

    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                parent.onScan(Self.pdf(from: scan))
            }
            parent.dismiss()
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }

        static func pdf(from scan: VNDocumentCameraScan) -> Data {
            let first = scan.imageOfPage(at: 0)
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [:]
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size), format: format)
            return renderer.pdfData { ctx in
                for i in 0..<scan.pageCount {
                    let page = scan.imageOfPage(at: i)
                    let rect = CGRect(origin: .zero, size: page.size)
                    ctx.beginPage(withBounds: rect, pageInfo: [:])
                    page.draw(in: rect)
                }
            }
        }
    }
}

// MARK: - Photos

/// A photo or video from the photo picker, copied out of the picker's temporary file.
public struct PickedMedia: Transferable, Sendable {
    public let url: URL

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try PickedMedia(url: copyOut(received.file))
        }
        FileRepresentation(importedContentType: .image) { received in
            try PickedMedia(url: copyOut(received.file))
        }
    }

    static func copyOut(_ file: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: dest)
        return dest
    }
}

public extension ComposeModel {
    /// Adds the photos and videos picked in the photo picker, in the order picked.
    func addPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                if let picked = try await item.loadTransferable(type: PickedMedia.self) {
                    await addFile(picked.url, move: true)
                    try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent())
                }
            } catch {
                reportProblem("A photo or video could not be read from the library.")
            }
        }
    }
}

// MARK: - Files, paste, and the share sheet

/// Reads what another app hands over (share sheet, paste) into a submission: files are
/// copied in; plain text and web links go into the note.
public enum ItemProviderLoader {
    @MainActor
    public static func load(_ providers: [NSItemProvider], into model: ComposeModel) async {
        for p in providers {
            await loadOne(p, into: model)
        }
    }

    @MainActor
    static func loadOne(_ p: NSItemProvider, into model: ComposeModel) async {
        let types = p.registeredTypeIdentifiers.compactMap { UTType($0) }
        // A file: a photo, a video, a recording, a PDF, any other document.
        let fileType = types.first { $0.conforms(to: .movie) }
            ?? types.first { $0.conforms(to: .image) }
            ?? types.first { $0.conforms(to: .audio) }
            ?? types.first { $0.conforms(to: .pdf) }
            ?? types.first { $0.conforms(to: .data) && !$0.conforms(to: .text) && !$0.conforms(to: .url) }
        if let type = fileType {
            if let file = await loadFile(p, type: type) {
                await model.addFile(file, displayName: suggestedName(p, file: file, type: type), move: true)
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            } else if type.conforms(to: .image), let data = await loadImageData(p) {
                await model.addData(data, fileName: FileNaming.stamped("shared", ext: "jpg"))
            } else {
                model.reportProblem("Something you shared could not be read.")
            }
            return
        }
        // A link: a web address goes into the note; a file address is copied in.
        if types.contains(where: { $0.conforms(to: .url) }), let url = await loadURL(p) {
            if url.isFileURL {
                await copyFileURL(url, into: model)
            } else {
                model.appendText(url.absoluteString)
            }
            return
        }
        // Text goes into the note, as pasting does on the page.
        if types.contains(where: { $0.conforms(to: .text) }) {
            if let text = await loadText(p) {
                model.appendText(text)
            } else if let t = types.first(where: { $0.conforms(to: .text) }), let file = await loadFile(p, type: t) {
                await model.addFile(file, displayName: suggestedName(p, file: file, type: t), move: true)
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
        }
    }

    static func suggestedName(_ p: NSItemProvider, file: URL, type: UTType) -> String {
        let ext = file.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "") : file.pathExtension
        if let s = p.suggestedName, !s.isEmpty {
            return (s as NSString).pathExtension.isEmpty && !ext.isEmpty ? "\(s).\(ext)" : s
        }
        return file.lastPathComponent
    }

    /// Copies the provider's file out before the provider deletes it.
    static func loadFile(_ p: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            _ = p.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return cont.resume(returning: nil) }
                do {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let dest = dir.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    static func loadImageData(_ p: NSItemProvider) async -> Data? {
        guard p.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            _ = p.loadObject(ofClass: UIImage.self) { obj, _ in
                cont.resume(returning: (obj as? UIImage)?.jpegData(compressionQuality: 0.9))
            }
        }
    }

    static func loadURL(_ p: NSItemProvider) async -> URL? {
        guard p.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            _ = p.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }
    }

    static func loadText(_ p: NSItemProvider) async -> String? {
        guard p.canLoadObject(ofClass: String.self) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            _ = p.loadObject(ofClass: String.self) { s, _ in cont.resume(returning: s) }
        }
    }

    /// A file from the Files picker: open its security scope, copy it in, close the scope.
    @MainActor
    public static func copyFileURL(_ url: URL, into model: ComposeModel) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        await model.addFile(url, move: false)
    }
}

// MARK: - Voice note

/// Records a voice note as AAC in an .m4a file.
@MainActor
public final class VoiceRecorder: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var denied = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?

    public override init() {}

    public func start() async {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            denied = true
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(FileNaming.stamped("voice-note", ext: "m4a"))
            let r = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            guard r.record() else { return }
            recorder = r
            url = file
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
            }
        } catch {
            isRecording = false
        }
    }

    /// Stops and returns the recording's file.
    public func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { url = nil }
        return url
    }

    public func cancel() {
        if let u = stop() { try? FileManager.default.removeItem(at: u) }
    }
}

public struct VoiceNoteSheet: View {
    @StateObject private var recorder = VoiceRecorder()
    let onDone: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(onDone: @escaping (URL) -> Void) { self.onDone = onDone }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Text(timeString(recorder.elapsed))
                    .font(.system(size: 54, weight: .light, design: .monospaced))
                    .foregroundStyle(GSRTheme.navy)
                    .accessibilityLabel("Recorded \(Int(recorder.elapsed)) seconds")
                if recorder.denied {
                    Text("The app is not allowed to use the microphone. Turn it on in Settings, under GSR.")
                        .font(GSRTheme.serif(.body))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(GSRTheme.rust)
                }
                Button {
                    if recorder.isRecording {
                        if let url = recorder.stop() { onDone(url) }
                        dismiss()
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop and add" : "Record", systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .buttonStyle(GSRButtonStyle())
                .padding(.horizontal, 32)
                Text("Say as little as you like. The recording stays on this phone until you press Send.")
                    .font(GSRTheme.serif(.footnote, italic: true))
                    .foregroundStyle(GSRTheme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .background(GSRTheme.paper2.ignoresSafeArea())
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Web pages

/// Shows one of the site's pages inside the app.
public struct SafariView: UIViewControllerRepresentable {
    let url: URL
    public init(url: URL) { self.url = url }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(red: 0xB1 / 255, green: 0x4A / 255, blue: 0x37 / 255, alpha: 1)
        vc.dismissButtonStyle = .done
        return vc
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// A URL that can drive `.sheet(item:)`.
public struct WebPage: Identifiable, Hashable {
    public let url: URL
    public var id: String { url.absoluteString }
    public init(_ url: URL) { self.url = url }
}
#endif

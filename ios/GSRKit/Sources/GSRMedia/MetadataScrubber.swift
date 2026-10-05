#if canImport(ImageIO) && canImport(AVFoundation) && canImport(UniformTypeIdentifiers)
import AVFoundation
import Foundation
import GSRKit
import ImageIO
import UniformTypeIdentifiers

/// Removes hidden details from photos and videos before they upload: location, the
/// phone's make and model, the camera software, the lens, the time taken, and anything
/// else the file carries beyond the picture. Photos keep their orientation so they still
/// display the right way up.
///
/// Every cleaned file is read back and checked. If anything identifying is still there,
/// the clean fails and the uploader holds the file back for the sender to decide.
public struct MediaCleaner: ItemPreparer {
    public init() {}

    public func prepare(_ item: SubmissionItem, source: URL, folder: URL) async throws -> PreparedFile {
        switch item.kind {
        case .photo:
            let r = try MetadataScrubber.cleanImage(at: source, into: folder, baseName: "clean-" + item.storedName)
            return PreparedFile(name: r.url.lastPathComponent,
                                contentType: r.reencodedAsJPEG ? "image/jpeg" : nil,
                                displayName: r.reencodedAsJPEG ? MetadataScrubber.renamed(item.displayName, ext: "jpg") : nil)
        case .video:
            let out = folder.appendingPathComponent("clean-" + item.storedName)
            let type = try await MetadataScrubber.cleanVideo(at: source, to: out)
            let ext = type == .mp4 ? "mp4" : "mov"
            let changed = (item.displayName as NSString).pathExtension.lowercased() != ext
            return PreparedFile(name: out.lastPathComponent,
                                contentType: changed ? (type == .mp4 ? "video/mp4" : "video/quicktime") : nil,
                                displayName: changed ? MetadataScrubber.renamed(item.displayName, ext: ext) : nil)
        default:
            throw MetadataScrubber.Failure.unsupported
        }
    }
}

public enum MetadataScrubber {
    public enum Failure: Error, Equatable {
        case unreadable
        case unsupported
        case writeFailed
        case exportFailed(String)
        /// The cleaned copy still carried something identifying. The list says what.
        case stillIdentifying([String])
    }

    // MARK: Photos

    public struct ImageResult {
        public var url: URL
        public var reencodedAsJPEG: Bool
    }

    /// Writes a cleaned copy of the image at `source` into `folder`.
    ///
    /// First tries a lossless copy with all metadata replaced by the orientation alone.
    /// If that fails, or the copy still carries anything identifying, re-encodes the
    /// pixels in the same format, and as JPEG when the phone cannot write that format.
    public static func cleanImage(at source: URL, into folder: URL, baseName: String) throws -> ImageResult {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let type = CGImageSourceGetType(src) else { throw Failure.unreadable }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { throw Failure.unreadable }
        let out = folder.appendingPathComponent(baseName)
        try? FileManager.default.removeItem(at: out)

        // 1. Lossless: same bytes for the picture, new metadata.
        if count == 1, copyWithoutMetadata(src, type: type, to: out), identifyingImageKeys(at: out).isEmpty {
            return ImageResult(url: out, reencodedAsJPEG: false)
        }
        try? FileManager.default.removeItem(at: out)

        // 2. Re-encode in the same format.
        if reencode(src, count: count, type: type, to: out), identifyingImageKeys(at: out).isEmpty {
            return ImageResult(url: out, reencodedAsJPEG: false)
        }
        try? FileManager.default.removeItem(at: out)

        // 3. Re-encode as JPEG (for example HEIC on a device that cannot write HEIC).
        let jpgURL = folder.appendingPathComponent(renamed(baseName, ext: "jpg"))
        try? FileManager.default.removeItem(at: jpgURL)
        guard reencode(src, count: 1, type: UTType.jpeg.identifier as CFString, to: jpgURL) else { throw Failure.writeFailed }
        let left = identifyingImageKeys(at: jpgURL)
        guard left.isEmpty else {
            try? FileManager.default.removeItem(at: jpgURL)
            throw Failure.stillIdentifying(left)
        }
        return ImageResult(url: jpgURL, reencodedAsJPEG: true)
    }

    static func orientation(_ src: CGImageSource, _ index: Int) -> Int? {
        let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        return (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue
    }

    static func copyWithoutMetadata(_ src: CGImageSource, type: CFString, to out: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else { return false }
        let meta = CGImageMetadataCreateMutable()
        if let o = orientation(src, 0) {
            _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary,
                                                             kCGImagePropertyTIFFOrientation, NSNumber(value: o))
        }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: meta,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true,
        ]
        return CGImageDestinationCopyImageSource(dest, src, options as CFDictionary, nil)
    }

    static func reencode(_ src: CGImageSource, count: Int, type: CFString, to out: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type, count, nil) else { return false }
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(src, i, nil) else { return false }
            var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
            if let o = orientation(src, i) { props[kCGImagePropertyOrientation] = o }
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
        }
        return CGImageDestinationFinalize(dest)
    }

    /// Identifying metadata still in the image file, as "Dictionary.Key" names. Empty when clean.
    public static func identifyingImageKeys(at url: URL) -> [String] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ["unreadable"] }
        var found: [String] = []
        for i in 0..<max(1, CGImageSourceGetCount(src)) {
            guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] else { continue }
            if props[kCGImagePropertyGPSDictionary] != nil { found.append("GPS") }
            if props[kCGImagePropertyMakerAppleDictionary] != nil { found.append("MakerApple") }
            if props[kCGImagePropertyIPTCDictionary] != nil { found.append("IPTC") }
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                for k in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware,
                          kCGImagePropertyTIFFHostComputer, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFDateTime]
                where tiff[k] != nil {
                    found.append("TIFF.\(k)")
                }
            }
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                for k in [kCGImagePropertyExifLensMake, kCGImagePropertyExifLensModel, kCGImagePropertyExifBodySerialNumber,
                          kCGImagePropertyExifCameraOwnerName, kCGImagePropertyExifLensSerialNumber,
                          kCGImagePropertyExifUserComment, kCGImagePropertyExifDateTimeOriginal,
                          kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifSubsecTimeOriginal]
                where exif[k] != nil {
                    found.append("Exif.\(k)")
                }
            }
        }
        if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
           let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] {
            for tag in tags {
                let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
                if ["xmp", "photoshop", "dc", "Iptc4xmpCore", "aux", "exifEX"].contains(prefix) {
                    found.append("XMP.\(prefix)")
                }
            }
        }
        return Array(Set(found)).sorted()
    }

    // MARK: Videos

    /// Writes a copy of the video at `source` with no metadata: no location, make, model,
    /// software, or creation date. The picture and sound are copied sample for sample, not
    /// re-encoded, so quality and size stay the same.
    ///
    /// The main path rewrites the movie with AVAssetReader and AVAssetWriter, which write only
    /// what they are given. If that cannot handle the file, the passthrough export with
    /// Apple's sharing filter is tried. Either way the result is read back and checked, and
    /// the clean fails rather than hand back a file that still says where or on what it was shot.
    @discardableResult
    public static func cleanVideo(at source: URL, to out: URL) async throws -> AVFileType {
        let fileType: AVFileType = source.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        var lastError: Error = Failure.unsupported
        for attempt in [remux, exportForSharing] {
            try? FileManager.default.removeItem(at: out)
            do {
                try await attempt(source, out, fileType)
                let left = try await identifyingVideoKeys(at: out)
                if left.isEmpty { return fileType }
                lastError = Failure.stillIdentifying(left)
            } catch {
                lastError = error
            }
        }
        try? FileManager.default.removeItem(at: out)
        throw lastError
    }

    /// Copies the video and audio tracks into a new movie that carries no metadata.
    /// Other tracks (timed metadata, which can include location) are left out.
    static func remux(_ source: URL, _ out: URL, _ fileType: AVFileType) async throws {
        let asset = AVURLAsset(url: source)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: out, fileType: fileType)
        writer.metadata = []
        writer.shouldOptimizeForNetworkUse = false

        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for track in try await asset.load(.tracks) {
            let type = track.mediaType
            guard type == .video || type == .audio else { continue }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw Failure.unsupported }
            reader.add(output)
            let formats = try await track.load(.formatDescriptions)
            let input = AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: formats.first)
            input.expectsMediaDataInRealTime = false
            if type == .video {
                // Keep the picture the right way up.
                input.transform = try await track.load(.preferredTransform)
            }
            guard writer.canAdd(input) else { throw Failure.unsupported }
            writer.add(input)
            pairs.append((output, input))
        }
        guard pairs.contains(where: { $0.1.mediaType == .video }) else { throw Failure.unsupported }
        guard reader.startReading() else {
            throw Failure.exportFailed(reader.error.map { String(describing: $0) } ?? "reader did not start")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw Failure.exportFailed(writer.error.map { String(describing: $0) } ?? "writer did not start")
        }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            for (index, pair) in pairs.enumerated() {
                let (output, input) = pair
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        let queue = DispatchQueue(label: "gsr.media.remux.\(index)")
                        let state = RemuxState()
                        input.requestMediaDataWhenReady(on: queue) {
                            guard !state.finished else { return }
                            while input.isReadyForMoreMediaData {
                                if let buffer = output.copyNextSampleBuffer(), input.append(buffer) {
                                    continue
                                }
                                state.finished = true
                                input.markAsFinished()
                                cont.resume()
                                return
                            }
                        }
                    }
                }
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw Failure.exportFailed(reader.error.map { String(describing: $0) } ?? "reading failed")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.exportFailed(writer.error.map { String(describing: $0) } ?? "writing failed")
        }
    }

    /// Touched only on the remux queue for its track.
    private final class RemuxState: @unchecked Sendable {
        var finished = false
    }

    /// The fallback: passthrough export with Apple's sharing filter and no movie metadata.
    static func exportForSharing(_ source: URL, _ out: URL, _ wanted: AVFileType) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.unsupported
        }
        let fileType = session.supportedFileTypes.contains(wanted) ? wanted : .mov
        session.metadataItemFilter = AVMetadataItemFilter.forSharing()
        session.metadata = []
        session.shouldOptimizeForNetworkUse = false
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                try await session.export(to: out, as: fileType)
            } catch {
                throw Failure.exportFailed(String(describing: error))
            }
        } else {
            session.outputURL = out
            session.outputFileType = fileType
            await session.export()
            guard session.status == .completed else {
                throw Failure.exportFailed(session.error.map { String(describing: $0) } ?? "status \(session.status.rawValue)")
            }
        }
    }

    static let identifyingVideoKeyWords = ["location", "iso6709", "make", "model", "software", "creationdate",
                                           "author", "artist", "copyright", "comment", "description", "©xyz", "©mak", "©mod", "©swr"]

    /// Identifying metadata still in the video file, by identifier. Empty when clean.
    public static func identifyingVideoKeys(at url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        var items = try await asset.load(.metadata)
        for format in try await asset.load(.availableMetadataFormats) {
            items += try await asset.loadMetadata(for: format)
        }
        for track in try await asset.load(.tracks) {
            items += try await track.load(.metadata)
        }
        var found: [String] = []
        for item in items {
            let keyText = item.key.map { String(describing: $0) } ?? ""
            let id = (item.identifier?.rawValue ?? "") + " " + (item.commonKey?.rawValue ?? "") + " " + keyText
            let lower = id.lowercased()
            if identifyingVideoKeyWords.contains(where: { lower.contains($0) }) { found.append(id.trimmingCharacters(in: .whitespaces)) }
        }
        return Array(Set(found)).sorted()
    }

    // MARK: Names

    /// "IMG_0001.HEIC" → "IMG_0001.jpg".
    public static func renamed(_ name: String, ext: String) -> String {
        var stem = (name as NSString).deletingPathExtension
        // ".HEIC" is all extension: Foundation reads it as a hidden file with no extension.
        if stem.hasPrefix("."), !stem.dropFirst().contains(".") { stem = "" }
        return (stem.isEmpty ? "file" : stem) + "." + ext
    }
}
#endif

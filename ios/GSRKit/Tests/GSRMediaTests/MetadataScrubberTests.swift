#if canImport(ImageIO) && canImport(AVFoundation) && canImport(UniformTypeIdentifiers)
import AVFoundation
import CoreGraphics
import CoreVideo
import GSRKit
@testable import GSRMedia
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Builds photos and videos that carry a location, a make and model, and a capture time,
/// cleans them, and reads the result back.
final class MetadataScrubberTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gsr-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pixels(width: Int = 64, height: Int = 48) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.18, blue: 0.29, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.69, green: 0.29, blue: 0.22, alpha: 1))
        ctx.fill(CGRect(x: 8, y: 8, width: 20, height: 12))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// A photo that says where, when, and on what it was taken.
    private func taggedImage(_ type: UTType, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 43.4332, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 71.5947, kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 17 Pro",
                kCGImagePropertyTIFFSoftware: "26.5",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "iPhone 17 Pro back camera 6.86mm f/1.78",
                kCGImagePropertyExifDateTimeOriginal: "2026:10:04 12:00:00",
            ],
        ]
        CGImageDestinationAddImage(dest, try pixels(), props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func props(_ url: URL) throws -> [CFString: Any] {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    }

    private func check(_ type: UTType, _ name: String) throws {
        let original = try taggedImage(type, name: name)
        XCTAssertTrue(MetadataScrubber.identifyingImageKeys(at: original).contains("GPS"), "test photo should start tagged")
        let r = try MetadataScrubber.cleanImage(at: original, into: dir, baseName: "clean-" + name)
        XCTAssertEqual(MetadataScrubber.identifyingImageKeys(at: r.url), [], "\(type)")
        let p = try props(r.url)
        XCTAssertNil(p[kCGImagePropertyGPSDictionary])
        XCTAssertEqual((p[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6, "still the right way up")
        XCTAssertEqual((p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 64)
        XCTAssertEqual((p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 48)
    }

    func testJPEG() throws { try check(.jpeg, "a.jpg") }
    func testPNG() throws { try check(.png, "a.png") }

    func testHEICWhenThisMachineCanWriteIt() throws {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        try XCTSkipUnless(writable.contains(UTType.heic.identifier), "no HEIC encoder here")
        try check(.heic, "a.heic")
    }

    func testCleanerReportsFormatChangeOnlyWhenItHappens() async throws {
        let original = try taggedImage(.jpeg, name: "IMG_0001.JPG")
        let item = SubmissionItem(displayName: "IMG_0001.JPG", storedName: "IMG_0001.JPG", contentType: "image/jpeg", kind: .photo, size: 1)
        let p = try await MediaCleaner().prepare(item, source: original, folder: dir)
        XCTAssertNil(p.contentType)
        XCTAssertNil(p.displayName)
        XCTAssertEqual(MetadataScrubber.identifyingImageKeys(at: dir.appendingPathComponent(p.name)), [])
    }

    func testDocumentsAreNotTouched() async throws {
        let item = SubmissionItem(displayName: "memo.pdf", storedName: "memo.pdf", contentType: "application/pdf", kind: .document, size: 1)
        do {
            _ = try await MediaCleaner().prepare(item, source: dir.appendingPathComponent("memo.pdf"), folder: dir)
            XCTFail("documents are not cleaned")
        } catch {}
    }

    func testRenamed() {
        XCTAssertEqual(MetadataScrubber.renamed("IMG_0001.HEIC", ext: "jpg"), "IMG_0001.jpg")
        XCTAssertEqual(MetadataScrubber.renamed(".HEIC", ext: "jpg"), "file.jpg")
    }

    // MARK: Video

    private func taggedMovie() async throws -> URL {
        let url = dir.appendingPathComponent("tagged.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.dataType = kCMMetadataBaseDataType_UTF8 as String
            return m
        }
        writer.metadata = [
            item(.quickTimeMetadataLocationISO6709, "+43.4332-071.5947+100.000/"),
            item(.quickTimeMetadataMake, "Apple"),
            item(.quickTimeMetadataModel, "iPhone 17 Pro"),
            item(.quickTimeMetadataSoftware, "26.5"),
            item(.quickTimeMetadataCreationDate, "2026-10-04T12:00:00-0400"),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.jpeg, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), String(describing: writer.error))
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        for i in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var pb: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pb)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(20 * i), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, String(describing: writer.error))
        return url
    }

    func testVideoLosesLocationAndDevice() async throws {
        let original = try await taggedMovie()
        let before = try await MetadataScrubber.identifyingVideoKeys(at: original)
        XCTAssertFalse(before.isEmpty, "test movie should start tagged")
        XCTAssertTrue(before.contains { $0.lowercased().contains("location") }, "\(before)")
        let out = dir.appendingPathComponent("clean.mov")
        let type = try await MetadataScrubber.cleanVideo(at: original, to: out)
        XCTAssertEqual(type, .mov)
        let after = try await MetadataScrubber.identifyingVideoKeys(at: out)
        XCTAssertEqual(after, [])
        let asset = AVURLAsset(url: out)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1, "the picture survives")
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.5)
    }
}
#endif

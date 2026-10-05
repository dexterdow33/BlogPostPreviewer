// swift-tools-version:5.9
// GSRKit: the parts of the Granite State Report app that are not screens.
//
//   GSRKit    The GSR Drop Box protocol, the outbox on disk, the upload engine, the
//             story feed, and the form definitions read off the live pages.
//             Plain Foundation; builds and tests on Linux as well as Apple platforms.
//   GSRMedia  Removes location and device details from photos and videos (ImageIO,
//             AVFoundation). Apple platforms only; empty elsewhere.
//   GSRUI     SwiftUI screens shared by the app and its share extension. iOS only;
//             empty elsewhere.
import PackageDescription

let package = Package(
    name: "GSRKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GSRKit", targets: ["GSRKit"]),
        .library(name: "GSRMedia", targets: ["GSRMedia"]),
        .library(name: "GSRUI", targets: ["GSRUI"]),
    ],
    targets: [
        .target(name: "GSRKit"),
        .target(name: "GSRMedia", dependencies: ["GSRKit"]),
        .target(name: "GSRUI", dependencies: ["GSRKit", "GSRMedia"]),
        .testTarget(name: "GSRKitTests", dependencies: ["GSRKit"]),
        .testTarget(name: "GSRMediaTests", dependencies: ["GSRMedia"]),
    ]
)

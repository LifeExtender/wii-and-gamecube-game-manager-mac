// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiiKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "WiiKit", targets: ["WiiKit"])],
    targets: [
        .target(name: "WiiKit"),
        .testTarget(name: "WiiKitTests", dependencies: ["WiiKit"]),
    ],
    swiftLanguageModes: [.v5]
)

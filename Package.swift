// swift-tools-version: 6.0
import PackageDescription

// Dependency rule (clean architecture): BeadsCore depends on nothing.
// BeadsData and BeadsPresentation depend only on BeadsCore.
// BeadsViewerApp is the composition root and the only target that sees everything.
let package = Package(
    name: "BeadsViewer",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BeadsViewer", targets: ["BeadsViewer"]),
    ],
    targets: [
        .target(name: "BeadsCore"),
        .target(name: "BeadsData", dependencies: ["BeadsCore"]),
        .target(name: "BeadsPresentation", dependencies: ["BeadsCore"]),
        .executableTarget(
            name: "BeadsViewer",
            dependencies: ["BeadsCore", "BeadsData", "BeadsPresentation"]
        ),
        .testTarget(name: "BeadsCoreTests", dependencies: ["BeadsCore"]),
        .testTarget(name: "BeadsDataTests", dependencies: ["BeadsData"]),
        .testTarget(name: "BeadsPresentationTests", dependencies: ["BeadsPresentation"]),
    ]
)

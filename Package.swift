// swift-tools-version: 6.0
import PackageDescription

// Dependency rule (clean architecture): BeadsCore depends on nothing.
// BeadsData and BeadsPresentation depend only on BeadsCore.
// BeadyApp is the composition root and the only target that sees everything.
//
// Every target with on-screen text carries its own String Catalog (Localizable.xcstrings): the
// modules look their strings up in `Bundle.module`, and scripts/bundle.sh ships each compiled
// catalog inside the app. docs/LOCALIZATION.md says how to add or improve a translation.
let package = Package(
    name: "Beady",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Beady", targets: ["Beady"]),
    ],
    targets: [
        .target(name: "BeadsCore", resources: [.process("Localizable.xcstrings")]),
        .target(name: "BeadsData", dependencies: ["BeadsCore"], resources: [.process("Localizable.xcstrings")]),
        .target(name: "BeadsPresentation", dependencies: ["BeadsCore"], resources: [.process("Localizable.xcstrings")]),
        .executableTarget(
            name: "Beady",
            dependencies: ["BeadsCore", "BeadsData", "BeadsPresentation"],
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(name: "BeadsCoreTests", dependencies: ["BeadsCore"]),
        .testTarget(name: "BeadsDataTests", dependencies: ["BeadsData"]),
        .testTarget(name: "BeadsPresentationTests", dependencies: ["BeadsPresentation"]),
    ]
)

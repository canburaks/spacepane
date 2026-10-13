// swift-tools-version: 6.2
import PackageDescription

// Swift 6 complete checking, explicitly nonisolated shared logic, extension-safe APIs.
// The UI target annotates its AppKit entry points with @MainActor.
let sharedSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .unsafeFlags(["-application-extension", "-default-isolation", "nonisolated"])
]

let package = Package(
    name: "PreviewCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PreviewContracts", targets: ["PreviewContracts"]),
        .library(name: "PreviewFileAccess", targets: ["PreviewFileAccess"]),
        .library(name: "PreviewCore", targets: ["PreviewCore"]),
        .library(name: "PreviewCADFormats", targets: ["PreviewCADFormats"]),
        .library(name: "PreviewFormats", targets: ["PreviewFormats"]),
        .library(name: "PreviewPreferences", targets: ["PreviewPreferences"]),
        .library(name: "PreviewRenderers", targets: ["PreviewRenderers"]),
        .library(name: "PreviewThumbnails", targets: ["PreviewThumbnails"])
    ],
    targets: [
        .target(name: "PreviewContracts", resources: [.process("Resources")], swiftSettings: sharedSettings),
        .target(name: "PreviewFileAccess", dependencies: ["PreviewContracts"], swiftSettings: sharedSettings),
        .target(name: "PreviewCore", dependencies: ["PreviewContracts", "PreviewFileAccess"], swiftSettings: sharedSettings),
        .target(name: "SQLiteSafetyShim", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fapplication-extension"] )], linkerSettings: [.linkedLibrary("sqlite3")]),
        // Narrow typed bridge to the system libbz2 streaming decoder (decision 013).
        .target(name: "BZip2Shim", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fapplication-extension", "-fms-extensions"])], linkerSettings: [.linkedLibrary("bz2")]),
        .target(name: "PreviewCADFormats", dependencies: ["PreviewContracts"], swiftSettings: sharedSettings),
        .target(name: "PreviewFormats", dependencies: ["PreviewContracts", "PreviewFileAccess", "SQLiteSafetyShim", "BZip2Shim"], swiftSettings: sharedSettings),
        .target(name: "PreviewPreferences", dependencies: ["PreviewContracts"], swiftSettings: sharedSettings),
        .target(name: "PreviewRenderers", dependencies: ["PreviewContracts"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources")], swiftSettings: sharedSettings),
        // Content thumbnails draw with Core Graphics, Core Text and ImageIO only: no AppKit, no format
        // adapters. The host injects the adapter registrations, so the target stays format-independent.
        .target(name: "PreviewThumbnails", dependencies: ["PreviewContracts", "PreviewCore", "PreviewPreferences"], swiftSettings: sharedSettings),
        // Shared synthetic fixtures and bounded test doubles; never a shipping product or dependency.
        .target(name: "PreviewTestSupport", dependencies: ["PreviewContracts"], path: "Tests/PreviewTestSupport", swiftSettings: sharedSettings),
        .testTarget(name: "PreviewFileAccessTests", dependencies: ["PreviewFileAccess", "PreviewContracts"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewCoreTests", dependencies: ["PreviewTestSupport", "PreviewCore", "PreviewFormats", "PreviewCADFormats", "PreviewContracts"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewCADFormatsTests", dependencies: ["PreviewTestSupport", "PreviewCADFormats", "PreviewCore", "PreviewContracts"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewFormatsTests", dependencies: ["PreviewTestSupport", "PreviewFormats", "PreviewContracts"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewPreferencesTests", dependencies: ["PreviewTestSupport", "PreviewPreferences", "PreviewContracts"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewRenderersTests", dependencies: ["PreviewRenderers", "PreviewContracts", "PreviewCore", "PreviewFormats", "PreviewThumbnails", "PreviewTestSupport"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewThumbnailsTests", dependencies: ["PreviewTestSupport", "PreviewThumbnails", "PreviewFormats", "PreviewCore", "PreviewPreferences", "PreviewContracts"], swiftSettings: sharedSettings),
        .testTarget(name: "PreviewDiagramsTests", dependencies: ["PreviewTestSupport", "PreviewCore", "PreviewFormats", "PreviewRenderers", "PreviewContracts"], swiftSettings: sharedSettings)
    ],
    swiftLanguageModes: [.v6]
)

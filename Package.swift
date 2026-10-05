// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rowboat",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Rowboat", targets: ["Rowboat"]),
        .library(name: "RowboatCore", targets: ["RowboatCore"]),
    ],
    targets: [
        // Pure logic, no AppKit: label generation, fuzzy search, hint layout.
        .target(name: "RowboatCore"),
        // The app: accessibility, overlay, key capture, modes, settings.
        .executableTarget(
            name: "Rowboat",
            dependencies: ["RowboatCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(name: "RowboatCoreTests", dependencies: ["RowboatCore"]),
    ]
)

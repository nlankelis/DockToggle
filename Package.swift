// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockToggle",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DockToggle", targets: ["DockToggle"])],
    targets: [
        .target(name: "DockToggleCore"),
        .executableTarget(name: "DockToggle", dependencies: ["DockToggleCore"]),
        // A dependency-free test executable also runs on Command Line Tools
        // installations whose XCTest/Swift Testing runtime is incomplete.
        .executableTarget(name: "DockToggleTests", dependencies: ["DockToggleCore"], path: "Tests/DockToggleTests")
    ],
    swiftLanguageModes: [.v5]
)

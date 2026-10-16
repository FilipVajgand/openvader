// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenVader",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VaderKit", targets: ["VaderKit"]),
        .executable(name: "vaderctl", targets: ["vaderctl"]),
        .executable(name: "OpenVader", targets: ["OpenVader"]),
    ],
    targets: [
        .target(
            name: "VaderKit",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "vaderctl",
            dependencies: ["VaderKit"]
        ),
        .executableTarget(
            name: "OpenVader",
            dependencies: ["VaderKit"]
        ),
        .testTarget(
            name: "VaderKitTests",
            dependencies: ["VaderKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)

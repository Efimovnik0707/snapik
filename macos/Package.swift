// swift-tools-version: 5.9
import PackageDescription

var targets: [Target] = [
    .target(
        name: "SnapBriefCore",
        path: "Sources/SnapBriefCore"
    ),
    .testTarget(
        name: "SnapBriefCoreTests",
        dependencies: ["SnapBriefCore"],
        path: "Tests/SnapBriefCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "SnapBriefCore", targets: ["SnapBriefCore"]),
]

#if os(macOS)
targets += [
    .executableTarget(
        name: "SnapBriefMac",
        dependencies: ["SnapBriefCore"],
        path: "Sources/SnapBriefMac",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("Carbon"),
            .linkedFramework("ScreenCaptureKit"),
            .linkedFramework("ServiceManagement"),
        ]
    ),
    .testTarget(
        name: "SnapBriefMacTests",
        dependencies: ["SnapBriefMac", "SnapBriefCore"],
        path: "Tests/SnapBriefMacTests"
    ),
]
products += [.executable(name: "SnapBriefMac", targets: ["SnapBriefMac"])]
#endif

let package = Package(
    name: "SnapBrief",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)

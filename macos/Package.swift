// swift-tools-version: 5.9
import PackageDescription

var targets: [Target] = [
    .target(
        name: "SnapikCore",
        path: "Sources/SnapikCore"
    ),
    .testTarget(
        name: "SnapikCoreTests",
        dependencies: ["SnapikCore"],
        path: "Tests/SnapikCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "SnapikCore", targets: ["SnapikCore"]),
]

#if os(macOS)
targets += [
    .executableTarget(
        name: "SnapikMac",
        dependencies: ["SnapikCore"],
        path: "Sources/SnapikMac",
        resources: [
            .copy("Resources/Audio/camera-shutter.wav"),
            .copy("Resources/Audio/camera-dial-click.wav"),
        ],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("Carbon"),
            .linkedFramework("ScreenCaptureKit"),
            .linkedFramework("ServiceManagement"),
            .linkedFramework("UserNotifications"),
        ]
    ),
    .testTarget(
        name: "SnapikMacTests",
        dependencies: ["SnapikMac", "SnapikCore"],
        path: "Tests/SnapikMacTests"
    ),
]
products += [.executable(name: "SnapikMac", targets: ["SnapikMac"])]
#endif

let package = Package(
    name: "Snapik",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)

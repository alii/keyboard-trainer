// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardTrainer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeyboardTrainer",
            path: "Sources/KeyboardTrainer",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        )
    ]
)

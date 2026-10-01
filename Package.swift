// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Presentools",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "presentools",
            path: "Sources/presentools"
        )
    ]
)

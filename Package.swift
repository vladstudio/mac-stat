// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stat",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../mac-app-kit"),
    ],
    targets: [
        .executableTarget(
            name: "Stat",
            dependencies: [.product(name: "MacAppKit", package: "mac-app-kit")],
            path: "app/Stat",
            exclude: ["Info.plist"]
        )
    ]
)

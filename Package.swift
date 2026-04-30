// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stat",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../app-kit"),
    ],
    targets: [
        .systemLibrary(
            name: "CIOHIDPrivate",
            path: "app/CIOHIDPrivate"
        ),
        .executableTarget(
            name: "Stat",
            dependencies: [.product(name: "MacAppKit", package: "app-kit"), "CIOHIDPrivate"],
            path: "app/Stat",
            exclude: ["Info.plist"]
        ),
        .executableTarget(
            name: "TempTest",
            dependencies: ["CIOHIDPrivate"],
            path: "app/TempTest"
        ),
    ]
)

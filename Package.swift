// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "mango",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mango", targets: ["MangoApp"]),
        .executable(name: "mmsg", targets: ["mmsg"]),
        .library(name: "Mango", targets: ["Mango"]),
        .library(name: "Port", targets: ["Port"]),
    ],
    targets: [
        // Private macOS APIs (_AXUIElementGetWindow, SkyLight read-only calls).
        .target(
            name: "MangoPrivate",
            path: "Sources/MangoPrivate",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("SkyLight"),
                .linkedFramework("MultitouchSupport"),
                .linkedFramework("Carbon"),
            ]
        ),
        // mango's code: what mango is (its server, clients, monitors, layouts, config, IPC),
        // in Sources/Mango, and nothing else. The boundary it calls where mango calls wlroots
        // (WindowSystem, PortHooks, ConfigPort, …) is declared beside it, in Sources/Boundary,
        // and built in the same module (its types use mango's: Client, Monitor, Config).
        .target(
            name: "Mango",
            path: "Sources",
            exclude: ["Port", "MangoApp", "MangoPrivate", "Mango/mmsg"],
            sources: ["Mango", "Boundary"]
        ),
        // The port: macOS where wlroots stands (Port/macOS) and the port's extensions
        // (Port/Extensions).
        .target(
            name: "Port",
            dependencies: ["Mango", "MangoPrivate"],
            path: "Sources/Port",
            exclude: ["mmsg"]
        ),
        // mmsg's macOS extras (service, logs, reload, binds), the port's.
        .target(
            name: "MmsgPort",
            path: "Sources/Port/mmsg"
        ),
        .executableTarget(
            name: "MangoApp",
            dependencies: ["Mango", "Port"],
            path: "Sources/MangoApp"
        ),
        .executableTarget(
            name: "mmsg",
            dependencies: ["MmsgPort"],
            path: "Sources/Mango/mmsg"
        ),
        .testTarget(
            name: "MangoCoreTests",
            dependencies: ["Mango", "Port"],
            path: "Tests/MangoCoreTests"
        ),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SonyControl",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "SonyControl", targets: ["SonyControl"]),
        .executable(name: "sonyctl", targets: ["sonyctl"]),
    ],
    targets: [
        .target(
            name: "SonyKit",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .executableTarget(name: "SonyControl", dependencies: ["SonyKit"]),
        .executableTarget(name: "sonyctl", dependencies: ["SonyKit"]),
    ]
)

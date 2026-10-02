// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacBar", targets: ["MacBar"])],
    targets: [
        .target(name: "TouchBarBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(name: "MacBar", dependencies: ["TouchBarBridge"], resources: [.copy("Assets")]),
        .testTarget(name: "MacBarTests", dependencies: ["MacBar"])
    ]
)

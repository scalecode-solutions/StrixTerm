// swift-tools-version: 6.0

import PackageDescription
import Foundation

#if os(Linux) || os(Windows)
let platformExcludes = ["Renderer", "Platform", "Input", "Accessibility", "Search"]
#else
let platformExcludes: [String] = []
#endif

let package = Package(
    name: "StrixTerm",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "StrixTermCore", targets: ["StrixTermCore"]),
        .library(name: "StrixTermConfig", targets: ["StrixTermConfig"]),
        .library(name: "StrixTermProcess", targets: ["StrixTermProcess"]),
        .library(name: "StrixTermUI", targets: ["StrixTermUI"]),
        .library(name: "StrixTerm", targets: ["StrixTerm"]),
        .executable(name: "StrixTermApp", targets: ["StrixTermApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        .target(
            name: "StrixTermCore",
            dependencies: []
        ),
        .target(
            name: "StrixTermConfig",
            dependencies: ["StrixTermCore"]
        ),
        .target(
            name: "StrixTermProcess",
            dependencies: ["StrixTermCore"]
        ),
        .target(
            name: "StrixTermUI",
            dependencies: ["StrixTermCore", "StrixTermConfig"],
            exclude: platformExcludes,
            resources: [
                .process("Renderer/Shaders.metal")
            ]
        ),
        .target(
            name: "StrixTerm",
            dependencies: ["StrixTermCore", "StrixTermUI", "StrixTermProcess", "StrixTermConfig"]
        ),
        .executableTarget(
            name: "StrixTermApp",
            dependencies: ["StrixTermCore", "StrixTermUI", "StrixTermProcess", "StrixTermConfig"]
        ),
        .testTarget(
            name: "StrixTermCoreTests",
            dependencies: ["StrixTermCore"]
        ),
        .testTarget(
            name: "StrixTermProcessTests",
            dependencies: ["StrixTermProcess"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

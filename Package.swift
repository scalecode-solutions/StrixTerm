// swift-tools-version: 6.0

import PackageDescription
import Foundation

#if os(Linux) || os(Windows)
let platformExcludes = ["Renderer", "Platform", "Input", "Accessibility", "Search"]
#else
let platformExcludes: [String] = []
#endif

let package = Package(
    name: "FredTerm",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "FredTermCore", targets: ["FredTermCore"]),
        .library(name: "FredTermConfig", targets: ["FredTermConfig"]),
        .library(name: "FredTermProcess", targets: ["FredTermProcess"]),
        .library(name: "FredTermUI", targets: ["FredTermUI"]),
        .library(name: "FredTerm", targets: ["FredTerm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        .target(
            name: "FredTermCore",
            dependencies: []
        ),
        .target(
            name: "FredTermConfig",
            dependencies: ["FredTermCore"]
        ),
        .target(
            name: "FredTermProcess",
            dependencies: ["FredTermCore"]
        ),
        .target(
            name: "FredTermUI",
            dependencies: ["FredTermCore", "FredTermConfig"],
            exclude: platformExcludes,
            resources: [
                .process("Renderer/Shaders.metal")
            ]
        ),
        .target(
            name: "FredTerm",
            dependencies: ["FredTermCore", "FredTermUI", "FredTermProcess", "FredTermConfig"]
        ),
        .testTarget(
            name: "FredTermCoreTests",
            dependencies: ["FredTermCore"]
        ),
        .testTarget(
            name: "FredTermProcessTests",
            dependencies: ["FredTermProcess"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

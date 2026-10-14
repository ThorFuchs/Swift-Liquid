// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "Swift-Liquid",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Liquid", targets: ["Liquid"]),
        .executable(name: "liquid", targets: ["LiquidCLI"])
    ],
    dependencies: [],
    targets: [
        .target(name: "Liquid"),
        .executableTarget(name: "LiquidCLI", dependencies: ["Liquid"]),
        .testTarget(name: "LiquidTests", dependencies: ["Liquid"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)

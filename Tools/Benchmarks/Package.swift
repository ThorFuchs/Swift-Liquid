// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "LiquidBenchmarks",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "LiquidBenchmarks", dependencies: [.product(name: "Liquid", package: "Swift-Liquid")])],
    swiftLanguageModes: [.v6]
)

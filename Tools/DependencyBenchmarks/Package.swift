// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "LiquidDependencyBenchmarks",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "LiquidDependencyBenchmarks", dependencies: [.product(name: "Liquid", package: "Swift-Liquid")])],
    swiftLanguageModes: [.v6]
)

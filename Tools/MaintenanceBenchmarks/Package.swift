// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "LiquidMaintenanceBenchmarks", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "LiquidMaintenanceBenchmarks", dependencies: [
        .product(name: "Liquid", package: "Swift-Liquid")
    ])], swiftLanguageModes: [.v6]
)

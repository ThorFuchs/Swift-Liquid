// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "LiquidConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "Swift-Liquid", path: "../..")],
    targets: [.executableTarget(name: "LiquidConsumer", dependencies: [.product(name: "Liquid", package: "Swift-Liquid")])],
    swiftLanguageModes: [.v6]
)

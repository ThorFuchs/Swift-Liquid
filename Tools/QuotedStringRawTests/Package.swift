// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(name: "QuotedStringRawTests", platforms: [.macOS(.v14)],
    dependencies: [.package(name: "Swift-Liquid", path: "../..")], targets: [
        .testTarget(name: "QuotedStringRawTests", dependencies: [.product(name: "Liquid", package: "Swift-Liquid")], resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v6])

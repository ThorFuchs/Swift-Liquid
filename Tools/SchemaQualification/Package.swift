// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// An isolated tooling consumer; this dependency never enters Swift-Liquid's root graph.
let package = Package(
    name: "LiquidSchemaQualification",
    platforms: [.macOS("27.0")],
    dependencies: [.package(url: "https://github.com/ThorFuchs/Swift-JSON.git", exact: "1.3.0")],
    targets: [.executableTarget(name: "LiquidSchemaQualification", dependencies: [
        .product(name: "JSON", package: "Swift-JSON"),
        .product(name: "JSONSchema", package: "Swift-JSON")
    ])],
    swiftLanguageModes: [.v6]
)

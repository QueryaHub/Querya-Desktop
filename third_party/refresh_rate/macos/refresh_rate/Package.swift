// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// This Package.swift file is consumed by Swift Package Manager when the plugin
// is used via the Flutter SPM integration (flutter build / flutter run with
// Swift Package Manager enabled). It mirrors the sources and settings declared
// in refresh_rate.podspec.

import PackageDescription

let package = Package(
    name: "refresh_rate",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        .library(name: "refresh-rate", targets: ["refresh_rate"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "refresh_rate",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "../Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../Classes"),
            ]
        ),
    ]
)

// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
import PackageDescription

let package = Package(
    name: "refresh_rate",
    platforms: [
        .iOS(.v12),
    ],
    products: [
        .library(name: "refresh-rate", targets: ["refresh_rate"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "refresh_rate_objc",
            path: "Sources/refresh_rate_objc",
            publicHeadersPath: "include"
        ),
        .target(
            name: "refresh_rate",
            dependencies: [
                "refresh_rate_objc",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/refresh_rate"
        ),
    ]
)

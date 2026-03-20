// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AirTodayUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AirTodayUI", targets: ["AirTodayUI"]),
    ],
    dependencies: [
        .package(path: "../AirTodayCore"),
    ],
    targets: [
        .target(name: "AirTodayUI", dependencies: ["AirTodayCore"]),
        .testTarget(name: "AirTodayUITests", dependencies: ["AirTodayUI"]),
    ]
)

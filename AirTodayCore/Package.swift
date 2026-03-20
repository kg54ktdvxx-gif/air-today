// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AirTodayCore",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AirTodayCore", targets: ["AirTodayCore"]),
    ],
    targets: [
        .target(name: "AirTodayCore"),
        .testTarget(name: "AirTodayCoreTests", dependencies: ["AirTodayCore"]),
    ]
)

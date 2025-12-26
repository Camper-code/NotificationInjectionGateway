// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "NotificationInjectionGateway",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "NotificationInjectionGateway",
            targets: ["NotificationInjectionGateway"]
        ),
    ],
    targets: [
        .target(
            name: "NotificationInjectionGateway",
            path: "Sources/NotificationInjectionGateway",
            exclude: ["NotificationInjectionGateway.swift"] 
        ),
        .testTarget(
            name: "NotificationInjectionGatewayTests",
            dependencies: ["NotificationInjectionGateway"]
        ),
    ]
)

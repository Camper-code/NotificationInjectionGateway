// swift-tools-version: 6.2
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
            name: "NotificationInjectionGateway"
        ),
        .testTarget(
            name: "NotificationInjectionGatewayTests",
            dependencies: ["NotificationInjectionGateway"]
        ),
    ]
)

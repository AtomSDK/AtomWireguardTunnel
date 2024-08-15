// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AtomWireguardTunnel",
    platforms: [
        .iOS(.v12), .macOS(.v10_14)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "AtomWireguardTunnel",
            targets: ["AtomWireguardTunnel"]),
    ],
    dependencies: [
        //.package(name: "WireGuardKit", url: "https://github.com/wireguard/wireguard-apple", branch: "am/develop")
        .package(url: "https://github.com/AtomSDK/wireguard-apple", from: "1.0.18")
    ],
    targets: [
        .target(
            name: "AtomWireGuardAppExtension",
            dependencies: [
                .product(name: "WireGuardKit", package: "wireguard-apple"),
                "AtomWireGuardCore",
                "AtomWireGuardManager"
            ]),
        .target(
            name: "AtomWireGuardCore",
            dependencies: [
                .product(name: "WireGuardKit", package: "wireguard-apple")
            ]),
        .target(
            name: "AtomWireGuardManager",
            dependencies: [
                "AtomWireGuardCore",
                .product(name: "WireGuardKit", package: "wireguard-apple")
            ]),
        .target(
            name: "AtomWireguardTunnel",
            dependencies: [
                .product(name: "WireGuardKit", package: "wireguard-apple"),
                "AtomWireGuardAppExtension"
                
            ]),

    ]
)

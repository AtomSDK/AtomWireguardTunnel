// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AtomWireguardTunnel",
    platforms: [
        .iOS(.v12), .macOS(.v10_14), .tvOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "AtomWireguardTunnel",
            targets: ["AtomWireguardTunnel"]),
    ],
    dependencies: [
        
        // tvOS from Atom branch, needs testing on macOS and iOS.
        .package(name: "WireGuardKit", url: "https://github.com/AtomSDK/wireguard-apple", branch: "feature/tvos-compatibility")
        
        // Working fine on tvOS, needs testing on macOS and iOS.
        //.package(name: "WireGuardKit", url: "https://github.com/passepartoutvpn/wireguard-apple", revision: "b79f0f150356d8200a64922ecf041dd020140aa0")
        
        // Old without tvOS, working fine on macOS and iOS.
        //.package(name: "WireGuardKit", url: "https://github.com/wireguard/wireguard-apple", branch: "am/develop")
    ],
    targets: [
        .target(
            name: "AtomWireGuardAppExtension",
            dependencies: [
                "WireGuardKit",
                "AtomWireGuardCore",
                "AtomWireGuardManager"
            ]),
        .target(
            name: "AtomWireGuardCore",
            dependencies: [
                "WireGuardKit"
            ]),
        .target(
            name: "AtomWireGuardManager",
            dependencies: [
                "AtomWireGuardCore",
                "WireGuardKit"
            ]),
        .target(
            name: "AtomWireguardTunnel",
            dependencies: [
                "WireGuardKit",
                "AtomWireGuardAppExtension"
                
            ]),

    ]
)

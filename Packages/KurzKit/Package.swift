// swift-tools-version: 6.2
import PackageDescription

// Layers depend downwards only: Features -> Core. Core targets never import SwiftUI.
let package = Package(
    name: "KurzKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Networking", targets: ["Networking"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Networking", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking", "Domain"]),
    ]
)

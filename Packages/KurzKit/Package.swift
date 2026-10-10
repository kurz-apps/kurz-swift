// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KurzKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Auth", targets: ["Auth"]),
        .library(name: "FeatureAuth", targets: ["FeatureAuth"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Networking", dependencies: ["Domain"]),
        .target(name: "Auth", dependencies: ["Domain", "Networking"]),
        .target(name: "DesignSystem"),
        .target(name: "FeatureAuth", dependencies: ["Auth", "DesignSystem"]),
        .testTarget(name: "AuthTests", dependencies: ["Auth", "Networking", "Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking", "Domain"]),
    ]
)

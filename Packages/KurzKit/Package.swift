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
        .library(name: "FeatureAgenda", targets: ["FeatureAgenda"]),
        .library(name: "FeatureShell", targets: ["FeatureShell"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Networking", dependencies: ["Domain"]),
        .target(name: "Auth", dependencies: ["Domain", "Networking"]),
        .target(name: "DesignSystem", resources: [.process("Resources")]),
        .target(name: "FeatureAuth", dependencies: ["Auth", "DesignSystem"]),
        .target(name: "FeatureAgenda", dependencies: ["Domain", "Networking", "DesignSystem"]),
        .target(name: "FeatureShell", dependencies: ["Domain", "Networking", "DesignSystem", "FeatureAgenda"]),
        .testTarget(name: "FeatureAuthTests", dependencies: ["FeatureAuth", "Networking"]),
        .testTarget(name: "FeatureShellTests", dependencies: ["FeatureShell", "Domain"]),
        .testTarget(name: "FeatureAgendaTests", dependencies: ["FeatureAgenda", "Domain", "DesignSystem"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "AuthTests", dependencies: ["Auth", "Networking", "Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking", "Domain"]),
    ]
)

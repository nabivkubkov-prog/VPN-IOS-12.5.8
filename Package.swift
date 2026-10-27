// swift-tools-version:5.7
import PackageDescription

let package = Package(name: "IncyProfiles", platforms: [.iOS(.v12), .macOS(.v10_13)],
    products: [.library(name: "IncyProfiles", targets: ["IncyProfiles"])],
    targets: [
        .target(name: "IncyProfiles", path: "Shared", exclude: ["ProfileVault.swift"]),
        .testTarget(name: "IncyProfilesTests", dependencies: ["IncyProfiles"], path: "Tests/Profiles")
    ])


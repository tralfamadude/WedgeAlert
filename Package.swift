// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WedgeAlert",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "WedgeAlert", targets: ["WedgeAlert"])],
    targets: [
        .executableTarget(name: "WedgeAlert"),
        .testTarget(name: "WedgeAlertTests", dependencies: ["WedgeAlert"])
    ],
    swiftLanguageModes: [.v5]
)

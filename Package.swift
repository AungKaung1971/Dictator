// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Dictator", platforms: [.macOS(.v13)], products: [
    .executable(name: "Dictator", targets: ["Dictator"])
], targets: [
    .target(name: "DictatorCore"),
    .executableTarget(name: "Dictator", dependencies: ["DictatorCore"])
])

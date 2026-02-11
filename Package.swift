// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowDoro",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "CSQLite"
        ),
        .executableTarget(
            name: "FlowDoro",
            dependencies: ["CSQLite"],
            path: "FlowDoro"
        ),
    ]
)

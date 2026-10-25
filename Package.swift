// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TurboFan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TurboFanApp", targets: ["TurboFanApp"]),
        .library(name: "TurboCore", targets: ["TurboCore"]),
        .library(name: "TurboFanUI", targets: ["TurboFanUI"]),
        .executable(name: "turbofan", targets: ["turbofan"]),
        .executable(name: "turbofand", targets: ["turbofand"]),
    ],
    targets: [
        .target(name: "TurboCore", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "TurboFanUI", dependencies: ["TurboCore"]),
        .executableTarget(name: "TurboFanApp", dependencies: ["TurboFanUI"]),
        .executableTarget(name: "turbofan", dependencies: ["TurboCore"]),
        .executableTarget(name: "turbofand", dependencies: ["TurboCore"]),
        .testTarget(name: "TurboCoreTests", dependencies: ["TurboCore"]),
    ]
)

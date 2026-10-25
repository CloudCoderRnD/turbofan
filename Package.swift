// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TurboFan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TurboFanApp", targets: ["TurboFanApp"]),
        .executable(name: "TurboFanProApp", targets: ["TurboFanProApp"]),
        .library(name: "TurboCore", targets: ["TurboCore"]),
        .library(name: "TurboFanUI", targets: ["TurboFanUI"]),
        .executable(name: "turbofan", targets: ["turbofan"]),
        .executable(name: "turbofand", targets: ["turbofand"]),
        .executable(name: "turbofanpro-helper", targets: ["turbofanpro-helper"]),
        .executable(name: "turbofan-license", targets: ["turbofan-license"]),
    ],
    dependencies: [
        // Auto-updates for the Pro edition only.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Free edition
        .target(name: "TurboCore", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "TurboFanUI", dependencies: ["TurboCore"]),
        .executableTarget(name: "TurboFanApp", dependencies: ["TurboFanUI"]),
        .executableTarget(name: "turbofan", dependencies: ["TurboCore"]),
        .executableTarget(name: "turbofand", dependencies: ["TurboCore"]),
        .testTarget(name: "TurboCoreTests", dependencies: ["TurboCore"]),

        // Pro edition: battery limit, health history, licences, auto-updates
        .target(name: "ProShared"),
        .target(name: "TurboFanPro", dependencies: [
            "ProShared", "TurboCore", "TurboFanUI",
            .product(name: "Sparkle", package: "Sparkle"),
        ], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "TurboFanProApp", dependencies: ["TurboFanPro", "TurboFanUI"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "turbofanpro-helper", dependencies: ["ProShared", "TurboCore"]),
        .executableTarget(name: "turbofan-license", dependencies: ["ProShared"]),
    ]
)

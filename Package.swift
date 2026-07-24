// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Helm",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "HelmContract"),
        .target(name: "HelmRuntime"),
        .target(name: "HelmUI", dependencies: ["HelmContract"]),
        .target(
            name: "Module_KeepAwake_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/KeepAwake/Engine"
        ),
        .target(
            name: "Module_KeepAwake_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_KeepAwake_Engine"],
            path: "Sources/Modules/KeepAwake/UI"
        ),
        .executableTarget(
            name: "HelmApp",
            dependencies: ["HelmContract", "HelmRuntime", "HelmUI",
                           "Module_KeepAwake_Engine", "Module_KeepAwake_UI"]
        ),
        .testTarget(name: "HelmRuntimeTests", dependencies: ["HelmRuntime"]),
        .testTarget(
            name: "Module_KeepAwake_EngineTests",
            dependencies: ["Module_KeepAwake_Engine"],
            path: "Tests/Modules/KeepAwake/EngineTests"
        ),
    ]
)

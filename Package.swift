// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Helm",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "HelmContract"),
        .target(name: "HelmRuntime"),
        .target(name: "HelmUI", dependencies: ["HelmContract", "HelmRuntime"]),
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
        .target(
            name: "Module_VPN_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/VPN/Engine"
        ),
        .target(
            name: "Module_VPN_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_VPN_Engine"],
            path: "Sources/Modules/VPN/UI"
        ),
        .executableTarget(
            name: "HelmApp",
            dependencies: ["HelmContract", "HelmRuntime", "HelmUI",
                           "Module_KeepAwake_Engine", "Module_KeepAwake_UI",
                           "Module_VPN_Engine", "Module_VPN_UI"]
        ),
        .testTarget(name: "HelmRuntimeTests", dependencies: ["HelmRuntime"]),
        .testTarget(
            name: "Module_KeepAwake_EngineTests",
            dependencies: ["Module_KeepAwake_Engine"],
            path: "Tests/Modules/KeepAwake/EngineTests"
        ),
        .testTarget(
            name: "Module_VPN_EngineTests",
            dependencies: ["Module_VPN_Engine"],
            path: "Tests/Modules/VPN/EngineTests"
        ),
    ]
)

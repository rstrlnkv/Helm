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
        .target(
            name: "Module_Uninstaller_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/Uninstaller/Engine"
        ),
        .target(
            name: "Module_Uninstaller_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_Uninstaller_Engine"],
            path: "Sources/Modules/Uninstaller/UI"
        ),
        .target(
            name: "Module_Homebrew_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/Homebrew/Engine"
        ),
        .target(
            name: "Module_Homebrew_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_Homebrew_Engine"],
            path: "Sources/Modules/Homebrew/UI"
        ),
        .executableTarget(
            name: "HelmApp",
            dependencies: ["HelmContract", "HelmRuntime", "HelmUI",
                           "Module_KeepAwake_Engine", "Module_KeepAwake_UI",
                           "Module_VPN_Engine", "Module_VPN_UI",
                           "Module_Uninstaller_Engine", "Module_Uninstaller_UI",
                           "Module_Homebrew_Engine", "Module_Homebrew_UI"]
        ),
        .testTarget(name: "HelmContractTests", dependencies: ["HelmContract"]),
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
        .testTarget(
            name: "Module_Uninstaller_EngineTests",
            dependencies: ["Module_Uninstaller_Engine"],
            path: "Tests/Modules/Uninstaller/EngineTests"
        ),
        .testTarget(
            name: "Module_Homebrew_EngineTests",
            dependencies: ["Module_Homebrew_Engine"],
            path: "Tests/Modules/Homebrew/EngineTests"
        ),
    ]
)

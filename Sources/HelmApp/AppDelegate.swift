import AppKit
import HelmContract
import Module_Island_UI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!
    var islandPrototype: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        host.bootstrap()
        statusController = StatusItemController(host: host)
        // Accessory apps launched without activation can fail to render their
        // status item until first activation; kick it once (accessory = no Dock icon).
        NSApp.activate()

        // Global hotkey toggles Keep Awake.
        HotkeyManager.shared.onFire = { [weak host] in
            guard let engine = host?.liveModule("keep-awake")?.engine else { return }
            let transport = engine.transport
            Task { _ = try? await transport.send(EngineCommand(name: "toggle")) }
        }
        HotkeyManager.shared.start()

        UpdateService.shared.checkOnLaunch()

        // Island drag-detection prototype (risk gate, plan Task 2).
        if ProcessInfo.processInfo.environment["HELM_DEBUG_ISLAND"] == "1" {
            islandPrototype = IslandWindowController()
        }
    }
}

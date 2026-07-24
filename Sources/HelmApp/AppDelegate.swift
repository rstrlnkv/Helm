import AppKit
import HelmContract

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!

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

    }
}

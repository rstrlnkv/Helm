import AppKit
import HelmContract
import Module_Island_UI
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!
    var islandPrototype: IslandWindowController?
    var islandDebugStep = 0

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

        // Island debug harness: cycle states for frame capture.
        if ProcessInfo.processInfo.environment["HELM_DEBUG_ISLAND"] == "1" {
            let controller = IslandWindowController(content: AnyView(
                Text("Drop files here").foregroundStyle(.white).frame(height: 120)))
            islandPrototype = controller
            islandDebugStep = 0
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    guard let c = self.islandPrototype else { return }
                    switch self.islandDebugStep % 4 {
                    case 0: c.apply(.hoverEntered)
                    case 1: c.apply(.event(id: "demo"))
                    case 2: c.apply(.hoverExited); c.apply(.graceElapsed)   // → peek (event alive)
                    default: c.apply(.dismiss)
                    }
                    self.islandDebugStep += 1
                }
            }
        }
    }
}

import AppKit
import HelmContract
import HelmRuntime

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

        // Dev builds always log: the file is the evidence we triage before a
        // build graduates to the stable channel.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        HelmLog.shared.start(version: version, override: AppSettings.loggingOverride)
        HelmLog.shared.info("app", "modules: \(ModuleRegistry.all.map(\.idRaw).joined(separator: ", "))")

        // First launch: find out what macOS is withholding before a removal
        // silently leaves files behind.
        PermissionAudit.runOnFirstLaunch()
        HelmLog.shared.info("permissions", "full disk access probe: \(PermissionCheck.currentFullDiskAccess().rawValue)")


        UpdateService.shared.checkOnLaunch()
    }
    func applicationWillTerminate(_ notification: Notification) {
        HelmLog.shared.info("app", "terminating")
    }

}

import AppKit
import HelmContract
import HelmRuntime

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before the status item and the panel exist, so nothing is drawn twice.
        AppSettings.applyAppearance()
        // Dev builds always log: the file is the evidence we triage before a
        // build graduates to the stable channel.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        HelmLog.shared.start(version: version, override: AppSettings.loggingOverride)

        host.bootstrap()
        statusController = StatusItemController(host: host)
        // Accessory apps launched without activation can fail to render their
        // status item until first activation; kick it once (accessory = no Dock icon).
        NSApp.activate()


        // Global shortcuts. Each one sends a command to a module's engine, so
        // the host never reaches past the transport into a module.
        func send(_ command: String, to module: String) -> () -> Void {
            { [weak host] in
                guard let engine = host?.liveModule(module)?.engine else { return }
                let transport = engine.transport
                Task { _ = try? await transport.send(EngineCommand(name: command)) }
            }
        }
        HotkeyManager.shared.register(
            "keep-awake.toggle",
            store: NamespacedStore(namespace: "keep-awake", backing: UserDefaults.standard),
            action: send("toggle", to: "keep-awake"))
        HotkeyManager.shared.register(
            "layout.convert",
            store: NamespacedStore(namespace: "layout", backing: UserDefaults.standard),
            prefix: "convertHotkey",
            action: send("convertLastWord", to: "layout"))
        HotkeyManager.shared.register(
            "layout.undo",
            store: NamespacedStore(namespace: "layout", backing: UserDefaults.standard),
            prefix: "undoHotkey",
            action: send("undoLastConversion", to: "layout"))
        HotkeyManager.shared.start()

        HelmLog.shared.info("app", "modules: \(ModuleRegistry.all.map(\.idRaw).joined(separator: ", "))")

        // First launch: find out what macOS is withholding before a removal
        // silently leaves files behind.
        PermissionAudit.host = host
        PermissionAudit.run()
        HelmLog.shared.info("permissions", "full disk access probe: \(PermissionCheck.currentFullDiskAccess().rawValue)")


        UpdateService.shared.checkOnLaunch()
    }
    func applicationWillTerminate(_ notification: Notification) {
        HelmLog.shared.info("app", "terminating")
    }

}

import AppKit
import HelmContract
import HelmRuntime

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!
    private var footprintTimer: Timer?

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
        // One chord for the whole module, doing whatever the tap key does — for
        // keyboards with no right-hand modifier to tap. There were five: convert
        // the last word, undo, and one for each of three selection actions. The
        // engine already decided between converting and undoing on its own, and
        // now it decides between the selection and the last word too, so the
        // other four were rows asking the user to assemble a gesture the app
        // could assemble itself.
        HotkeyManager.shared.register(
            "layout.fix",
            store: NamespacedStore(namespace: "layout", backing: UserDefaults.standard),
            prefix: "convertHotkey",
            action: send("fix", to: "layout"))
        // Keeps the frontmost-app snapshot current, so every thread that asks
        // reads a value rather than reaching into AppKit for it.
        FrontmostApp.shared.startObserving()
        HotkeyManager.shared.start()

        HelmLog.shared.info("app", "modules: \(ModuleRegistry.all.map(\.idRaw).joined(separator: ", "))")

        // First launch: find out what macOS is withholding before a removal
        // silently leaves files behind.
        PermissionAudit.host = host
        PermissionAudit.run()
        HelmLog.shared.info("permissions", "full disk access probe: \(PermissionCheck.currentFullDiskAccess().rawValue)")

        UpdateService.shared.checkOnLaunch()

        HelmLog.shared.memory("launch")
        startFootprintWatch()
    }

    /// The reading nothing else takes.
    ///
    /// Every other `memory(_:)` call sits on an operation, which answers "what
    /// did that cost" — and says nothing at all about growth that happens while
    /// the app sits there. This one runs on a timer and is silent unless the
    /// footprint has moved past the threshold since the last time it spoke, so
    /// a quiet app writes nothing and a growing one leaves a timestamped trail
    /// of where it grew. It is what turns "48 GB by morning" into a interval
    /// somebody can look at.
    private func startFootprintWatch() {
        footprintTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            HelmLog.shared.memory("idle")
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        HelmLog.shared.info("app", "terminating")
    }

}

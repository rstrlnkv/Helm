import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import Module_KeepAwake_UI
import Module_Layout_UI
import Module_Uninstaller_UI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = ModuleHost.shared
    var statusController: StatusItemController!
    /// Held, so the tick lives as long as the app does — and so `stop()` has
    /// something to be called on at teardown rather than waiting for a `deinit`
    /// that a running task would keep from firing.
    private var scanCoordinator: ScanCoordinator?
    private var footprintTimer: Timer?
    /// Held for as long as it is on screen; dropped in its own close handler.
    private var welcomeWindow: WelcomeWindow?
    /// The same, for the window that offers to clean up after an app somebody
    /// dragged to the Trash.
    private var trashWindow: TrashedLeftoversWindow?
    private var moduleEnabledObserver: NSObjectProtocol?
    private var moduleDisabledObserver: NSObjectProtocol?
    /// The subscription to the Uninstaller's "look again". Held so it can be
    /// cancelled: a `for await` over an event stream that never finishes runs for
    /// the life of the app, and cancelling it from outside is the only way it
    /// ever ends — `deinit` cannot, because the task is what keeps the object
    /// alive (ARCHITECTURE.md § Memory).
    private var trashEventsTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before the status item and the panel exist, so nothing is drawn twice.
        // Before anything draws a string: every `L()` reads the language on
        // every call, so a late apply would leave whatever was built first in
        // the Mac's own language.
        AppSettings.applyStoredLanguage()
        AppSettings.applyAppearance()
        // Dev builds always log: the file is the evidence we triage before a
        // build graduates to the stable channel.
        let version = AppBuild.shortVersion ?? "0"
        HelmLog.shared.start(version: version, override: AppSettings.loggingOverride)

        host.bootstrap()
        statusController = StatusItemController(host: host)
        // After bootstrap, because it asks the host for live modules. It does
        // nothing at launch beyond starting a one-minute tick: `ScanSchedule`
        // refuses a scan that already ran today, which is what stops somebody
        // who opens and quits Helm five times an afternoon from re-reading the
        // volume five times.
        scanCoordinator = ScanCoordinator(host: host)
        scanCoordinator?.start()
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
            store: NamespacedStore(namespace: KeepAwakeDescriptor.id.rawValue, backing: UserDefaults.standard),
            action: send(KeepAwakeCommand.toggle.rawValue, to: KeepAwakeDescriptor.id.rawValue))
        // One chord for the whole module, doing whatever the tap key does — for
        // keyboards with no right-hand modifier to tap. There were five: convert
        // the last word, undo, and one for each of three selection actions. The
        // engine already decided between converting and undoing on its own, and
        // now it decides between the selection and the last word too, so the
        // other four were rows asking the user to assemble a gesture the app
        // could assemble itself.
        HotkeyManager.shared.register(
            "layout.fix",
            store: NamespacedStore(namespace: LayoutDescriptor.id.rawValue, backing: UserDefaults.standard),
            prefix: "convertHotkey",
            action: send(LayoutCommand.fix.rawValue, to: LayoutDescriptor.id.rawValue))
        // Keeps the frontmost-app snapshot current, so every thread that asks
        // reads a value rather than reaching into AppKit for it.
        FrontmostApp.shared.startObserving()
        HotkeyManager.shared.start()

        HelmLog.shared.info("app", "modules: \(ModuleRegistry.all.map(\.idRaw).joined(separator: ", "))")

        // First launch: find out what macOS is withholding before a removal
        // silently leaves files behind.
        PermissionAudit.host = host
        // The audit puts up an alert when macOS is withholding something, and
        // on a first launch that is the same moment the welcome window wants.
        // Two of them arriving together is not an introduction, it is a
        // pile-up — so the audit waits for the window to go away, by Done, by
        // Skip or by the close button.
        if WelcomeWindow.shouldShow(store: AppSettings.store) {
            let welcome = WelcomeWindow { [weak self] in
                self?.welcomeWindow = nil
                PermissionAudit.run()
                self?.offerTrashLeftovers()
            }
            welcomeWindow = welcome
            welcome.show(
                steps: WelcomeSteps.build(from: ModuleRegistry.all.map(\.moduleMetadata)),
                store: AppSettings.store,
                isModuleEnabled: { [host] id in
                    ModuleRegistry.all.first { $0.idRaw == id }.map { host.isEnabled($0) } ?? true
                },
                setModuleEnabled: { [host] id, on in
                    guard let d = ModuleRegistry.all.first(where: { $0.idRaw == id }) else { return }
                    host.setEnabled(d, on)
                },
                isLaunchAtLogin: { LoginItem.isEnabled },
                setLaunchAtLogin: { LoginItem.setEnabled($0) })
        } else {
            PermissionAudit.run()
            offerTrashLeftovers()
        }
        // An app dragged to the Trash while Helm is running is the case the
        // sweep alone cannot see, and it is the one people actually do.
        watchTrashArrivals()
        // Switching the Uninstaller on is the other moment worth sweeping: the
        // module that answers this question did not exist a second ago.
        moduleEnabledObserver = NotificationCenter.default.addObserver(
            forName: .helmModuleEnabled, object: nil, queue: .main) { [weak self] note in
                guard note.object as? String == UninstallerDescriptor.id.rawValue else { return }
                MainActor.assumeIsolated {
                    self?.offerTrashLeftovers()
                    // A new engine means a new transport: the old subscription
                    // points at a stream nothing will ever emit into again.
                    self?.watchTrashArrivals()
                }
            }
        moduleDisabledObserver = NotificationCenter.default.addObserver(
            forName: .helmModuleDisabled, object: nil, queue: .main) { [weak self] note in
                guard note.object as? String == UninstallerDescriptor.id.rawValue else { return }
                MainActor.assumeIsolated {
                    self?.trashEventsTask?.cancel()
                    self?.trashEventsTask = nil
                }
            }
        HelmLog.shared.info("permissions", "full disk access probe: \(PermissionCheck.currentFullDiskAccess().rawValue)")

        UpdateService.shared.checkOnLaunch()

        HelmLog.shared.memory("launch")
        startFootprintWatch()

    }

    /// Asks the Uninstaller what is sitting in the Trash and shows the offer if
    /// there is one.
    ///
    /// Called from three places, and each covers what the others cannot: at
    /// launch (an app deleted while Helm was closed), when the module is switched
    /// on by hand, and on the module's watcher noticing an arrival — which is the
    /// case people actually produce, dragging an app to the Trash with Helm
    /// running. The module being off is the whole answer: no engine, no sweep, no
    /// window.
    ///
    /// Full Disk Access is not checked here. Without it the Trash cannot be read,
    /// the sweep comes back empty and no window appears — and the place that says
    /// why is the module's own page, which already carries the notice.
    private func offerTrashLeftovers() {
        // A window already up is not a reason to do nothing — it is the reason
        // the host does nothing *here*: the window is listening to the same
        // event and takes the new app into the list it is already showing,
        // which is what a second app dropped a moment after the first deserves.
        guard trashWindow == nil else {
            HelmLog.shared.info("app", "trash arrival goes to the open window")
            return
        }
        guard let live = host.liveModule(UninstallerDescriptor.id.rawValue) else {
            HelmLog.shared.info("app", "trash sweep skipped: the uninstaller is off")
            return
        }
        HelmLog.shared.info("app", "trash sweep requested")
        let window = TrashedLeftoversWindow { [weak self] in self?.trashWindow = nil }
        trashWindow = window
        Task { [weak self] in
            // Nothing to offer: drop the holder, or the next sweep finds it
            // occupied and stays quiet for the rest of the run.
            if await window.showIfAnything(vm: live.vm) == false { self?.trashWindow = nil }
        }
    }

    /// Subscribes to the Uninstaller's "look again".
    ///
    /// The event carries nothing and is not meant to: the module watches
    /// `~/.Trash`, decides whether the change could have been an app arriving,
    /// and says only that the question is worth asking again. The host answers it
    /// the one way it can — the same sweep it runs at launch.
    private func watchTrashArrivals() {
        trashEventsTask?.cancel()
        guard let live = host.liveModule(UninstallerDescriptor.id.rawValue) else { return }
        let events = live.engine.transport.events
        // A string is what crosses the transport; it is not what the host has
        // to type. `UninstallerDescriptor` re-exports `UninstallerEvent` the
        // way the descriptors already re-export their command enums for the
        // hotkeys two screens up, so this name is one declaration rather than a
        // literal on each side. Spelled by hand, a rename in the engine would
        // be an error nowhere and the offer would simply stop appearing.
        trashEventsTask = Task { [weak self] in
            for await event in events where event.name == UninstallerEvent.trashChanged.rawValue {
                self?.offerTrashLeftovers()
            }
        }
    }

    /// The reading nothing else takes.
    ///
    /// Called `idle` until 2026-07-31, which was a lie by omission: it is a
    /// timer, and it fires whatever the app is doing. A run of `idle: 179 MB
    /// (+120)` / `75 MB (-104)` was read as an app churning while sitting still,
    /// by someone holding this app's own log — `listApps` and `appSizes` were
    /// running between those lines. It is a sample, it says so, and it now
    /// carries what was running when it was taken.
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
            HelmLog.shared.memory("sample")
        }
    }
    /// Quitting must not leave the machine changed.
    ///
    /// Keep Awake's lid option runs `sudo pmset disablesleep 1`, which is
    /// system state, not a process assertion — it outlives Helm. What takes it
    /// back is `deactivate()`, and nothing called it on quit: the only recovery
    /// was in `activate()`, i.e. the *next* launch of Helm. So quitting during
    /// a clamshell session left the Mac unable to sleep until the app was
    /// started again, and deleting the app left it that way for good.
    ///
    /// Deactivating every live engine fixes the class rather than that one
    /// instance — the IOKit assertions, the event tap, the folder watchers and
    /// the power observers are all released the same way, by the code that
    /// already knows how.
    func applicationWillTerminate(_ notification: Notification) {
        HelmLog.shared.info("app", "terminating")
        trashEventsTask?.cancel()
        // The coordinator owns a repeating tick and a notification observer, and
        // neither goes through an engine's `deactivate()`. Stopped from outside,
        // like every other observer the app starts itself.
        scanCoordinator?.stop()
        for live in host.live.values { live.engine.deactivate() }
    }

}

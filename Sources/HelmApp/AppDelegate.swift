import AppKit
import HelmRuntime
import HelmUI
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
        // Straight after the log opens, because this is the one thing that can
        // have gone wrong while there was no log: an update swap that never
        // completed leaves its note behind, and this launch is either the copy
        // that was put back or the one that landed (`UpdateHandoff`).
        UpdateHandoff.reportAtLaunch()

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

        // Keeps the frontmost-app snapshot current, so every thread that asks
        // reads a value rather than reaching into AppKit for it.
        FrontmostApp.shared.startObserving()
        // Every module's declared shortcuts, held while it is live.
        host.registerHotkeys()
        HotkeyManager.shared.start()

        HelmLog.shared.info("app", "modules: \(ModuleRegistry.all.map(\.idRaw).joined(separator: ", "))")

        // Every launch: find out what macOS is withholding before a removal
        // silently leaves files behind.
        PermissionAudit.host = host
        introduceOrAudit()
        // An app dragged to the Trash while Helm is running is the case the
        // sweep alone cannot see, and it is the one people actually do.
        watchTrashArrivals()
        // Switching the Uninstaller on is the other moment worth sweeping: the
        // module that answers this question did not exist a second ago.
        // Read once here on the main actor: the observer closures are Sendable
        // and may not touch the isolated descriptor themselves.
        let uninstallerId = UninstallerDescriptor.id.rawValue
        moduleEnabledObserver = NotificationCenter.default.addObserver(
            forName: .helmModuleEnabled, object: nil, queue: .main) { [weak self] note in
                guard note.object as? String == uninstallerId else { return }
                MainActor.assumeIsolated {
                    self?.offerTrashLeftovers()
                    // A new module means a new model: the old one, stopped with
                    // its module, listens to nobody.
                    self?.watchTrashArrivals()
                }
            }
        HelmLog.shared.info("permissions", "full disk access probe: \(PermissionCheck.currentFullDiskAccess().rawValue)")

        UpdateService.shared.startChecking()

        HelmLog.shared.memory("launch")
        startFootprintWatch()

        LaunchPage.openRequested(by: statusController, enabled: host.enabledModuleIDs)
    }

    /// The tour on a launch that has not seen it, then the permission audit;
    /// without the tour, the audit at once.
    ///
    /// The audit can put up an alert, and on a launch that shows the tour that
    /// is the same moment the welcome window
    /// wants. Two of them arriving together is not an introduction, it is a
    /// pile-up — so the audit waits for the window to go away, by Done, by Skip or by the close
    /// button.
    private func introduceOrAudit() {
        guard WelcomeWindow.shouldShow(store: AppSettings.store) else {
            PermissionAudit.run()
            offerTrashLeftovers()
            return
        }
        let welcome = WelcomeWindow { [weak self] in
            self?.welcomeWindow = nil
            PermissionAudit.run()
            self?.offerTrashLeftovers()
        }
        welcomeWindow = welcome
        welcome.show(
            steps: WelcomeSteps.build(from: ModuleRegistry.all.map(\.moduleMetadata)),
            store: AppSettings.store,
            actions: WelcomeActions(
                isModuleEnabled: { [host] id in
                    ModuleRegistry.all.first { $0.idRaw == id }.map { host.isEnabled($0) } ?? true
                },
                setModuleEnabled: { [host] id, on in
                    guard let d = ModuleRegistry.all.first(where: { $0.idRaw == id }) else { return }
                    host.setEnabled(d, on)
                },
                isLaunchAtLogin: { LoginItem.current().isOn },
                setLaunchAtLogin: { LoginItem.setEnabled($0).isOn },
                // The page first, then the tour goes away: closing it runs the
                // permission audit, and an alert arriving over a window that has
                // not been drawn yet is the pile-up the line above is about.
                openModule: { [weak self] id in
                    self?.statusController.showSettings(module: id)
                    self?.welcomeWindow?.close()
                }))
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
        // the host does nothing *here*: the model hands an arrival to the open
        // window, which takes the new app into the list it is already showing,
        // which is what a second app dropped a moment after the first deserves.
        guard trashWindow == nil else {
            HelmLog.shared.info("app", "trash arrival goes to the open window")
            return
        }
        guard let model = uninstaller else {
            HelmLog.shared.info("app", "trash sweep skipped: the uninstaller is off")
            return
        }
        HelmLog.shared.info("app", "trash sweep requested")
        let window = TrashedLeftoversWindow { [weak self] in self?.trashWindow = nil }
        trashWindow = window
        Task { [weak self] in
            // Nothing to offer: drop the holder, or the next sweep finds it
            // occupied and stays quiet for the rest of the run.
            if await window.showIfAnything(uvm: model) == false { self?.trashWindow = nil }
        }
    }

    /// The Uninstaller's model, or nil while the module is off.
    private var uninstaller: UninstallerViewModel? {
        guard let live = host.liveModule(UninstallerDescriptor.id.rawValue) else { return nil }
        guard let model = live.model as? UninstallerViewModel else {
            HelmLog.shared.warn("app", "the uninstaller's model is not UninstallerViewModel, so there is no trash offer"); return nil }
        return model
    }

    /// Subscribes to the Uninstaller's "look again".
    ///
    /// The signal carries nothing and is not meant to: the module watches
    /// `~/.Trash`, decides whether the change could have been an app arriving,
    /// and says only that the question is worth asking again. The host answers it
    /// the one way it can — the same sweep it runs at launch. The model ends the
    /// subscription with the module (`UninstallerViewModel.stop()`).
    private func watchTrashArrivals() {
        uninstaller?.listenForTrash { [weak self] in self?.offerTrashLeftovers() }
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
        // The coordinator owns a repeating tick and a notification observer, and
        // neither goes through an engine's `deactivate()`. Stopped from outside,
        // like every other observer the app starts itself.
        scanCoordinator?.stop()
        host.shutdown()
    }

}

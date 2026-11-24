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
        // Before the status item and the panel exist, so nothing is drawn twice.
        // Before anything draws a string: every `L()` reads the language on
        // every call, so a late apply would leave whatever was built first in
        // the Mac's own language.
        AppSettings.applyStoredLanguage()
        AppSettings.applyAppearance()
        // Dev builds always log: the file is the evidence a build is triaged on.
        let version = AppBuild.shortVersion ?? "0"
        HelmLog.shared.start(version: version, override: AppSettings.loggingOverride, isDev: AppBuild.isDev)
        // Straight after the log opens, because this is the one thing that can
        // have gone wrong while there was no log: an update swap that never
        // completed leaves its note behind, and this launch is either the copy
        // that was put back or the one that landed (`UpdateHandoff`).
        UpdateService.shared.unfinishedUpdate = UpdateHandoff.reportAtLaunch()

        host.bootstrap()
        statusController = StatusItemController(host: host)
        // After bootstrap, because it asks the host for live modules. It does
        // nothing at launch beyond starting a one-minute tick: `ScanSchedule`
        // refuses a scan that already ran today, so relaunching Helm does not
        // re-read the volume.
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
        UpdateService.shared.startChecking()

        HelmLog.shared.memory("launch")
        startFootprintWatch()

        LaunchPage.openRequested(by: statusController, enabled: host.enabledModuleIDs)
    }

    /// The tour on a launch that has not seen it, then the permission audit;
    /// without the tour, the audit at once.
    ///
    /// The audit can put up an alert, and two windows arriving together are a
    /// pile-up, so the audit waits for the welcome window to go away, by Done,
    /// by Skip or by the close button.
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
                    ModuleRegistry.descriptor(id).map { host.isEnabled($0) } ?? true
                },
                setModuleEnabled: { [host] id, on in
                    guard let d = ModuleRegistry.descriptor(id) else { return }
                    host.setEnabled(d, on)
                },
                isLaunchAtLogin: { LoginItem.current().isOn },
                setLaunchAtLogin: { LoginItem.setEnabled($0).isOn },
                // The page first, then the tour goes away: closing it runs the
                // permission audit, which must not arrive over a window not yet
                // drawn.
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
    /// on by hand, and on the module's watcher noticing an arrival (an app
    /// dragged to the Trash with Helm running). The module being off is the
    /// whole answer: no engine, no sweep, no window.
    ///
    /// Full Disk Access is not checked here. Without it the Trash cannot be read,
    /// the sweep comes back empty and no window appears — and the place that says
    /// why is the module's own page, which already carries the notice.
    private func offerTrashLeftovers() {
        // A window already up takes the arrival itself: the model hands it to
        // the open window, which adds the new app to the list it is showing.
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
    /// Named `sample`, not `idle`: it is a timer and fires whatever the app is
    /// doing, and the line carries what was running when it was taken.
    ///
    /// Every other `memory(_:)` call sits on an operation, which answers "what
    /// did that cost" and says nothing about growth while the app sits there.
    /// This one is silent unless the footprint has moved past the threshold
    /// since it last spoke, so a quiet app writes nothing and a growing one
    /// leaves a timestamped trail of where it grew.
    private func startFootprintWatch() {
        footprintTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            HelmLog.shared.memory("sample")
        }
    }

    /// The Launchpad Dock helper opens its link here (`CFBundleURLTypes`); the host decides what it means.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { host.openLaunchpadFromLink(url) }
    }

    /// Opening Helm again (Finder, Spotlight, Launchpad, `open -a`) does not start a
    /// second copy of a running app: the running one is sent this reopen event.
    /// Helm is an accessory app with no window of its own until Settings is
    /// opened, so without this handler the open would do nothing.
    ///
    /// With nothing on screen it asks for Settings through the notification every
    /// other caller uses (`StatusItemController` listens). With a window up there
    /// is nothing to ask for. `false` either way: the default reopen has nothing
    /// to add. A miniaturised window is not visible, so it takes the asking path:
    /// `bringForward()` activates and orders Settings front; whether that also
    /// restores a minimised window is not verified (to check in Helm Dev).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .helmOpenSettings, object: nil) }
        return false
    }

    /// Quitting must not leave the machine changed.
    ///
    /// Keep Awake's lid option runs `sudo pmset disablesleep 1`, which is
    /// system state, not a process assertion: it outlives Helm, and only
    /// `deactivate()` takes it back. So every live engine is deactivated here,
    /// and the IOKit assertions, the event tap, the folder watchers and the
    /// power observers are released the same way, by the code that knows how.

    func applicationWillTerminate(_ notification: Notification) {
        HelmLog.shared.terminating()
        // The coordinator owns a repeating tick and a notification observer, and
        // neither goes through an engine's `deactivate()`. Stopped from outside,
        // like every other observer the app starts itself.
        scanCoordinator?.stop()
        host.shutdown()
    }

}

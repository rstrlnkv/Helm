import AppKit
import Combine
import HelmContract
import HelmRuntime
import HelmUI
import HelmAppStrings

/// Owns the single `NSStatusItem`. `StatusPlan` decides which enabled module it
/// reflects and whether the ring moves; left click toggles the shared panel,
/// right click shows the menu `StatusMenuBuilder` builds: Settings, edit panel,
/// the live modules by sidebar section, Quit.
@MainActor final class StatusItemController: NSObject {
    private let host: ModuleHost
    private let statusItem: NSStatusItem
    private var hostCancellable: AnyCancellable?
    private var moduleCancellables: Set<AnyCancellable> = []
    /// The icon's two reasons to be drawn again: the style and the order.
    private var refreshObservers: [NSObjectProtocol] = []
    private var openSettingsObserver: NSObjectProtocol?

    private lazy var panel = HelmPanel(host: host)
    private lazy var settingsWindow = SettingsWindow(host: host)

    init(host: ModuleHost) {
        self.host = host
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // The menu-bar button is the only entrance to Helm, and an image
            // with no description is an unnamed button VoiceOver cannot find.
            button.setAccessibilityLabel("Helm")
            button.toolTip = "Helm"
        }

        // `@Published` publishes in `willSet`: `enabledModules` and the icon
        // read `host.live`, which still holds the old set inside the sink. One
        // main-queue hop lets the write land first, so both read the new set.
        hostCancellable = host.$live
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resubscribeToModules() }
        // The style changing redraws the icon, and so does the order:
        // `refreshIcon` hands `StatusPlan.choose` the modules in the user's
        // order, read at call time, so a reorder can change the answer (the
        // first tinted module wins) while nothing else asks for it again.
        refreshObservers = [.helmMenuBarStyleChanged, .helmModuleOrderChanged].map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.refreshIcon() }
            }
        }
        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .helmOpenSettings, object: nil, queue: .main
        ) { [weak self] note in
            // `object` may carry a module id to open that module's page directly.
            let moduleID = note.object as? String
            Task { @MainActor in self?.showSettings(module: moduleID) }
        }
        resubscribeToModules()
    }

    private func resubscribeToModules() {
        moduleCancellables.removeAll()
        for live in host.enabledModules {
            // A module with no `statusChanges` has nothing to say here.
            guard let changes = live.statusChanges() else { continue }
            changes
                // objectWillChange fires before the property is written, so
                // refreshing inline would read the previous state and never
                // start the countdown tick.
                .sink { [weak self] _ in
                    Task { @MainActor in self?.refreshIcon() }
                }
                .store(in: &moduleCancellables)
        }
        refreshIcon()
    }

    private var lastIconKey: String?
    /// Drives the countdown ring and its text: modules only emit on state
    /// changes, so both need their own tick while a timer is running.
    private lazy var timerTick = RepeatingTick(interval: 1) { [weak self] in self?.refreshIcon() }
    /// Drives a spin, which is thirty frames a second for about a second — far
    /// faster than the countdown, and armed only while a spin is live. It stops
    /// itself: the tick calls the very refresh that decides whether it is still
    /// wanted, so a spin that ends, a module switched off mid-spin and Reduce
    /// Motion switched on all disarm it within one frame.
    private lazy var spinTick = RepeatingTick(interval: 1.0 / 30) { [weak self] in self?.refreshIcon() }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let now = Date()
        // One rule decides, in four tiers (`StatusPlan.choose`): the first module
        // with a countdown, else the newest running spin, else the first tint,
        // else the first title.
        let appearance = StatusPlan.choose(
            host.enabledModules.map { $0.statusAppearance() }, now: now)
        let token = appearance.tintToken
        let globalStyle = AppSettings.menuBarIconStyle
        let style = appearance.iconStyle.flatMap(MenuBarIconStyle.init(rawValue:)) ?? globalStyle
        let size = AppSettings.menuBarIconSize
        let progress = appearance.timerProgress
        // Read fresh, the way `HelmMotion` does: the setting can be switched on
        // while a spin is running, and a cached answer would keep it moving.
        let spinning = StatusPlan.spins(appearance, now: now, reduceMotion: HelmMotion.reduceMotion)
        let frame = spinning ? StatusPlan.frame(spinUntil: appearance.spinUntil, now: now,
                                                frameCount: MenuBarIcon.frameCount) : nil
        timerTick.set(active: StatusPlan.wantsSecondTick(appearance))
        // Tied to the frame rather than to `spinning`: what keeps the tick alive
        // is exactly what it has left to draw.
        spinTick.set(active: frame != nil)
        // A module says nothing for an unchanged payload; redraw only when the glyph or title changes.
        let title = appearance.title
        // The spin's own colour when it has one, and the module's tint otherwise.
        let spinTint = appearance.spinTintToken ?? token
        let key = StatusPlan.redrawKey(style: style.rawValue, size: size.rawValue, tint: token,
                                       progress: progress, title: title, frame: frame,
                                       spinTint: frame != nil ? spinTint : nil)
        guard key != lastIconKey else { return }
        lastIconKey = key
        if let frame {
            button.image = MenuBarIcon.spinnerFrames(style: style, size: size,
                                                  tintToken: spinTint)[frame]
        } else {
            button.image = MenuBarIcon.make(style: style, size: size, tintToken: token, progress: progress)
        }
        // Countdown text sits after the glyph, in the tint the module asked for.
        if let title {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: MenuBarIcon.nsColor(forTintToken: token),
            ])
        } else {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    @objc private func statusItemClicked(_: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button)
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }

        // Only what is actually running, as in the panel: opening a disabled
        // module's page just to be told it is disabled is a dead end.
        let live = Set(host.enabledModules.map { $0.descriptor.idRaw })
        // The person's own arrangement, not the category enum's: they compose
        // the sidebar, and a menu of the same modules that disagreed with it
        // would make the arrangement a setting that only half applies.
        let layout = SidebarLayoutStore.current()
        let groups = layout.sections.map { section in
            StatusMenuBuilder.Group(entries: section.modules
                .filter { live.contains($0) }
                .compactMap { id in ModuleRegistry.descriptor(id) }
                .map { StatusMenuBuilder.Entry(id: $0.idRaw,
                                               title: $0.moduleMetadata.name,
                                               symbol: $0.moduleMetadata.sfSymbol) })
        }

        let menu = StatusMenuBuilder.menu(
            settingsTitle: AppStr.settings, quitTitle: AppStr.quit, groups: groups,
            target: self,
            openSettings: #selector(openSettings),
            openModule: #selector(openModuleSettings(_:)),
            quit: #selector(quit),
            editTitle: AppStr.editPanel,
            editWidgets: #selector(editWidgets))

        // Hand placement to the status item: popUp(at:) with a hand-computed
        // point opens a long menu scrolled, its first item off-screen.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    /// Opens the panel if it is closed, then asks it to arrange itself.
    ///
    /// Not `togglePanel()`: the panel is shut while its own menu is up, but a
    /// toggle would close it in whatever case it was not — and «edit» would
    /// then mean «put it away».
    @objc private func editWidgets() {
        if !panel.isShown { togglePanel() }
        NotificationCenter.default.post(name: .helmPanelEditRequested, object: nil)
    }

    @objc private func openModuleSettings(_ sender: NSMenuItem) {
        showSettings(module: sender.representedObject as? String)
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    /// Open Settings focused on a module (panel utility rows pass an id).
    func showSettings(module moduleID: String?) {
        settingsWindow.show(selecting: moduleID)
    }

    /// Open Settings on exactly this page (`LaunchPage`).
    func showSettings(page: SettingsSelection) {
        settingsWindow.show(page: page)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}

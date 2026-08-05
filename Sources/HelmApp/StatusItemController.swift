import AppKit
import Combine
import HelmContract
import HelmRuntime
import HelmUI

/// Owns the single `NSStatusItem`. `StatusPlan` decides which enabled module it
/// reflects and whether the ring moves; left click toggles the shared panel,
/// right click shows Settings/Quit.
@MainActor final class StatusItemController: NSObject {
    private let host: ModuleHost
    private let statusItem: NSStatusItem
    private var hostCancellable: AnyCancellable?
    private var moduleCancellables: Set<AnyCancellable> = []
    private var styleObserver: NSObjectProtocol?
    private var openSettingsObserver: NSObjectProtocol?
    private var orderObserver: NSObjectProtocol?

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
            // with no description is an unnamed button among twenty others:
            // VoiceOver could not find the app at all.
            button.setAccessibilityLabel("Helm")
            button.toolTip = "Helm"
        }

        hostCancellable = host.$live
            .sink { [weak self] _ in self?.resubscribeToModules() }
        styleObserver = NotificationCenter.default.addObserver(
            forName: .helmMenuBarStyleChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshIcon() }
        }
        // `refreshIcon` hands `StatusPlan.choose` the modules in the user's
        // order, read at call time — so a reorder changes the answer while
        // nothing asks for it again. Latent today: `KeepAwakeDescriptor` is the
        // only descriptor that overrides `statusAppearance`, so the fallback to
        // the first tinted module finds it whatever the order. It stops being
        // latent the day a second module tints the icon, and that is not the
        // day to remember this.
        orderObserver = NotificationCenter.default.addObserver(
            forName: .helmModuleOrderChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshIcon() }
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
            // Only a module that tints the icon has anything to say here.
            guard let changes = live.descriptor.statusChanges(live.vm) else { continue }
            changes
                // objectWillChange fires BEFORE the property is written, so
                // refreshing inline read the previous state — the countdown tick
                // was never started and nothing refreshed it afterwards.
                .sink { [weak self] _ in
                    Task { @MainActor in self?.refreshIcon() }
                }
                .store(in: &moduleCancellables)
        }
        refreshIcon()
    }

    private var lastIconKey: String?
    /// Drives the countdown ring: modules only emit on state changes, so the
    /// arc needs its own tick while a timer is running.
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
        // One rule decides: a module whose spin is running borrows the icon,
        // otherwise the first module that tints it.
        let appearance = StatusPlan.choose(
            host.enabledModules.map { $0.descriptor.statusAppearance($0.vm) }, now: now)
        let token = appearance.tintToken
        let globalStyle = MenuBarIconStyle(stored: AppSettings.menuBarIconStyle)
        let style = appearance.iconStyle.flatMap(MenuBarIconStyle.init(rawValue:)) ?? globalStyle
        let size = MenuBarIconSize(stored: AppSettings.menuBarIconSize)
        let progress = appearance.timerProgress
        // Read fresh, the way `HelmMotion` does: the setting can be switched on
        // while a spin is running, and a cached answer would keep it moving.
        let spinning = StatusPlan.spins(appearance, now: now, reduceMotion: HelmMotion.reduceMotion)
        let frame = spinning ? StatusPlan.frame(spinUntil: appearance.spinUntil, now: now,
                                                frameCount: RingIcon.frameCount) : nil
        timerTick.set(active: progress != nil)
        // Tied to the frame rather than to `spinning`: what keeps the tick alive
        // is exactly what it has left to draw.
        spinTick.set(active: frame != nil)
        // Modules emit state on every tick; only redraw when the glyph changes.
        let title = appearance.title
        // The spin's own colour when it has one, and the module's tint
        // otherwise — which is what Keep Awake has always drawn with.
        let spinTint = appearance.spinTintToken ?? token
        let key = StatusPlan.redrawKey(style: style.rawValue, size: size.rawValue, tint: token,
                                       progress: progress, title: title, frame: frame,
                                       spinTint: frame != nil ? spinTint : nil)
        guard key != lastIconKey else { return }
        lastIconKey = key
        if let frame {
            button.image = RingIcon.spinnerFrames(style: style, size: size,
                                                  tintToken: spinTint)[frame]
        } else {
            button.image = RingIcon.make(style: style, size: size, tintToken: token, progress: progress)
        }
        // Countdown text sits after the glyph, in the tint the module asked for.
        if let title {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: RingIcon.nsColor(forTintToken: token),
            ])
        } else {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
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

        // Only what is actually running: opening a disabled module's page just
        // to be told it is disabled is a dead end. The panel already did this.
        let live = Set(host.enabledModules.map { type(of: $0.descriptor).id.rawValue })
        // The person's own arrangement, not the category enum's: they compose
        // the sidebar, and a menu of the same nine modules that disagreed with
        // it would make the arrangement a setting that only half applies.
        let layout = SidebarLayoutStore.read(from: AppSettings.store,
                                             registry: SidebarLayoutStore.registry())
        let groups = layout.sections.map { section in
            StatusMenuBuilder.Group(entries: section.modules
                .filter { live.contains($0) }
                .compactMap { id in ModuleRegistry.all.first { $0.idRaw == id } }
                .map { StatusMenuBuilder.Entry(id: $0.idRaw,
                                               title: $0.moduleMetadata.name,
                                               symbol: $0.moduleMetadata.sfSymbol) })
        }

        let menu = StatusMenuBuilder.menu(
            settingsTitle: AppStr.settings, quitTitle: AppStr.quit, groups: groups,
            target: self,
            openSettings: #selector(openSettings),
            openModule: #selector(openModuleSettings(_:)),
            quit: #selector(quit))

        // Hand placement to the status item: popUp(at:) with a hand-computed
        // point stopped fitting once the module entries were added, and the menu
        // opened scrolled (its first item pushed off-screen).
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openModuleSettings(_ sender: NSMenuItem) {
        showSettings(module: sender.representedObject as? String)
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    /// Open Settings focused on a module (panel utility rows pass an id).
    private func showSettings(module moduleID: String?) {
        settingsWindow.show(selecting: moduleID)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}

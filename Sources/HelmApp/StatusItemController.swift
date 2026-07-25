import AppKit
import Combine
import HelmUI

/// Owns the single `NSStatusItem`. Reflects the first enabled module that
/// reports a non-default status appearance; left click toggles the shared
/// panel, right click shows Settings/Quit.
@MainActor final class StatusItemController: NSObject {
    private let host: ModuleHost
    private let statusItem: NSStatusItem
    private var hostCancellable: AnyCancellable?
    private var moduleCancellables: Set<AnyCancellable> = []
    private var styleObserver: NSObjectProtocol?
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
        }

        hostCancellable = host.$live
            .sink { [weak self] _ in self?.resubscribeToModules() }
        styleObserver = NotificationCenter.default.addObserver(
            forName: .helmMenuBarStyleChanged, object: nil, queue: .main
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
            live.vm.objectWillChange
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
    private var timerTick: Timer?

    private func scheduleTimerTick(active: Bool) {
        if active, timerTick == nil {
            timerTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshIcon() }
            }
        } else if !active, timerTick != nil {
            timerTick?.invalidate()
            timerTick = nil
        }
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        // First active module (non-nil tint) drives both the tint and an optional
        // active-state shape override.
        let appearance = host.enabledModules
            .map { $0.descriptor.statusAppearance($0.vm) }
            .first { $0.tintToken != nil } ?? .inactive
        let token = appearance.tintToken
        let globalStyle = MenuBarIconStyle(rawValue: AppSettings.menuBarIconStyle) ?? .ring
        let style = appearance.iconStyle.flatMap(MenuBarIconStyle.init(rawValue:)) ?? globalStyle
        let size = MenuBarIconSize(rawValue: AppSettings.menuBarIconSize) ?? .medium
        let progress = appearance.timerProgress
        scheduleTimerTick(active: progress != nil)
        // Modules emit state on every tick; only redraw when the glyph changes.
        // Progress is bucketed so a countdown redraws ~1% at a time, not per pixel.
        let bucket = progress.map { Int(($0 * 100).rounded()) }
        let title = appearance.title
        let key = "\(style.rawValue)|\(size.rawValue)|\(token ?? "")|\(bucket.map(String.init) ?? "-")|\(title ?? "")"
        guard key != lastIconKey else { return }
        lastIconKey = key
        button.image = RingIcon.make(style: style, size: size, tintToken: token, progress: progress)
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
        let menu = NSMenu()
        menu.addItem(withTitle: AppStr.settings, action: #selector(openSettings), keyEquivalent: "").target = self

        // Jump straight to a module's page instead of opening Settings and
        // hunting for it in the sidebar.
        menu.addItem(.separator())
        for descriptor in ModuleRegistry.all {
            let item = NSMenuItem(title: descriptor.moduleMetadata.name,
                                  action: #selector(openModuleSettings(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = descriptor.idRaw
            let symbol = NSImage(systemSymbolName: descriptor.moduleMetadata.sfSymbol,
                                 accessibilityDescription: nil)
            symbol?.size = NSSize(width: 15, height: 15)
            symbol?.isTemplate = true
            item.image = symbol
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: AppStr.quit, action: #selector(quit), keyEquivalent: "q").target = self

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

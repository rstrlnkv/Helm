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
                .sink { [weak self] _ in self?.refreshIcon() }
                .store(in: &moduleCancellables)
        }
        refreshIcon()
    }

    private var lastIconKey: String?

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
        // Modules emit state on every tick; only redraw when the glyph changes.
        let key = "\(style.rawValue)|\(size.rawValue)|\(token ?? "")"
        guard key != lastIconKey else { return }
        lastIconKey = key
        button.image = RingIcon.make(style: style, size: size, tintToken: token)
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
        menu.addItem(.separator())
        menu.addItem(withTitle: AppStr.quit, action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
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

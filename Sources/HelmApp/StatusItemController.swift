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

    private lazy var panel = HelmPanel(
        host: host,
        onOpenSettings: { [weak self] in self?.openSettings() },
        onQuit: { NSApp.terminate(nil) }
    )
    private lazy var settingsWindow = SettingsWindow(host: host)

    init(host: ModuleHost) {
        self.host = host
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = RingIcon.make(tintToken: nil)
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

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let token = host.enabledModules
            .compactMap { $0.descriptor.statusAppearance($0.vm).tintToken }
            .first
        let style = MenuBarIconStyle(rawValue: AppSettings.menuBarIconStyle) ?? .ring
        let size = MenuBarIconSize(rawValue: AppSettings.menuBarIconSize) ?? .medium
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
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import Carbon
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// Helm's own copy of the system's input-source indicator.
///
/// macOS shows one already, and its abbreviation cannot be changed: no flags,
/// no letter style, no size. This one is the same idea with those choices given
/// back — and it is off by default, because two identical indicators in a row
/// is worse than one.
@MainActor final class LanguageIndicator: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let store: NamespacedStore
    private var observer: NSObjectProtocol?

    init(store: NamespacedStore) {
        self.store = store
        super.init()
    }

    func refresh() {
        guard store.bool("indicator", default: false) else { teardown(); return }
        if item == nil { build() }
        redraw()
    }

    private func build() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.setAccessibilityLabel(LyStr.indicator)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        // The system posts this on every switch, including ones Helm made.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
    }

    private func teardown() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func redraw() {
        guard let button = item?.button else { return }
        let style = BadgeStyle.from(store.string("badgeStyle", default: BadgeStyle.plain.rawValue))
        let size = MenuBarIconSize(rawValue: store.string("badgeSize", default: "small")) ?? .small
        let source = InputSourceInfo.current()
        button.image = BadgeImage.make(label: source.badge, flag: source.emojiFlag,
                                       stripes: source.stripes, style: style,
                                       points: size.points)
        button.image?.isTemplate = (style == .plain)
        button.toolTip = source.name
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = InputSourceInfo.current()
        for source in InputSourceInfo.all() {
            let entry = NSMenuItem(title: source.name, action: #selector(pick(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = source.id
            entry.state = source.id == current.id ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: LyStr.openKeyboardSettings,
                                  action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        TISLayoutSources().select(id)
    }

    @objc private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

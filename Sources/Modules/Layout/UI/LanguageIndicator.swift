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
    private var themeObserver: NSObjectProtocol?

    init(store: NamespacedStore) {
        self.store = store
        super.init()
    }

    func refresh() {
        guard store.bool(LayoutKey.indicator, default: false) else { detach(); return }
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
        // The outline is one colour in dark and another in light, and the
        // image caches its rendering: without this the flag keeps the outline
        // of the theme it was drawn in until the next layout switch.
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
    }

    /// Off the menu bar, with its two observers. Called by `refresh` when the
    /// setting goes off and by the descriptor when the module stops running —
    /// which is one route more than this had: nothing removed the item when
    /// Keyboard was switched off.
    func detach() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
        observer = nil
        themeObserver = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    /// The one setting three sites read: the switch that draws it, the press
    /// that flips it, and the redraw that obeys it.
    private var showsName: Bool { store.bool(LayoutKey.indicatorShowsName, default: false) }

    private var badgeStyle: BadgeStyle {
        BadgeStyle.from(store.string(LayoutKey.badgeStyle, default: BadgeStyle.default.rawValue))
    }

    /// The badge and its template flag together — the pair the menu bar and
    /// every menu row draw, so the two cannot disagree about either half.
    private func badge(for source: InputSourceInfo, points: CGFloat) -> NSImage {
        let image = BadgeImage.make(label: source.badge, flag: source.emojiFlag,
                                    region: source.region, style: badgeStyle,
                                    points: points)
        image.isTemplate = (badgeStyle == .plain)
        return image
    }

    private func redraw() {
        guard let button = item?.button else { return }
        let source = InputSourceInfo.current()
        // The system input menu's «Show Input Source Name»: the layout's name
        // where the badge would be, which is what the system's own indicator
        // shows with that switch on.
        if showsName {
            button.image = nil
            button.title = source.name
        } else {
            let size = MenuBarIconSize(stored: store.string(LayoutKey.badgeSize, default: "small"))
            button.title = ""
            button.image = badge(for: source, points: size.points)
        }
        button.toolTip = source.name
        // The label says what the control is; the value says the one fact it
        // exists to show. Set here, not in build(), so it tracks every switch.
        button.setAccessibilityValue(source.name)
    }

    // MARK: - Menu

    /// The sections macOS's own input menu draws, in its order: layouts wearing
    /// their badges, the emoji palette door, the source-name switch, the
    /// keyboard settings door. No Keyboard Viewer item on purpose — every route
    /// to opening one was measured dead on macOS 27 (the guard test's doc has
    /// the three routes), and a door that opens nothing is worse than none.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = InputSourceInfo.current()
        // The rows wear the badge the person chose for the menu bar, at one
        // fixed size: the style is the layout's identity, the stored size is a
        // fact about the menu bar's density, not the menu's.
        for source in InputSourceInfo.all() {
            let entry = NSMenuItem(title: source.name, action: #selector(pick(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = source.id
            entry.state = source.id == current.id ? .on : .off
            entry.image = badge(for: source, points: MenuBarIconSize.small.points)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let emoji = actionItem(LyStr.showEmojiPanel(), #selector(openEmojiPalette))
        emoji.image = EmojiPalette.icon
        menu.addItem(emoji)
        menu.addItem(.separator())
        let name = actionItem(LyStr.showInputSourceName, #selector(toggleSourceName))
        name.state = showsName ? .on : .off
        menu.addItem(name)
        menu.addItem(.separator())
        menu.addItem(actionItem(LyStr.openKeyboardSettings, #selector(openSettings)))
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        TISLayoutSources().select(id)
    }

    /// The palette lands on whichever app holds the keyboard — a status-item
    /// menu does not take it away, and `EmojiPalette` never activates Helm, so
    /// the person's focus stays where they were typing. The beep is the
    /// refusal said out loud: without Accessibility, or in an app whose menus
    /// carry no such item, a silent press would look like a dead control.
    @objc private func openEmojiPalette() {
        if !EmojiPalette.openInFrontmostApp() { NSSound.beep() }
    }

    /// The write redraws by itself: `set` posts `.helmStoreChanged`, the
    /// descriptor's observer calls `refresh()`, and the indicator swaps badge
    /// for name — the same round trip any other window's write makes.
    @objc private func toggleSourceName() {
        store.set(!showsName, for: LayoutKey.indicatorShowsName)
    }

    @objc private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

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
    /// Whether this object is registered with the distributed centre — one
    /// `Bool` where two opaque tokens used to be, because the observer is
    /// `self` now rather than two blocks. See `build()` for why it had to be.
    private var observing = false
    private var frontmostWatch: UUID?
    /// The source id `redraw` last put on the button. Read by
    /// `menuNeedsUpdate` to catch a badge that has fallen behind the keyboard.
    private var drawn: String?
    /// Once per run — see `noteBadgeWasBehind`.
    private var saidBehind = false

    /// Whether Accessibility is granted, asked rather than assumed.
    ///
    /// **A port, not a call, because the answer decides how many sections the
    /// menu has.** `AXIsProcessTrusted()` inline would make the menu's shape a
    /// fact about the machine the suite runs on — green here, a different menu
    /// on a build machine, and no test able to see both. Named at every
    /// construction, the way every other port in this app is.
    private let isTrusted: () -> Bool

    init(store: NamespacedStore, isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.store = store
        self.isTrusted = isTrusted
        super.init()
        carryTheOldNameSettingOver()
    }

    /// «Show Input Source Name» used to be a key of its own, flipped from the
    /// status item's menu; it is `BadgeStyle.sourceName` now.
    ///
    /// **Deleting the key without this would take somebody's choice away in
    /// silence** — their menu bar goes back to a badge on the next launch with
    /// nothing said. Written once and erased in the same breath, so it cannot
    /// fight a style the person picks afterwards: the old key is gone from the
    /// store the first time this runs, and every later launch sees nothing to
    /// carry. This is the same failure the trigger switches had, caught before
    /// it shipped rather than after — a stored value outliving the only control
    /// that could change it.
    private func carryTheOldNameSettingOver() {
        guard store.bool(LayoutKey.indicatorShowsName, default: false) else { return }
        // `set(nil, for:)` is this store’s delete — there is no `remove`.
        store.set(nil, for: LayoutKey.indicatorShowsName)
        store.set(BadgeStyle.sourceName.rawValue, for: LayoutKey.badgeStyle)
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
        // **`.deliverImmediately`, and therefore the selector API.** The block
        // form of `addObserver` takes no suspension behaviour and gets the
        // default, which coalesces: while a centre is suspended it keeps at
        // most the last notification and delivers it on resume. Helm is
        // `LSUIElement` — it is never the active application — so its centre
        // spends nearly all its life suspended, and a layout switch made with
        // the person's own shortcut reached macOS and never reached the badge.
        // The badge then sat on one layout until Helm was restarted, which is
        // exactly the report this fixes: the reading was never wrong, the
        // message never came.
        let centre = DistributedNotificationCenter.default()
        // The system posts this on every switch, including ones Helm made.
        centre.addObserver(
            self, selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        // The outline is one colour in dark and another in light, and the
        // image caches its rendering: without this the flag keeps the outline
        // of the theme it was drawn in until the next layout switch. Suspension
        // hits this one the same way — a theme changed in the background was a
        // badge left in the old theme's outline.
        centre.addObserver(
            self, selector: #selector(themeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, suspensionBehavior: .deliverImmediately)
        observing = true
        // A second door to the same fact, through a channel that is not the
        // distributed centre at all: `FrontmostApp` is the app's own observer
        // of `NSWorkspace`'s activation notice. If the first door is ever shut
        // again the badge still comes right the next time the person changes
        // application, which is oftener than they look at it.
        frontmostWatch = FrontmostApp.shared.onChange { [weak self] _ in
            Task { @MainActor in self?.redraw() }
        }
    }

    @objc private func inputSourceChanged() { redraw() }

    @objc private func themeChanged() { redraw() }

    /// Off the menu bar, with its two observers. Called by `refresh` when the
    /// setting goes off and by the descriptor when the module stops running —
    /// which is one route more than this had: nothing removed the item when
    /// Keyboard was switched off.
    func detach() {
        if observing {
            DistributedNotificationCenter.default().removeObserver(self)
            observing = false
        }
        if let frontmostWatch { FrontmostApp.shared.stopWatching(frontmostWatch) }
        frontmostWatch = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        drawn = nil
    }

    /// Read off the style rather than a key of its own — see `BadgeStyle.isName`.
    private var showsName: Bool { badgeStyle.isName }

    private var badgeStyle: BadgeStyle {
        BadgeStyle.from(store.string(LayoutKey.badgeStyle, default: BadgeStyle.default.rawValue))
    }

    /// The badge and its template flag together — the pair the menu bar and
    /// every menu row draw, so the two cannot disagree about either half.
    private func badge(for source: InputSourceInfo, points: CGFloat) -> NSImage {
        let image = BadgeImage.make(label: source.badge, region: source.region, style: badgeStyle,
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
            // `.small` outright, which is what the menu rows below have always
            // drawn and what the removed setting defaulted to. It had a size
            // key of its own, four points wide end to end, beside the app's own
            // `menuBarIconSize` in General — two items in one menu bar sized by
            // two settings, with this one's own menu ignoring both.
            button.title = ""
            button.image = badge(for: source, points: MenuBarIconSize.small.points)
        }
        button.toolTip = source.name
        // The label says what the control is; the value says the one fact it
        // exists to show. Set here, not in build(), so it tracks every switch.
        button.setAccessibilityValue(source.name)
        drawn = source.id
    }

    /// Once per run: a badge that has fallen behind will keep falling behind,
    /// and a line every time somebody opens the menu would bury the log this
    /// belongs in.
    private func noteBadgeWasBehind() {
        guard !saidBehind else { return }
        saidBehind = true
        HelmLog.shared.warn(LayoutEngine.moduleID,
                            "the badge was behind the keyboard when the menu opened — "
                            + "the switch notification did not arrive")
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
        // **The evidence, and the reason this menu is where it is taken.** A
        // person opens this menu; Helm never does. So a badge disagreeing with
        // the live reading at this moment is the notification above having
        // failed to arrive and nothing else — no switch Helm made itself can
        // be mistaken for it. Correct the badge, and say so once.
        if current.id != drawn {
            noteBadgeWasBehind()
            redraw()
        }
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
        // **The emoji door, drawn only where it opens.** It is the one item
        // here that needs Accessibility — an AX press of *another* app's
        // Edit-menu item, matched by title out of `InputManager.loctable` —
        // and the settings page draws «the language indicator below works
        // without this permission» directly above the section that offers it.
        // That sentence is about the menu a person without the grant sees, so
        // the item is behind the grant rather than in front of it: without it
        // this menu is what it was, and nothing beeps in the state the sentence
        // was written for. Every Mac still opens the same palette with Globe+E.
        //
        // No Keyboard Viewer item beside it: macOS 27 ships no such input
        // source and no such bundle — the system's own menu draws it out of
        // private frameworks, and the class doc of
        // `TheIndicatorMenuFollowsTheSystemInputMenuTests` has the count.
        if isTrusted() {
            menu.addItem(.separator())
            let emoji = actionItem(LyStr.showEmojiPanel(), #selector(openEmojiPalette))
            emoji.image = EmojiPalette.icon
            menu.addItem(emoji)
        }
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
    /// the person's focus stays where they were typing. The beep is the refusal
    /// said out loud, and it is now a narrow one: the item is only drawn with
    /// the grant in hand, so what is left is an app whose menus carry no such
    /// item, where a silent press would look like a dead control.
    @objc private func openEmojiPalette() {
        if !EmojiPalette.openInFrontmostApp() { NSSound.beep() }
    }

    @objc private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

import AppKit
import ApplicationServices
import Carbon

/// Opens macOS's emoji palette over whichever app holds the keyboard.
///
/// No API does this from a menu-bar app on macOS 27.
/// `orderFrontCharacterPalette` shows the palette only for the calling app,
/// while it is active with a key window holding a text context, so from Helm
/// it is a silent no-op and activating Helm first steals focus and still shows
/// nothing. `TISSelectInputSource(com.apple.CharacterPaletteIM)` returns
/// `noErr` and draws no window. A synthesised shortcut is worse: the item's key
/// equivalent is Globe+E, and a forged Fn+E arrives as plain typing, putting a
/// letter into the person's document.
///
/// What works is what the person does by hand: the item AppKit puts in every
/// Edit menu. Pressing the focused app's own item over Accessibility runs the
/// action inside that app, so the palette anchors to its insertion point and
/// focus never moves. `LanguageIndicator` draws the item only when the grant
/// exists, so the settings page's «works without this permission» stays true
/// of the menu a person without the grant sees.
enum EmojiPalette {

    /// AppKit's own table for its input-related menu items — the one place
    /// macOS spells «Эмодзи и символы» in every language it ships.
    private static let loctable =
        "/System/Library/Frameworks/AppKit.framework/Resources/InputManager.loctable"

    /// Every spelling macOS gives the Edit-menu item, one per system language.
    ///
    /// All of them, not Helm's eight: the item being pressed belongs to another
    /// app, titled in whatever language *its* menus speak. The `LocProvenance`
    /// entry beside the languages is bookkeeping, and its values are not
    /// dictionaries of strings — the cast is what keeps it out. Read once: the
    /// table cannot change under a running system.
    static let systemNames: Set<String> = {
        let table = (NSDictionary(contentsOfFile: loctable) as? [String: Any]) ?? [:]
        var names: Set<String> = []
        for case let language as [String: String] in table.values {
            if let name = language["Emoji & Symbols"] { names.insert(name) }
        }
        return names
    }()

    /// The palette's own icon, the one the system input menu draws beside its
    /// emoji item: TIS's `kTISPropertyIconImageURL` for
    /// `com.apple.CharacterPaletteIM` — read, not redrawn. A template, so the
    /// menu colours it. Nil when macOS stops handing one out, and the guard
    /// test says so out loud rather than letting the door go bare silently.
    /// Read once: an input method's icon cannot change under a running system.
    static let icon: NSImage? = {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.CharacterPaletteIM"]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, true)
            .takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL)
        else { return nil }
        let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
        guard let image = NSImage(contentsOf: url.absoluteURL) else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Presses the frontmost app's own «Emoji & Symbols» item. False when
    /// macOS withholds Accessibility, when nothing is frontmost, or when the
    /// app's menus carry no such item — the caller says no the audible way.
    /// Reads `NSWorkspace.frontmostApplication` on main itself because it needs
    /// the pid, which `FrontmostApp` does not offer.
    @MainActor static func openInFrontmostApp() -> Bool {
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        // A hung app must not hang Helm's main thread with it.
        AXUIElementSetMessagingTimeout(app, 1)
        var bar: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar)
        guard let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        // Safe by the line above: the type was just checked, the way
        // `unsafeDowncast`'s own contract asks.
        let menuBar = unsafeDowncast(bar, to: AXUIElement.self)
        for menu in children(menuBar).flatMap(children) {
            for item in children(menu) where systemNames.contains(title(item)) {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return (value as? [AXUIElement]) ?? []
    }

    private static func title(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return (value as? String) ?? ""
    }
}

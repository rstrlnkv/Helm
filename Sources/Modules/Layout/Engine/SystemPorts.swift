import AppKit
import Carbon
import HelmRuntime

/// Marks every event Helm synthesises.
///
/// The tap drops anything carrying it. Without this the tap reads its own
/// replacement back as typing, converts it again, and does so forever.
private let helmEventMarker: Int64 = 0x48_45_4C_4D   // "HELM"

// MARK: - The tap

public final class CGKeyTap: KeyTapPort, @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    private var modifierHandler: (@Sendable (ModifierTap.Input) -> Void)?

    public init() {}

    public func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                      onModifier: @escaping @Sendable (ModifierTap.Input) -> Void) -> Bool {
        // Non-prompting: the module says so in its own settings rather than
        // throwing a system dialog at someone who has not asked for one.
        guard AXIsProcessTrusted() else { return false }
        handler = onEvent
        modifierHandler = onModifier
        // flagsChanged as well: a key bound on its own is recognised from the
        // press and the release, and neither is a keyDown.
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        // Listen-only: the tap reports keys and can neither delay nor swallow
        // them, so nothing Helm does here can freeze somebody's typing.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<CGKeyTap>.fromOpaque(refcon).takeUnretainedValue().deliver(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        handler = nil
        modifierHandler = nil
    }

    /// A modifier changed. Which physical key it was comes from the key code;
    /// whether it went down or up comes from its own device-dependent bit,
    /// because `.maskCommand` cannot tell the two Command keys apart and would
    /// read a release as a press whenever the other one is held.
    /// Device-dependent flag bits for every modifier key, both sides. The
    /// bindable right-side keys carry theirs in `TapKey`; the left-side bits
    /// live here because a left modifier must still *spoil* a tap — without
    /// them a left press arrived as a release, was never entered into the
    /// chord set, and left-⇧ right-⌘ fired the gesture mid-shortcut.
    private static let modifierMasks: [Int64: UInt64] = [
        54: 0x000010, 61: 0x000040, 62: 0x002000, 60: 0x000004,   // right ⌘ ⌥ ⌃ ⇧
        55: 0x000008, 58: 0x000020, 59: 0x000001, 56: 0x000002,   // left  ⌘ ⌥ ⌃ ⇧
        63: 0x800000,                                             // 🌐
    ]

    private func deliverModifier(_ event: CGEvent) {
        guard let handler = modifierHandler else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let at = ProcessInfo.processInfo.systemUptime
        if let mask = Self.modifierMasks[code] {
            let down = event.flags.rawValue & mask != 0
            if down {
                handler(.down(code, at: at))
                // A modifier already held when this key went down produced no
                // event of its own inside the tap's window, so the machine
                // could not know about it and the chord fired as a tap. The
                // live flags do know.
                let others = Self.modifierMasks.values
                    .filter { $0 != mask }
                    .contains { event.flags.rawValue & $0 != 0 }
                if others { handler(.otherInput) }
            } else {
                handler(.up(code, at: at))
            }
        } else {
            // Caps Lock, fn, anything else: not trackable by a bit of its
            // own, but its arrival still proves a chord is being typed.
            handler(.otherInput)
        }
    }

    private func deliver(_ event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) != helmEventMarker else { return }
        if event.type == .flagsChanged { deliverModifier(event); return }
        // Everything that is not a modifier proves a held modifier is being
        // used as one, so the tap machine hears about it before the buffer does.
        modifierHandler?(.otherInput)
        if event.type == .leftMouseDown { handler?(.click); return }

        // A command or control chord is not text. Without this, ⌘S appended an
        // "s" to the word and the next space converted the result — and the
        // module's own shortcut broke itself, because a head-inserted tap sees
        // the key before Carbon delivers the hotkey, so the letter was in the
        // buffer by the time "convert the last word" ran.
        // Option and shift alone still type — ⌥Z is "Ω" — so they cannot be
        // dropped wholesale. But a *global shortcut* on one of them is
        // swallowed by Carbon and never reaches the field, while the tap has
        // already put its character in the buffer: one backspace too many.
        // Anything the shortcut recorder would accept is treated as a chord.
        let flags = event.flags
        let modified = flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
        if modified {
            // A chord is not text, and it is not a confirmation either. ⌘Space
            // — the very gesture someone makes on noticing the wrong layout —
            // used to arrive as a plain space: the word was "confirmed", a
            // backspace was budgeted for a space that never reached the field,
            // and the character to its left was eaten. ⌘S appended an "s". ⌘V
            // changed the text underneath without saying what it now holds.
            //
            // `.navigation` covers all of it: the word ends, nothing is
            // confirmed, and the buffer stops describing a field it no longer
            // matches.
            handler?(.navigation)
            return
        }

        switch Int(event.getIntegerValueField(.keyboardEventKeycode)) {
        case kVK_Delete: handler?(.backspace)
        case kVK_Space: handler?(.space)
        case kVK_Return, kVK_ANSI_KeypadEnter: handler?(.newline)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Escape, kVK_Tab:
            handler?(.navigation)
        default:
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length,
                                           unicodeString: &characters)
            guard length > 0,
                  let character = String(utf16CodeUnits: characters, count: length).first
            else { return }
            handler?(character.isLetter ? .character(character) : .punctuation(character))
        }
    }
}

// MARK: - Typing

/// Backspaces, then the replacement as synthesised Unicode.
///
/// Not the clipboard: clipboard replacement fails in Electron and VS Code, and
/// it destroys whatever the user had copied.
public struct SynthesisTyping: TypingPort {
    public init() {}

    public func perform(_ plan: SwitchPlan) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        source.userData = helmEventMarker

        for _ in 0..<plan.backspaces {
            guard let down = CGEvent(keyboardEventSource: source,
                                     virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source,
                                   virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
            else { return false }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        for character in plan.insert {
            var utf16 = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}

// MARK: - Input sources

/// One place that reads the Text Input Sources list, because every other port
/// here needs the same lookup.
enum InputSources {
    static func all() -> [TISInputSource] {
        (TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    static func identifier(of source: TISInputSource) -> String? {
        string(source, kTISPropertyInputSourceID)
    }

    static func source(id: String) -> TISInputSource? {
        all().first { identifier(of: $0) == id }
    }

    static func string(_ source: TISInputSource, _ key: CFString!) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String)
    }
}

public struct TISLayoutSources: LayoutSourcePort {
    public init() {}

    public func installed() -> [String] {
        // Keyboard layouts only: an input method (Chinese, Japanese) composes
        // rather than maps, and has no key table to translate through.
        InputSources.all()
            .filter { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) != nil }
            .compactMap(InputSources.identifier(of:))
    }

    public func current() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return nil }
        return InputSources.identifier(of: source)
    }

    public func select(_ sourceID: String) {
        guard let match = InputSources.source(id: sourceID) else { return }
        TISSelectInputSource(match)
    }
}

// MARK: - Translation

/// The same key presses read through another layout, via `UCKeyTranslate`
/// against the layouts actually installed — a hard-coded ЙЦУКЕН↔QWERTY table
/// would support exactly two layouts and silently mangle a third.
public struct UCTranslation: TranslationPort {
    public init() {}

    public func translate(_ word: String, from: String, to: String) -> String? {
        guard let fromTable = Self.characterTable(from),
              let toTable = Self.characterTable(to) else { return nil }
        var out = ""
        for character in word {
            // `Character(_:)` traps on a string that is not one grapheme, and
            // uppercasing is not one-to-one: "ß".uppercased() is "SS". A crash
            // inside a keyboard hook takes the whole app down, so the string
            // form is appended as it comes.
            guard let lower = character.lowercased().first,
                  let code = fromTable.first(where: { $0.value == lower })?.key,
                  let mapped = toTable[code] else { return nil }
            out.append(character.isUppercase ? mapped.uppercased() : String(mapped))
        }
        return out
    }

    /// keyCode → the character it types, for the printable letter range.
    /// Cached: building it walks fifty keys through Carbon, and it changes only
    /// when the installed layouts do.
    private static let cache = TableCache()

    private final class TableCache: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: [UInt16: Character]] = [:]

        func table(_ sourceID: String, build: () -> [UInt16: Character]?) -> [UInt16: Character]? {
            lock.lock()
            if let cached = tables[sourceID] { lock.unlock(); return cached }
            lock.unlock()
            guard let built = build() else { return nil }
            lock.lock(); tables[sourceID] = built; lock.unlock()
            return built
        }
    }

    private static func characterTable(_ sourceID: String) -> [UInt16: Character]? {
        // The keyboard type is baked into the table by `UCKeyTranslate`, so it
        // belongs in the key: plugging in an ISO keyboard where an ANSI one was
        // leaves every cached table describing the wrong hardware.
        cache.table("\(sourceID)#\(LMGetKbdType())") { buildTable(sourceID) }
    }

    private static func buildTable(_ sourceID: String) -> [UInt16: Character]? {
        guard let source = InputSources.source(id: sourceID),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var table: [UInt16: Character] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return }
            for code in UInt16(0)...UInt16(50) {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0,
                                            UInt32(LMGetKbdType()),
                                            UInt32(kUCKeyTranslateNoDeadKeysMask),
                                            &deadKeyState, 4, &length, &characters)
                guard status == noErr, length > 0,
                      let character = String(utf16CodeUnits: characters, count: length).first,
                      character.isLetter else { continue }
                table[code] = character
            }
        }
        return table.isEmpty ? nil : table
    }
}

// MARK: - Spelling

/// The system's own dictionaries. Nil means "no dictionary for this language" —
/// which is not the same as "not a word", and must never be read as one.
public struct SystemSpell: SpellPort {
    public init() {}

    public func isWord(_ word: String, sourceID: String) -> Bool? {
        guard let language = Self.language(for: sourceID) else { return nil }
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains(where: { $0.hasPrefix(language) })
        else { return nil }
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language,
                                          wrap: false, inSpellDocumentWithTag: 0,
                                          wordCount: nil)
        return range.location == NSNotFound
    }

    /// "com.apple.keylayout.Russian" → "ru".
    private static func language(for sourceID: String) -> String? {
        guard let source = InputSources.source(id: sourceID),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
        else { return nil }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return languages?.first
    }
}

// MARK: - Secure context

/// The system's own alert sound, not one of ours: it is already at the volume
/// the user chose for such things, and it stops when they mute alerts.
public struct SystemSound: SoundPort {
    private let name: String

    public init(name: String = "Tink") { self.name = name }

    public func playSwitch() { NSSound(named: name)?.play() }
}

public struct AXSecureContext: SecureContextPort {
    public init() {}

    public func isSecureInput() -> Bool { IsSecureEventInputEnabled() }

    public func isSecure() -> Bool {
        // System-wide secure input: the tap gets nothing anyway, and saying so
        // is what lets the UI explain the silence.
        if isSecureInput() { return true }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }
        // The type ID was checked on the line above, so this cannot be wrong —
        // but a trapping cast on the keystroke path would take the app down
        // mid-sentence if that check ever moved, and this one cannot trap.
        let axElement = unsafeBitCast(element, to: AXUIElement.self)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement,
                                            kAXRoleAttribute as CFString, &role) == .success
        else { return false }
        // The constant is not exported to Swift; this is the value AppKit uses.
        return (role as? String) == "AXSecureTextField"
    }

    public func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}

// MARK: - Selection

/// The selected text, through the accessibility tree where the app answers and
/// through the clipboard where it does not.
///
/// Two routes because neither covers the machine. `AXSelectedText` is exact,
/// instantaneous and leaves nothing behind — and a great many apps do not
/// implement it: Electron ones, most web views, some of Apple's own. The
/// fallback is ⌘C: it works nearly everywhere and it costs the clipboard, so it
/// is second and it puts back what it borrowed.
public struct AXSelection: SelectionPort {
    public init() {}

    public func selectedText() -> String? {
        if let text = axSelection(), !text.isEmpty { return text }
        return copySelection()
    }

    public func selectedTextWithoutClipboard() -> String? {
        guard let text = axSelection(), !text.isEmpty else { return nil }
        return text
    }

    public func replaceSelection(with text: String) -> Bool {
        if setAXSelection(text) { return true }
        // Read before pasting, so the paste route has something to compare
        // against and can tell whether the app took it.
        let before = axSelection()
        return pasteSelection(text, replacing: before)
    }

    // MARK: The exact route

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focused
        else { return nil }
        // The same `unsafeBitCast` the rest of this file uses: a `CFTypeRef`
        // that is an `AXUIElement` is one, and a conditional cast of a CF type
        // through `as?` is the thing Swift 6 will not do.
        return unsafeBitCast(focused, to: AXUIElement.self)
    }

    private func axSelection() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            &value) == .success,
              let text = value as? String
        else { return nil }
        return text
    }

    private func setAXSelection(_ text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            text as CFTypeRef) == .success
    }

    // MARK: The clipboard route

    /// ⌘C, read, and put back what was there.
    ///
    /// The restore is not politeness: somebody's clipboard is theirs, and a
    /// shortcut that quietly eats it is a shortcut people stop using. The
    /// change count is what tells us the copy actually happened — a selection
    /// of nothing leaves the pasteboard untouched, and reading it then would
    /// return whatever was already on it and transliterate *that*.
    private func copySelection() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let before = pasteboard.changeCount

        send(key: CGKeyCode(kVK_ANSI_C))
        guard waitForChange(from: before) else {
            restore(saved)
            return nil
        }
        let copied = pasteboard.string(forType: .string)
        restore(saved)
        return copied
    }

    /// Returns whether the app took the text, as far as this route can tell.
    ///
    /// It used to return `true` always. In an app where ⌘V is not paste — a
    /// terminal, a game, a modal that swallows it — Helm clobbered the
    /// clipboard, restored it, played the success sound and reported a change
    /// that never happened. There is no receipt for a synthesised keystroke, so
    /// what is checked is the one thing that can be: whether the app read the
    /// pasteboard at all. `changeCount` does not move on a read, but the
    /// selection does — if the tree still reports exactly what was selected
    /// before, nothing replaced it.
    private func pasteSelection(_ text: String, replacing previous: String?) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        send(key: CGKeyCode(kVK_ANSI_V))
        // Long enough for the paste to have been read, short enough not to be
        // felt. Restoring too early puts the old text back before the app has
        // taken the new one, and the person pastes their own clipboard.
        usleep(120_000)
        restore(saved)
        // Unreadable tree: no evidence either way, so do not claim failure on a
        // paste that probably worked. Claiming success is the bug being fixed;
        // claiming failure here would only trade it for the opposite one.
        guard let now = axSelection() else { return true }
        return now != previous
    }

    private func restore(_ saved: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }
    }

    /// Polled rather than slept: a fast app answers in a few milliseconds and a
    /// slow one gets its 200, instead of everyone waiting for the slow one.
    private func waitForChange(from before: Int) -> Bool {
        for _ in 0..<20 {
            usleep(10_000)
            if NSPasteboard.general.changeCount != before { return true }
        }
        return false
    }

    private func send(key: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.userData = helmEventMarker
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

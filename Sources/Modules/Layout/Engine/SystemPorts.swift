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

    public init() {}

    public func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void) -> Bool {
        // Non-prompting: the module says so in its own settings rather than
        // throwing a system dialog at someone who has not asked for one.
        guard AXIsProcessTrusted() else { return false }
        handler = onEvent
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
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
    }

    private func deliver(_ event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) != helmEventMarker else { return }
        if event.type == .leftMouseDown { handler?(.click); return }

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
            let lower = Character(character.lowercased())
            guard let code = fromTable.first(where: { $0.value == lower })?.key,
                  let mapped = toTable[code] else { return nil }
            out.append(character.isUppercase ? Character(mapped.uppercased()) : mapped)
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
        cache.table(sourceID) { buildTable(sourceID) }
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

public struct AXSecureContext: SecureContextPort {
    public init() {}

    public func isSecure() -> Bool {
        // System-wide secure input: the tap gets nothing anyway, and saying so
        // is what lets the UI explain the silence.
        if IsSecureEventInputEnabled() { return true }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXRoleAttribute as CFString, &role) == .success
        else { return false }
        // The constant is not exported to Swift; this is the value AppKit uses.
        return (role as? String) == "AXSecureTextField"
    }

    public func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}

import AppKit
import Carbon
import HelmRuntime

/// Marks every event Helm synthesises.
///
/// The tap drops anything carrying it. Without this the tap reads its own
/// replacement back as typing, converts it again, and does so forever.
///
/// **It is the only guard, on every path.** Every `perform` runs on main (the
/// automatic path inside the tap callback, the gesture and the hotkey after
/// `fix()`'s hop back to main), and the tap, on the main run loop, hears the
/// echo only after `perform` has returned. A flag set around `perform` would
/// always be down by then, so there is none.
let helmEventMarker: Int64 = 0x48_45_4C_4D   // "HELM"

/// One source for every event this module posts, so the marker is set in one place.
private func helmEventSource() -> CGEventSource? {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
    source.userData = helmEventMarker
    return source
}

// MARK: - The tap

/// The live keyboard tap.
///
/// **The pointer CoreGraphics holds does not own this object, and that is
/// deliberate.** `userInfo` is a raw pointer with no retain/release callbacks —
/// unlike `SCDynamicStoreContext`, which is why the VPN watcher can hand its
/// sink over and let the framework hold it. Handing this one over `passRetained`
/// would mean the tap keeps the object alive until the port is invalidated, and
/// the only thing that invalidates the port is this object's own teardown: an
/// unbreakable cycle, in which a module the user switched off goes on reading
/// every keystroke for the life of the process.
///
/// So the pointer stays unretained, and the object gets a `deinit` — which is
/// reachable precisely *because* nothing retains `self` (Architecture/StateAndLifetime.md § State that outlives a page and ends with its module).
/// Without it, any path that drops the engine other than `deactivate()` —
/// `bootstrap()` replacing it, the module let go at quit — leaves an enabled
/// tap on the main run loop resolving a freed pointer: a crash in
/// `swift_retain` under `eventTapMessageHandler`.
///
/// `CFMachPortInvalidate` fixes a separate thing: the port caches the run loop
/// source it creates and the source retains the port, so without it neither is
/// ever freed. It does **not** prevent the crash — stopping without it already
/// stops delivery.
///
/// `CFRunLoop` is the one thread-safe CoreFoundation type, so removing the
/// source from whatever thread `deinit` happens to run on is supported and
/// needs no hop to main. The fields do need a lock: this is `@unchecked
/// Sendable`, the callback reads the handlers on the run loop that services the
/// port, and `stop()` clears them.
public final class CGKeyTap: KeyTapPort, @unchecked Sendable {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    private var modifierHandler: (@Sendable (ModifierTap.Input) -> Void)?
    /// Told when this tap stops without being asked to. Read out before
    /// `stop()` clears the handlers, because standing down is the one case where
    /// the teardown and the announcement are the same moment.
    private var diedHandler: (@Sendable () -> Void)?

    /// Synchronous readers rather than `await`, because Swift 6 refuses `NSLock.lock()` across a
    /// suspension, and a field read on one side of a lock is a field read with no lock at all.
    private var handlers: ((@Sendable (TypingBuffer.Event) -> Void)?,
                           (@Sendable (ModifierTap.Input) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        return (handler, modifierHandler)
    }

    public init() {}

    /// The live tap's mach port name, for the teardown test and nothing else.
    /// The test asserts about *this* name rather than counting the task's whole
    /// namespace, which moves with every XPC connection and thread the rest of
    /// the process creates inside the measurement window.
    var portName: mach_port_name_t? { lock.withLock { tap.map { CFMachPortGetPort($0) } } }

    /// The backstop. `deactivate()` is the ordinary route; this covers every
    /// other way the port can be let go.
    deinit { stop() }

    /// `KeyTapPort.start`'s contract. The tap is **listen-only**: it reports keys
    /// and can neither delay nor swallow them, so nothing Helm does here can
    /// freeze somebody's typing. Accessibility is asked without prompting.
    public func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                      onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
                      died: @escaping @Sendable () -> Void) -> Bool {
        // Non-prompting: the module says so in its own settings rather than
        // throwing a system dialog at someone who has not asked for one.
        guard AXIsProcessTrusted() else { return false }
        install(onEvent, onModifier: onModifier, died: died)
        // flagsChanged as well: a key bound on its own is recognised from the
        // press and the release, and neither is a keyDown.
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<CGKeyTap>.fromOpaque(refcon).takeUnretainedValue().deliver(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lock.lock()
        self.tap = tap
        self.source = source
        lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Sets the handlers `deliver` calls, with no tap. `start` calls it; a test
    /// calls it too, then hands `deliver` events it built and never posted.
    func install(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                 onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
                 died: @escaping @Sendable () -> Void) {
        lock.lock()
        handler = onEvent
        modifierHandler = onModifier
        diedHandler = died
        lock.unlock()
    }

    /// Idempotent, because `deinit` runs it again after `deactivate()` already
    /// has, and invalidating a port twice is not free of consequence.
    public func stop() {
        // Taken out under the lock and torn down outside it, the shape
        // `DynamicStoreNetworkWatch.stopObserving` uses: nothing that can call
        // back into this object runs with the lock held.
        lock.lock()
        let tap = self.tap
        let source = self.source
        self.tap = nil
        self.source = nil
        handler = nil
        modifierHandler = nil
        diedHandler = nil
        lock.unlock()

        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        // Not optional, and last: the port holds the run loop source it made and
        // the source holds the port, so releasing our references frees neither.
        CFMachPortInvalidate(tap)
    }

    /// Device-dependent flag bits for every modifier key, both sides, from
    /// `TapKey`. Whether a modifier went down or up comes from its own bit,
    /// because `.maskCommand` cannot tell the two Command keys apart and would
    /// read a release as a press whenever the other one is held.
    ///
    /// Every key is in it, not only the bindable one: a modifier on the other
    /// side must still *spoil* a tap, or left-⇧ right-⌘ fires the gesture
    /// mid-shortcut.
    private static let modifierMasks = TapKey.masksByKeyCode

    /// macOS has taken the tap away. `TapDisabled` says what that means.
    ///
    /// Both disabling event types type no characters, so without this Layout
    /// would stop converting and say nothing. A timeout needs no permission
    /// change: when a word is judged the callback asks the accessibility server
    /// whether the field is secure, and one slow app in front is enough to get
    /// the tap switched off for the rest of the session.
    private func theSystemDisabledUs() {
        lock.lock(); let tap = self.tap; let died = self.diedHandler; lock.unlock()
        guard let tap else { return }
        switch TapDisabled.response(stillTrusted: AXIsProcessTrusted()) {
        case .enableItAgain:
            CGEvent.tapEnable(tap: tap, enable: true)
            HelmLog.shared.warn(LayoutEngine.moduleID,
                                "the system switched the keyboard tap off; back on")
        case .standDown:
            stop()
            HelmLog.shared.warn(LayoutEngine.moduleID,
                                "the accessibility grant was withdrawn — no longer watching")
            // Read before `stop()` and called after it: standing down clears the
            // handlers, and the engine has to hear about it or it will believe
            // this tap is alive until the process ends.
            died?()
        }
    }

    private func deliverModifier(_ event: CGEvent, _ handler: @Sendable (ModifierTap.Input) -> Void) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let at = ProcessInfo.processInfo.systemUptime
        if let mask = Self.modifierMasks[code] {
            let down = event.flags.rawValue & mask != 0
            if down {
                // Whether anything else is held comes from this event's own
                // flags. Nothing is remembered between events, so a release
                // that never arrives cannot disable the gesture for good.
                let others = Self.modifierMasks.values
                    .filter { $0 != mask }
                    .contains { event.flags.rawValue & $0 != 0 }
                handler(.down(code, at: at, othersHeld: others))
            } else {
                handler(.up(code, at: at))
            }
        } else {
            // Caps Lock, fn, anything else: not trackable by a bit of its
            // own, but its arrival still proves a chord is being typed.
            handler(.otherInput)
        }
    }

    func deliver(_ event: CGEvent) {
        // Before the marker check, not after: the system's own "I have switched
        // this tap off" carries no source data, and it is the one event that
        // must never be dropped.
        if TapDisabled.disables(event.type) { theSystemDisabledUs(); return }
        guard event.getIntegerValueField(.eventSourceUserData) != helmEventMarker else { return }
        // Both read once, under the lock, before anything is dispatched: a
        // `stop()` landing between the two would otherwise deliver half an event.
        let (handler, modifierHandler) = handlers
        if event.type == .flagsChanged {
            if let modifierHandler { deliverModifier(event, modifierHandler) }
            return
        }
        // Everything that is not a modifier proves a held modifier is being
        // used as one, so the tap machine hears about it before the buffer does.
        modifierHandler?(.otherInput)
        if event.type == .leftMouseDown { handler?(.click); return }

        // A command or control chord is not text: ⌘S would append an "s" to the
        // word, and a head-inserted tap sees the module's own hotkey before
        // Carbon delivers it, so its letter would be in the buffer by then.
        // Option and shift alone still type — ⌥Z is "Ω" — so they cannot be
        // dropped wholesale. But a *global shortcut* on one of them is
        // swallowed by Carbon and never reaches the field, while the tap has
        // already put its character in the buffer: one backspace too many.
        // Anything the shortcut recorder would accept is treated as a chord.
        let flags = event.flags
        let modified = flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
        // The ordering is `TapEvent.classify`, pure so a test can ask it: a key
        // held with ⌘, ⌥ or ⌃ is a chord unless it moves the caret or deletes
        // backwards, ⌥Delete included. ⌘Space read as a plain space would
        // confirm a word and budget a backspace for a space the field never got.
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if let classified = TapEvent.classify(keycode: code, modified: modified) {
            handler?(classified)
            return
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length,
                                       unicodeString: &characters)
        guard length > 0,
              let character = String(utf16CodeUnits: characters, count: length).first
        else { return }
        // **Not «is this a letter», but «is this key a letter anywhere».**
        // `,` types `б` in Russian, `;` types `ж`, `[` types `х` — and
        // punctuation confirms a word, so on a latin layout `cgfcb,j` would be
        // cut at the comma.
        //
        // A Mac with only latin layouts installed answers false for every mark,
        // and the comma goes on ending an English sentence's last word.
        let letter = character.isLetter
            || UCTranslation.letterKeys(installed: TISLayoutSources().installed())
                .contains(UInt16(code))
        handler?(letter ? .character(character) : .punctuation(character))
    }
}

// MARK: - Typing

/// Backspaces, then the replacement as synthesised Unicode.
///
/// Not the clipboard: clipboard replacement fails in Electron and VS Code, and
/// it destroys whatever the user had copied.
public struct SynthesisTyping: TypingPort {
    public init() {}

    /// **Every event is built before any of them is posted.**
    ///
    /// `CGEvent(keyboardEventSource:virtualKey:keyDown:)` is a failable
    /// allocation that can answer nil on its own. Posted before the replacement
    /// is built, the deletes could leave the word gone, nothing typed, and
    /// `false` read by every caller as «the app refused, nothing happened» —
    /// the partial retype `TypingPort.perform` promises never to make.
    /// `SystemCommandKeys.press` in this file builds first for the same reason.
    ///
    /// **It does not make the plan atomic against the app**, and cannot: the
    /// events go to the HID tap and whatever is in front may stop reading them
    /// halfway. What it removes is the half that is this port's own doing.
    public func perform(_ plan: SwitchPlan) -> Bool {
        guard let events = Self.events(for: plan) else { return false }
        for event in events { event.post(tap: .cghidEventTap) }
        return true
    }

    /// Every event for the plan, built and none posted; nil when any one could
    /// not be built.
    static func events(for plan: SwitchPlan) -> [CGEvent]? {
        guard let source = helmEventSource() else { return nil }
        return events(for: plan) { CGEvent(keyboardEventSource: source, virtualKey: $0, keyDown: $1) }
    }

    /// The building and the clearing, with the event factory a parameter so a test
    /// can hand it events that carry the live modifier state.
    static func events(for plan: SwitchPlan,
                       make: (CGKeyCode, Bool) -> CGEvent?) -> [CGEvent]? {

        var events: [CGEvent] = []
        events.reserveCapacity(plan.backspaces * 2 + plan.insert.count * 2)

        for _ in 0..<plan.backspaces {
            guard let down = make(CGKeyCode(kVK_Delete), true),
                  let up = make(CGKeyCode(kVK_Delete), false)
            else { return nil }
            // **Cleared, not inherited — this is the one that eats words.**
            // `CGEventSource(stateID: .combinedSessionState)` carries the *live*
            // modifier state, and the gesture is a tap of a modifier: if the
            // person is still holding ⌥ when these go out, every one of them is
            // ⌥Delete, which removes a whole word rather than a character, and
            // a word beside the conversion disappears. ⌘ would be worse: a
            // synthesised ⌘-letter is a menu command in whatever is in front.
            //
            // `SystemCommandKeys.press` in this file sets `.maskCommand` on purpose, which is
            // what proves these are inherited rather than empty by default.
            down.flags = []
            up.flags = []
            events.append(down)
            events.append(up)
        }

        for character in plan.insert {
            var utf16 = Array(String(character).utf16)
            guard let down = make(0, true), let up = make(0, false)
            else { return nil }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            // The same reason, and the worse half: a held ⌘ turns each of these
            // into a menu command in the app in front, and a held ⌥ can change
            // what the key means before the unicode string is read.
            down.flags = []
            up.flags = []
            events.append(down)
            events.append(up)
        }

        return events
    }
}

// MARK: - Input sources

/// One place that reads the Text Input Sources list, because every other port
/// here needs the same lookup — and so does the module's own menu-bar
/// indicator, which is why this is public rather than internal.
public enum InputSources {
    /// The language tags the source declares, most specific first; empty when it names none.
    public static func languages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
        else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
    }

    public static func all() -> [TISInputSource] {
        (TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    /// Keyboard layouts only: an input method (Chinese, Japanese) composes
    /// rather than maps, and has no key table to translate through or to name a
    /// language badge from.
    public static func keyboardLayouts() -> [TISInputSource] {
        all().filter { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) != nil }
    }

    public static func identifier(of source: TISInputSource) -> String? {
        string(source, kTISPropertyInputSourceID)
    }

    public static func source(id: String) -> TISInputSource? {
        all().first { identifier(of: $0) == id }
    }

    /// The layout the keyboard is on **now**.
    ///
    /// **Not `TISCopyCurrentKeyboardInputSource` first.** It answers out of
    /// per-process state that HIToolbox refreshes as the process handles the
    /// system's notification, and it can stop tracking: macOS switches layout
    /// and the process reads the previous one until it restarts. The menu-bar
    /// badge and the conversions share this reader, so both would freeze.
    ///
    /// A fresh `TISCreateInputSourceList` and the source that says it is
    /// selected cannot go stale: the list is built on the call. It costs a list
    /// walk, asked once per completed word rather than per keystroke.
    ///
    /// The cached call stays as the fallback, because with an input method in
    /// front — Japanese, Chinese — no *keyboard layout* need report itself
    /// selected, and an answer from the cache beats no answer at all. When the
    /// two disagree the log says so once.
    public static func current() -> TISInputSource? {
        let cached = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        guard let live = selected() else { return cached }
        if let cached, identifier(of: cached) != identifier(of: live) {
            noteDisagreement()
        }
        return live
    }

    /// The enabled keyboard layout whose own `kTISPropertyInputSourceIsSelected`
    /// is true, read off a list built on this call.
    public static func selected() -> TISInputSource? {
        keyboardLayouts().first { flag($0, kTISPropertyInputSourceIsSelected) == true }
    }

    /// Once per run, not once per word: a stale cache stays stale, so a line
    /// every time somebody types would bury the log it belongs in. A lock and a
    /// `Bool` rather than anything from `HelmRuntime` — nothing there does
    /// «say it once», and one log guard is not shared plumbing.
    private static let saidLock = NSLock()
    nonisolated(unsafe) private static var said = false

    private static func noteDisagreement() {
        saidLock.lock()
        let first = !said
        said = true
        saidLock.unlock()
        guard first else { return }
        HelmLog.shared.warn(LayoutEngine.moduleID,
                            "macOS's cached current layout disagrees with the selected one — "
                            + "reading the live list from here on")
    }

    private static func flag(_ source: TISInputSource, _ key: CFString!) -> Bool? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    public static func string(_ source: TISInputSource, _ key: CFString!) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String)
    }
}

public struct TISLayoutSources: LayoutSourcePort {
    public init() {}

    public func installed() -> [String] {
        InputSources.keyboardLayouts().compactMap(InputSources.identifier(of:))
    }

    public func current() -> String? {
        InputSources.current().flatMap(InputSources.identifier(of:))
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

    /// The tables are this type's business; what a string becomes is
    /// `KeyRemap`'s, where a test can reach it without a keyboard.
    public func translate(_ word: String, from: String, to: String) -> String? {
        guard let fromTable = Self.characterTable(from),
              let toTable = Self.characterTable(to) else { return nil }
        return KeyRemap.map(word, from: fromTable, to: toTable)
    }

    /// keyCode → the character it types, for the printable letter range.
    /// Cached: building it walks fifty keys through Carbon, and it changes only
    /// when the installed layouts do.
    private static let cache = LockedMemo<String, [UInt16: Character]>()

    /// Which keys type a letter in some installed layout.
    ///
    /// Built over the same cached tables the translation uses, and cached in
    /// turn: the tap asks this on every keystroke, on the thread that must not
    /// be busy. The keyboard type is in the key for the reason it is in the
    /// table's.
    static func letterKeys(installed: [String]) -> LetterKeys {
        let id = installed.sorted().joined(separator: ",") + "#\(LMGetKbdType())"
        return letterKeyCache.valueOrNothing(for: id) {
            LetterKeys(tables: installed.compactMap { characterTable($0) })
        } ?? LetterKeys(tables: [])
    }

    private static let letterKeyCache = LockedMemo<String, LetterKeys>()

    private static func characterTable(_ sourceID: String) -> [UInt16: Character]? {
        // The keyboard type is baked into the table by `UCKeyTranslate`, so it
        // belongs in the key: plugging in an ISO keyboard where an ANSI one was
        // leaves every cached table describing the wrong hardware.
        cache.valueOrNothing(for: "\(sourceID)#\(LMGetKbdType())") { buildTable(sourceID) }
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
                      // Not `isLetter`. A key is only «punctuation» in the
                      // layout you happen to be holding: `,` types `б` in
                      // Russian, `;` types `ж`, `[` types `х`. Letters only
                      // would leave those letters with no key, in most
                      // non-latin layouts.
                      //
                      // Whitespace stays out: a space is the same key in every
                      // layout, and admitting it would let a word boundary
                      // translate into a letter.
                      !character.isWhitespace else { continue }
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
        guard let source = InputSources.source(id: sourceID) else { return nil }
        return InputSources.languages(of: source).first
    }
}

// MARK: - Secure context

/// The system's own alert sound, not one of ours: it is already at the volume
/// the user chose for such things, and it stops when they mute alerts.
public struct SystemSound: SoundPort {
    public init() {}

    /// On the main thread, wherever it is called from: AppKit is not a thing to
    /// touch from whichever queue a caller happens to be on.
    public func playSwitch() {
        if Thread.isMainThread { NSSound(named: "Tink")?.play(); return }
        DispatchQueue.main.async { NSSound(named: "Tink")?.play() }
    }
}

public struct AXSecureContext: SecureContextPort {
    public init() {}

    public func isSecureInput() -> Bool { IsSecureEventInputEnabled() }

    public func isSecure() -> Bool {
        // System-wide secure input: the tap gets nothing anyway, and saying so
        // is what lets the UI explain the silence.
        if isSecureInput() { return true }
        guard let axElement = systemFocusedElement() else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement,
                                            kAXRoleAttribute as CFString, &role) == .success
        else { return false }
        // The constant is not exported to Swift; this is the value AppKit uses.
        return (role as? String) == "AXSecureTextField"
    }

    /// Through the snapshot, never straight to AppKit: the gesture asks from a
    /// background queue, and `NSWorkspace` off the main thread takes the process
    /// down (Architecture/RunningOtherPrograms.md § Running applications).
    public func frontmostBundleID() -> String { FrontmostApp.shared.bundleID() }
}

// MARK: - Selection

/// The selected text, through the accessibility tree; written back through the
/// tree where the app answers and through the clipboard where it does not.
///
/// Reading has one route. `AXSelectedText` is exact, instantaneous and leaves
/// nothing behind, and an app whose tree says nothing is treated as having no
/// selection. Writing keeps its fallback: the tree first, and ⌘V where the app
/// refuses.
public struct AXSelection: SelectionPort {
    private let pasteboard: any PasteboardPort
    private let focus: any FocusedTextPort
    private let keys: any CommandKeyPort

    public init() {
        self.init(pasteboard: SystemPasteboard(), focus: SystemFocusedText(), keys: SystemCommandKeys())
    }

    init(pasteboard: any PasteboardPort, focus: any FocusedTextPort, keys: any CommandKeyPort) {
        self.pasteboard = pasteboard
        self.focus = focus
        self.keys = keys
    }

    public func selectedTextWithoutClipboard() -> String? {
        guard let text = focus.selectedText(), !text.isEmpty else { return nil }
        return text
    }

    public func replaceSelection(with text: String) -> Bool {
        if focus.setSelectedText(text) { return true }
        // The paste route borrows the clipboard and can only give back a
        // string. Anything else on it — an image, RTF, a promised file — does
        // not survive the round trip, so if the clipboard holds something Helm
        // cannot put back, do not touch it.
        //
        // Declining is a correct outcome. The caller reports it, and the
        // person still has both their selection and their clipboard.
        let held = pasteboard.types
        guard PasteboardSafety.canBorrow(types: held) else {
            HelmLog.shared.warn(LayoutEngine.moduleID,
                                "selection left alone: the clipboard holds \(held.count) type(s) " +
                                "that would not survive being borrowed")
            return false
        }
        // Read before pasting, so the paste route has something to compare
        // against and can tell whether the app took it.
        let before = focus.selectedText()
        return pasteSelection(text, replacing: before)
    }

    // MARK: The clipboard route

    /// Returns whether the app took the text, as far as this route can tell.
    ///
    /// In an app where ⌘V is not paste — a terminal, a game, a modal that
    /// swallows it — an unconditional `true` reports a change that never
    /// happened. There is no receipt for a synthesised keystroke, so what is
    /// checked is whether the selection moved: if the tree still reports
    /// exactly what was selected before, nothing replaced it.
    private func pasteSelection(_ text: String, replacing previous: String?) -> Bool {
        let saved = pasteboard.string()
        pasteboard.clear()
        pasteboard.setString(text)
        keys.press(UInt16(kVK_ANSI_V))
        // Long enough for the paste to have been read, short enough not to be
        // felt. Restoring too early puts the old text back before the app has
        // taken the new one, and the person pastes their own clipboard.
        usleep(120_000)
        restore(saved)
        // Unreadable tree: no evidence either way, so do not claim failure on a
        // paste that probably worked.
        guard let now = focus.selectedText() else { return true }
        return now != previous
    }

    private func restore(_ saved: String?) {
        pasteboard.clear()
        if let saved { pasteboard.setString(saved) }
    }
}

/// The general pasteboard, as `AXSelection`'s clipboard route uses it.
struct SystemPasteboard: PasteboardPort {
    var types: [String] { NSPasteboard.general.types?.map(\.rawValue) ?? [] }
    func string() -> String? { NSPasteboard.general.string(forType: .string) }
    func clear() { NSPasteboard.general.clearContents() }
    func setString(_ text: String) { NSPasteboard.general.setString(text, forType: .string) }
}

/// The focused element's selected text, through the accessibility tree.
struct SystemFocusedText: FocusedTextPort {
    func selectedText() -> String? {
        guard let element = systemFocusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            &value) == .success,
              let text = value as? String
        else { return nil }
        return text
    }

    func setSelectedText(_ text: String) -> Bool {
        guard let element = systemFocusedElement() else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            text as CFTypeRef) == .success
    }
}

/// ⌘ plus one key, posted with Helm's marker.
struct SystemCommandKeys: CommandKeyPort {
    func press(_ key: UInt16) {
        guard let source = helmEventSource(),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Whatever has keyboard focus anywhere on the system.
///
/// The type ID is checked before the bitcast: a conditional cast of a CF type
/// is what Swift 6 will not do, and a trapping cast on the keystroke path
/// would take the app down mid-sentence.
private func systemFocusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    // **A second is the ceiling.** This is the one AX read on the keystroke
    // path: `AXSecureContext.isSecure` goes through it, `emitState` calls that,
    // and `emitState` runs from the tap's own callback — on main, where macOS
    // kills a callback that takes too long (`TapDisabled`). The system-wide
    // element's default messaging timeout is the global one, and a frozen app
    // in front would have Helm wait it out with the keyboard in its hands.
    //
    // A refusal here is the safe direction: no focused element reads as «not a
    // secure field», and the cheap `IsSecureEventInputEnabled` check that runs
    // first is the one that catches the login window.
    AXUIElementSetMessagingTimeout(system, 1)
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system,
                                        kAXFocusedUIElementAttribute as CFString,
                                        &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(element, to: AXUIElement.self)
}

// MARK: - AppActivation

/// `AppActivationPort` on the notification centre and `FrontmostApp`.
///
/// The frontmost watch goes through `FrontmostApp` rather than an `NSWorkspace`
/// observer of its own: that type is the app's single observer of the
/// activation notice and exists because `NSWorkspace` is main-thread-only.
///
/// Tokens are dropped before new ones are taken, not overwritten:
/// `FrontmostApp.shared` is a process-wide singleton whose watchers are never
/// pruned, so two starts in a row would leave the first registered, and
/// unstoppable once its token was lost. A block observer does not remove
/// itself either, and switching the module off and on would stack another each
/// time. `deinit` takes them back too.
public final class AppActivation: AppActivationPort, @unchecked Sendable {
    private let lock = NSLock()
    private var activeObserver: NSObjectProtocol?
    private var frontmostWatch: UUID?

    public init() {}

    deinit { stopObserving() }

    public func startObserving(helmBecameActive: @escaping @Sendable () -> Void,
                               frontmostChanged: @escaping @Sendable (String) -> Void) {
        stopObserving()
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in helmBecameActive() }
        let watch = FrontmostApp.shared.onChange(frontmostChanged)
        lock.lock()
        activeObserver = observer
        frontmostWatch = watch
        lock.unlock()
    }

    public func stopObserving() {
        lock.lock()
        let observer = activeObserver, watch = frontmostWatch
        activeObserver = nil
        frontmostWatch = nil
        lock.unlock()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let watch { FrontmostApp.shared.stopWatching(watch) }
    }
}

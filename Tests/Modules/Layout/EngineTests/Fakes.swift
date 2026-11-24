import Foundation
import HelmRuntime
@testable import Module_Layout_Engine

// The Layout engine's port fakes, one file: typing, secure context, sound,
// translation, spell, key tap, layout sources, selection and app activation. A
// fake keeps the port's states only, and every construction names the port it
// stands in for (Architecture/TestsAndMeasurement.md § Fakes).

/// The chord bound as «fix» in the suites that need a recorded shortcut. Only the
/// recorded one ends a word and leaves it remembered: every other chord may have
/// changed the text in front of the caret — ⌘V pastes, ⌥V types `√` — so the word
/// before it is dropped. Any code will do; what matters is that the engine has one.
let layoutShortcut: UInt16 = 9

/// An in-memory store under the module's own namespace, with `layoutShortcut`
/// recorded as the «fix» chord when `bound`.
func layoutStore(bound: Bool = false) -> NamespacedStore {
    let store = NamespacedStore(namespace: LayoutEngine.moduleID, backing: InMemoryKeyValueStore())
    if bound { store.set(Int(layoutShortcut), for: HotkeyStoreKeys(prefix: LayoutHotkey.storePrefix).keyCode) }
    return store
}

/// The port's states and nothing else: observing or not, how many times it was
/// asked to start, and the two moments the port delivers.
///
/// `observing` is a Bool and not a count because `AppActivationPort.startObserving`
/// *replaces* an earlier registration: after two starts one registration is
/// left, which a Bool says and a counter would not. `starts` is the other half
/// (how many times the engine asked). A handler runs only while observing, as
/// the real port's does; the real port delivers on the main thread, the fake
/// delivers on the caller's, which is the one place it is simpler than the port
/// and why `TheActivationPortKeepsOneWatchTests` also drives the real one.
final class FakeActivation: AppActivationPort, @unchecked Sendable {
    private let lock = NSLock()
    private var helmActive: (@Sendable () -> Void)?
    private var frontmost: (@Sendable (String) -> Void)?
    private var startCount = 0

    /// True between a start and a stop.
    var observing: Bool { lock.withLock { helmActive != nil || frontmost != nil } }
    /// How many times the engine asked the port to start.
    var starts: Int { lock.withLock { startCount } }

    func startObserving(helmBecameActive: @escaping @Sendable () -> Void,
                        frontmostChanged: @escaping @Sendable (String) -> Void) {
        lock.withLock {
            startCount += 1
            helmActive = helmBecameActive
            frontmost = frontmostChanged
        }
    }

    func stopObserving() {
        lock.withLock { helmActive = nil; frontmost = nil }
    }

    /// Helm itself came to the front; nothing when not observing.
    func helmComesToTheFront() {
        let handler = lock.withLock { helmActive }
        handler?()
    }

    /// Another application came to the front; nothing when not observing.
    func comesToTheFront(_ bundleID: String) {
        let handler = lock.withLock { frontmost }
        handler?(bundleID)
    }
}

/// Records the plans it is given, behind a lock: the engine types from its own
/// thread while a test reads. `succeeds` is one flag because the believed contract
/// is that the port did the whole plan or none of it; `false` means none.
/// `apply` carries a plan that went through out against something the test holds
/// (a field's text), which is what answers «what is in the field now».
final class FakeTyping: TypingPort, @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [SwitchPlan] = []
    var performed: [SwitchPlan] { lock.withLock { plans } }
    var succeeds = true
    var apply: (@Sendable (SwitchPlan) -> Void)?
    func perform(_ plan: SwitchPlan) -> Bool {
        lock.withLock { plans.append(plan) }
        guard succeeds else { return false }
        apply?(plan)
        return true
    }
}

/// The secure-context port with its two halves kept apart, as the port keeps
/// them: `isSecureInput` is the cheap system-wide syscall (`systemWideSecure`, also
/// spelled `secure`), `isSecure` also recognises a password field by its
/// accessibility role (`passwordField`) — an Electron login form, a web field the
/// browser did not escalate for. Folding them into one flag would make «the field
/// that took focus is a password field» a state no test could write down.
///
/// Every field is behind one lock: some suites write the front app from the
/// read's own thread and read it from the one that types. `mainReads` counts who
/// was asked in front **from the main queue**, and `onExpensiveCheck` fires once,
/// at the accessibility round trip `isSecure` stands for.
final class FakeSecure: SecureContextPort, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBundle: String
    private var storedSystemWide = false
    private var storedPasswordField = false
    private var storedMainReads = 0
    private var storedOnExpensiveCheck: (@Sendable () -> Void)?

    init(bundle: String = "com.apple.Notes") { storedBundle = bundle }

    var bundle: String {
        get { lock.withLock { storedBundle } }
        set { lock.withLock { storedBundle = newValue } }
    }
    var systemWideSecure: Bool {
        get { lock.withLock { storedSystemWide } }
        set { lock.withLock { storedSystemWide = newValue } }
    }
    /// The same flag under the name most suites know it by.
    var secure: Bool {
        get { systemWideSecure }
        set { systemWideSecure = newValue }
    }
    var passwordField: Bool {
        get { lock.withLock { storedPasswordField } }
        set { lock.withLock { storedPasswordField = newValue } }
    }
    var onExpensiveCheck: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnExpensiveCheck } }
        set { lock.withLock { storedOnExpensiveCheck = newValue } }
    }
    var mainReads: Int { lock.withLock { storedMainReads } }

    func isSecureInput() -> Bool { systemWideSecure }
    func isSecure() -> Bool {
        let (answer, announce): (Bool, (@Sendable () -> Void)?) = lock.withLock {
            let announce = storedOnExpensiveCheck
            storedOnExpensiveCheck = nil
            return (storedSystemWide || storedPasswordField, announce)
        }
        announce?()
        return answer
    }
    func frontmostBundleID() -> String {
        let onMain = Thread.isMainThread
        return lock.withLock {
            if onMain { storedMainReads += 1 }
            return storedBundle
        }
    }
}

/// Counts the sounds played, for the suites where one is audible.
final class FakeSound: SoundPort, @unchecked Sendable {
    var played = 0
    func playSwitch() { played += 1 }
}

/// The translation port, configured by what the scenario needs it to say.
///
/// `table` is a word to its translation whatever the pair; `byDirection` is keyed
/// `"from>to"` first, because the selection path asks both ways round and a table
/// that ignores the pair cannot tell the two apart — the real `UCTranslation` reads
/// two different layouts and can answer nil for one of them. `sameLength` answers
/// Cyrillic of the same grapheme count for a word nobody listed, for suites about
/// how many characters a plan deletes or where a word ends, not about which words a
/// dictionary knows. `otherwise` is asked last, for the one scenario whose answer
/// is a rule and not a list.
struct FakeTranslation: TranslationPort {
    var table: [String: String] = [:]
    var byDirection: [String: [String: String]] = [:]
    var sameLength = false
    var otherwise: (@Sendable (_ word: String, _ from: String, _ to: String) -> String?)?

    func translate(_ word: String, from: String, to: String) -> String? {
        if let known = byDirection["\(from)>\(to)"]?[word] ?? table[word] { return known }
        if let ruled = otherwise?(word, from, to) { return ruled }
        return sameLength && !word.isEmpty ? String(repeating: "п", count: word.count) : nil
    }
}

/// The spell port, configured by what the scenario needs it to say.
///
/// `valid` is the dictionary. `noDictionary` lists the layouts the Mac has no
/// dictionary for: the answer there is nil, which the port's contract says must
/// never be read as «not a word». `cyrillic` makes every word in Cyrillic a word
/// and a word in Latin only when it is listed: the shape of a real mislayout,
/// without a dictionary — the layout path asks whether a *Cyrillic* translation is
/// a word, the capital fix whether a *Latin* correction is one, which a fake that
/// said «no» to every Latin word could not be asked.
struct FakeSpell: SpellPort {
    var valid: Set<String> = []
    var noDictionary: Set<String> = []
    var cyrillic = false

    func isWord(_ word: String, sourceID: String) -> Bool? {
        if noDictionary.contains(sourceID) { return nil }
        if cyrillic && word.unicodeScalars.allSatisfy({ $0.value > 0x400 }) { return true }
        return valid.contains(word)
    }
}

/// A tap that can be in the three states the real one can: watching, refused
/// for want of the grant, and stopped by macOS behind the app's back.
///
/// `start` used to return `true` unconditionally, so «macOS would not give us a
/// tap» and «macOS took the tap away» were states no test could write down — which
/// is why the second one shipped as a page that said «Active» with nobody listening
/// (Architecture/ModulePattern.md § Ports and logic).
final class FakeTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
    private var died: (@Sendable () -> Void)?
    /// Whether Accessibility is granted. False is a refusal, exactly as
    /// `AXIsProcessTrusted()` failing is.
    var grant = true
    /// How many taps have been asked for — the difference between «it was
    /// rebuilt» and «the engine still believes in the first one».
    var starts: Int { lock.withLock { startCount } }
    private let lock = NSLock()
    private var startCount = 0
    /// What the app received of each key typed, before the tap reports it: the
    /// keystroke reaches the app and then the tap, the order `SwitchPlan` is
    /// written for.
    var received: (@Sendable (Character) -> Void)?

    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { startCount += 1 }
        guard grant else { return false }
        handler = onEvent
        modifiers = onModifier
        self.died = died
        return true
    }

    /// The grant is withdrawn mid-session: macOS disables the tap and the port
    /// stands down, which is a teardown the engine did not ask for.
    func macOSTakesItAway() {
        grant = false
        let announce = died
        stop()
        died = nil
        announce?()
    }
    func stop() { handler = nil; modifiers = nil }
    func type(_ text: String) { for character in text { received?(character); handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
    func space() { received?(" "); handler?(.space) }
}

/// A keyboard that is actually on the layout it was switched to.
///
/// `current()` used to answer `"en"` for ever, whatever `select()` had been
/// told — so "convert, then convert the next word back" was unrepresentable:
/// the engine reads `current()` at the top of every conversion, and in a test
/// the second one always started from where the first one had. No test could
/// have covered the sequence, whatever anybody wrote.
///
/// Shared rather than private: every Layout test that needs a keyboard takes this
/// one, so a fix to it reaches all of them. KeepAwake and VPN keep theirs in a
/// `Fakes.swift` the same way.
final class FakeSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    private var live: String
    /// Whether `current()` follows `select()`. False is a keyboard that stays on
    /// where it was whatever it is told, and remembers what it was told: for
    /// suites where the engine's own reading of `current()` must not change under it.
    private let follows: Bool
    init(current: String = "en", follows: Bool = true) { self.live = current; self.follows = follows }
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { live }
    func select(_ sourceID: String) { selected.append(sourceID); if follows { live = sourceID } }
}

/// The accessibility tree's selection and its replace, the port's states and nothing
/// else: the text selected, or none, and whether the app takes the replacement. A
/// refused replace records nothing, as the port changes nothing. Behind a lock:
/// the gesture reads and writes from its own thread while a test looks.
final class FakeSelection: SelectionPort, @unchecked Sendable {
    private let lock = NSLock()
    private var storedText: String?
    private var storedReplaced: [String] = []
    private var storedReads = 0
    private var storedOnReplace: (@Sendable () -> Void)?
    var accepts = true
    /// Run *inside* the read, which is where the real port spends its time: an
    /// accessibility round trip. Whatever the person does to their Mac in that
    /// window happens here.
    var whileReading: (@Sendable () -> Void)?

    init(_ text: String? = nil) { storedText = text }

    var text: String? {
        get { lock.withLock { storedText } }
        set { lock.withLock { storedText = newValue } }
    }
    var replaced: [String] { lock.withLock { storedReplaced } }
    /// How many times the tree was read.
    var reads: Int { lock.withLock { storedReads } }
    /// Fired once, at the first accepted replace.
    var onReplace: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnReplace } }
        set { lock.withLock { storedOnReplace = newValue } }
    }

    func selectedTextWithoutClipboard() -> String? {
        let answer: String? = lock.withLock { storedReads += 1; return storedText }
        whileReading?()
        return answer
    }

    func replaceSelection(with text: String) -> Bool {
        guard accepts else { return false }
        let announce: (@Sendable () -> Void)? = lock.withLock {
            storedReplaced.append(text)
            let announce = storedOnReplace
            storedOnReplace = nil
            return announce
        }
        announce?()
        return true
    }
}

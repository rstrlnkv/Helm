import Foundation
@testable import Module_Layout_Engine

// The Layout engine's port fakes, one file: typing, secure context, translation,
// spell, key tap, layout sources and app activation. A fake keeps the port's states
// only, and every construction names the port it stands in for
// (Architecture/TestsAndMeasurement.md § Fakes).

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

final class FakeTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    var succeeds = true
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return succeeds }
}

final class FakeSecure: SecureContextPort, @unchecked Sendable {
    var secure = false
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { secure }
    func isSecure() -> Bool { secure }
    func frontmostBundleID() -> String { bundle }
}

struct FakeTranslation: TranslationPort {
    let table: [String: String]
    func translate(_ word: String, from: String, to: String) -> String? { table[word] }
}

struct FakeSpell: SpellPort {
    let valid: Set<String>
    func isWord(_ word: String, sourceID: String) -> Bool? { valid.contains(word) }
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
    var starts = 0

    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        starts += 1
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
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
    func space() { handler?(.space) }
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
    init(current: String = "en") { self.live = current }
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { live }
    func select(_ sourceID: String) { selected.append(sourceID); live = sourceID }
}

/// Every layout the engine can reach is a word in Cyrillic, and a word in Latin
/// only when it is listed: the shape of a real mislayout, without a dictionary.
///
/// The layout path asks whether a *Cyrillic* translation is a word; the capital
/// fix asks whether a *Latin* correction is one, which a fake that said «no» to
/// every Latin word could not be asked. A fake that cannot be in a state the
/// port can be in cannot fail the way the port can.
struct CyrillicSpell: SpellPort {
    var latin: Set<String> = []
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 } || latin.contains(word)
    }
}

/// Latin in, Cyrillic of the same grapheme count out, unless `table` knows the
/// word: for suites about how many characters a plan deletes or where a word
/// ends, not about which words a dictionary knows.
struct SameLengthTranslation: TranslationPort {
    var table: [String: String] = [:]
    func translate(_ word: String, from: String, to: String) -> String? {
        if let known = table[word] { return known }
        return word.isEmpty ? nil : String(repeating: "п", count: word.count)
    }
}

/// A keyboard that stays on «en» whatever `select()` is told, and remembers what
/// it was told. `FakeSources` is the one that follows; this one is for suites
/// where the engine's own reading of `current()` must not change under it.
final class StuckSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) { selected.append(sourceID) }
}

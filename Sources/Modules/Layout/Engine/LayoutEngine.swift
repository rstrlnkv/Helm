import AppKit
import Foundation
import HelmContract
import HelmRuntime

/// Wires the ports to the logic. Holds no rules of its own: every decision is
/// made by a unit in `Logic/`, so it can be checked without typing.
public final class LayoutEngine: ModuleEngine, @unchecked Sendable {
    private let tap: KeyTapPort
    private let typing: TypingPort
    private let sources: LayoutSourcePort
    private let translation: TranslationPort
    private let spell: SpellPort
    private let secure: SecureContextPort
    private let sound: SoundPort?
    /// Absent in tests, where the values are injected directly.
    private let settings: NamespacedStore?
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// The tap delivers on its own run-loop source while the transport delivers
    /// on a concurrency pool; both touch everything below.
    private let lock = NSLock()
    private var buffer = TypingBuffer()
    /// The word that most recently ended, kept so "convert the last word" has
    /// something to work with: the shortcut is itself a chord, and a chord ends
    /// the word before the Carbon handler for it ever runs.
    private var lastCompleted: TypingBuffer.Completion?
    private var activeObserver: NSObjectProtocol?
    private var undo: UndoRecord?
    private var scope: AppScope
    private var exceptions: Exceptions
    private var automatic: Bool
    private var triggers: ConversionTriggers
    private var audible: Bool
    /// The single key bound to "fix / put it back", if any.
    private var tapKey = ModifierTap(key: .off)
    private var conversions = 0
    private var running = false
    /// Whether the tap is live. Without the grant `start` returns false, and
    /// that answer is what the settings page shows.
    private var tapped = false
    private var starting = false
    /// Set while performing a conversion, so the keystrokes it sends are not
    /// read back as typing. The marker on the events is the first line of
    /// defence; this is the second, for anything the marker misses.
    private var performing = false

    public init(tap: KeyTapPort,
                typing: TypingPort,
                sources: LayoutSourcePort,
                translation: TranslationPort,
                spell: SpellPort,
                secure: SecureContextPort,
                sound: SoundPort? = nil,
                rules: [String: Bool] = [:],
                exceptions: [String] = [],
                automatic: Bool = true,
                triggers: ConversionTriggers = .default,
                audible: Bool = false,
                settings: NamespacedStore? = nil,
                transport: LocalTransport = LocalTransport()) {
        self.tap = tap
        self.typing = typing
        self.sources = sources
        self.translation = translation
        self.spell = spell
        self.secure = secure
        self.sound = sound
        self.scope = AppScope(rules: rules)
        self.exceptions = Exceptions(words: exceptions)
        self.automatic = automatic
        self.triggers = triggers
        self.audible = audible
        self.settings = settings
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    // MARK: - Module lifecycle

    public func activate() {
        lock.lock(); running = true; lock.unlock()
        startTap()
        // Permission is usually granted while Helm is already running — the
        // note in settings sends people to System Settings and they come back.
        // Without this the tap stayed dead until the next launch, which is the
        // same "switch that looks like it works" defect the note exists to
        // prevent.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.startTap() }
        }
        emitState()
    }

    /// Idempotent: starts the tap only while it is not already running, so
    /// coming back to the app a hundred times costs nothing.
    private func startTap() {
        // Claimed inside the lock, not merely checked: two starts would build
        // two taps and leave the first one enabled on the run loop, doubling
        // every keystroke.
        lock.lock()
        guard running, !tapped, !starting else { lock.unlock(); return }
        starting = true
        lock.unlock()
        let started = tap.start({ [weak self] event in self?.handle(event) },
                                onModifier: { [weak self] input in self?.handleModifier(input) })
        lock.lock(); tapped = started; starting = false; lock.unlock()
        if started {
            HelmLog.shared.info("layout", "watching for mislayout words")
        } else {
            HelmLog.shared.warn("layout", "no accessibility grant — not watching")
        }
        emitState()
    }

    public func deactivate() {
        // Block observers do not remove themselves, and turning the module off
        // and on again would stack another one each time.
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        tap.stop()
        lock.lock()
        running = false; tapped = false
        buffer.clear(); undo = nil; lastCompleted = nil   // the third place a word lives
        lock.unlock()
        emitState()
    }

    // MARK: - The pipeline

    private func handle(_ event: TypingBuffer.Event) {
        // The cheap half of the secure check, on every key rather than at the
        // word boundary: a password typed without spaces would otherwise sit in
        // the buffer until the next one. No AX call here — this is one syscall.
        if secure.isSecureInput() {
            // All three places a word lives, as in deactivate: a retained
            // lastCompleted could later be typed back by the hotkey into
            // whatever field happens to be focused.
            lock.lock(); buffer.clear(); undo = nil; lastCompleted = nil; lock.unlock()
            return
        }
        lock.lock()
        guard !performing else { lock.unlock(); return }
        // Typing, clicking and leaving end the chance to undo: an undo is a
        // blind edit of a fixed length, and "привет abc" undone becomes
        // "приghbdtn ". A chord is the exception, and not a convenient one —
        // the undo shortcut *is* a chord, it reaches the tap before Carbon
        // delivers it, and treating it like the rest meant the shortcut
        // destroyed its own precondition and could never fire once.
        switch event {
        case .navigation: undo?.soften()
        default: undo?.invalidate()
        }
        let finished = buffer.accept(event)
        let auto = automatic
        let confirms = triggers.converts(event)
        lock.unlock()
        // Ended and meant are different things: leaving the word by clicking or
        // moving the caret ends it without asking for a conversion.
        // A click or a focus change means the person went somewhere else, and
        // converting then types six backspaces into wherever the caret is now —
        // possibly an hour later. A chord does not: the shortcut itself is one,
        // and it must not destroy its own input.
        switch event {
        case .click, .focusChange:
            lock.lock(); lastCompleted = nil; lock.unlock()
        default:
            if let finished { lock.lock(); lastCompleted = finished; lock.unlock() }
        }
        guard auto, confirms, let completed = finished else { return }
        convert(completed.word, trailing: completed.ending, force: false)
    }

    /// `force` is the hotkey: the user asked for this word by name, so the
    /// dictionary's opinion is not consulted. The secure checks still are.
    private func convert(_ word: String, trailing: Character?, force: Bool) {
        let bundleID = secure.frontmostBundleID()
        lock.lock(); let allowed = scope.allows(bundleID); lock.unlock()
        guard allowed else { return }
        guard !secure.isSecure() else {
            lock.lock(); buffer.clear(); lock.unlock()
            emitState()
            return
        }
        guard let from = sources.current(),
              let to = sources.installed().first(where: { $0 != from }),
              let translated = translation.translate(word, from: from, to: to)
        else { return }

        let replacement: String
        if force {
            guard !translated.isEmpty, translated != word else { return }
            replacement = translated
        } else {
            guard let typedIsWord = spell.isWord(word, sourceID: from),
                  let translatedIsWord = spell.isWord(translated, sourceID: to)
            else { return }
            lock.lock(); let list = exceptions.words; lock.unlock()
            guard case .convert(let candidate) = LayoutVerdict.decide(
                word: word, translated: translated,
                validAsTyped: typedIsWord, validTranslated: translatedIsWord,
                exceptions: list) else { return }
            replacement = candidate
        }

        guard let plan = SwitchPlan.make(replacing: word, with: replacement,
                                         trailing: trailing) else { return }
        // The port's own contract says a refusal means the text was not
        // replaced. Switching the input source, recording an undo and counting
        // a success on top of that would be the app claiming work it did not do.
        guard perform(plan) else {
            HelmLog.shared.warn("layout", "the app refused the replacement")
            return
        }
        sources.select(to)
        lock.lock(); let announce = audible; lock.unlock()
        if announce { sound?.playSwitch() }
        lock.lock()
        undo = UndoRecord(event: ConversionEvent(before: word, after: replacement,
                                                 app: bundleID,
                                                 trailing: trailing.map(String.init) ?? ""))
        conversions += 1
        lock.unlock()
        // Counts, never content: the words themselves stay out of the log.
        HelmLog.shared.info("layout", "converted a word in \(Redact.app(bundleID))")
        emitState()
    }

    /// One key, pressed and released on its own, does both jobs in turn.
    ///
    /// Two shortcuts for "fix this word" and "no, put it back" are two things
    /// to remember for one thought. So the key answers with whichever of them
    /// makes sense: if the last change is still undoable here, undo it;
    /// otherwise convert. Tapping twice therefore converts and converts back,
    /// which is the behaviour anyone who has used Punto Switcher expects, and
    /// the same key keeps working as a modifier because a tap is only a tap
    /// when nothing else was pressed with it.
    private func handleModifier(_ input: ModifierTap.Input) {
        lock.lock()
        let fired = tapKey.feed(input)
        lock.unlock()
        guard fired else { return }
        let bundleID = secure.frontmostBundleID()
        lock.lock()
        let undoable = undo?.canUndo(in: bundleID) ?? false
        lock.unlock()
        if undoable { undoLast() } else { convertLastWord() }
    }

    /// Puts the last conversion back, if the caret can still be where it was.
    public func undoLast() {
        let bundleID = secure.frontmostBundleID()
        lock.lock()
        guard let record = undo, record.canUndo(in: bundleID),
              let plan = record.reversePlan() else { lock.unlock(); return }
        undo = nil
        lock.unlock()
        perform(plan)
        emitState()
    }

    /// Converts whatever is in the buffer right now, whatever the dictionary
    /// thinks — the hotkey path.
    public func convertLastWord() {
        lock.lock()
        let live = buffer.word
        let previous = lastCompleted
        lock.unlock()
        if !live.isEmpty {
            // Mid-word: nothing ended it, so there is nothing extra to delete.
            convert(live, trailing: nil, force: true)
        } else if let previous {
            convert(previous.word, trailing: previous.ending, force: true)
        }
    }

    /// Re-reads what the settings page wrote. The page owns the store; the
    /// engine owns the behaviour, and this is the one line between them.
    private func reloadSettings() {
        guard let settings else { return }
        let rules = settings.boolTable("appRules")
        lock.lock()
        automatic = settings.bool("automatic", default: true)
        exceptions = Exceptions(words: settings.stringArray("exceptions"))
        scope = AppScope(rules: rules)
        audible = settings.bool("audible", default: false)
        tapKey = ModifierTap(key: TapKey.from(settings.string("tapKey", default: TapKey.off.rawValue)))
        triggers = ConversionTriggers(onSpace: settings.bool("onSpace", default: ConversionTriggers.default.onSpace),
                                      onReturn: settings.bool("onReturn", default: ConversionTriggers.default.onReturn),
                                      onPunctuation: settings.bool("onPunctuation", default: ConversionTriggers.default.onPunctuation))
        lock.unlock()
        emitState()
    }

    @discardableResult
    private func perform(_ plan: SwitchPlan) -> Bool {
        lock.lock(); performing = true; lock.unlock()
        let done = typing.perform(plan)
        lock.lock(); performing = false; buffer.clear(); lastCompleted = nil; lock.unlock()
        return done
    }

    // MARK: - Transport

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "undoLastConversion": self.undoLast()
            case "convertLastWord": self.convertLastWord()
            case "settingsChanged": self.reloadSettings()
            default: break
            }
            return Data()
        }
    }

    private func emitState() {
        // Outside the lock: `isSecure` reaches the accessibility server, and a
        // hung app there blocks for the messenger's timeout. Holding the lock
        // across it would freeze the tap callback — which runs on main.
        let suspended = secure.isSecure()
        lock.lock()
        let state = LayoutState(enabled: tapped, automatic: automatic,
                                suspended: suspended,
                                lastConversion: undo?.event,
                                conversionsToday: conversions)
        lock.unlock()
        if let data = try? JSONEncoder().encode(state) {
            localTransport.emit(EngineEvent(name: "layoutState", payload: data))
        }
    }
}

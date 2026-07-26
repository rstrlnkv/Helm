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
    /// Absent in tests, where the values are injected directly.
    private let settings: NamespacedStore?
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// The tap delivers on its own run-loop source while the transport delivers
    /// on a concurrency pool; both touch everything below.
    private let lock = NSLock()
    private var buffer = TypingBuffer()
    private var undo: UndoRecord?
    private var scope: AppScope
    private var exceptions: Exceptions
    private var automatic: Bool
    private var triggers: ConversionTriggers
    private var conversions = 0
    private var running = false
    /// Whether the tap is live. Without the grant `start` returns false, and
    /// that answer is what the settings page shows.
    private var tapped = false
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
                rules: [String: Bool] = [:],
                exceptions: [String] = [],
                automatic: Bool = true,
                triggers: ConversionTriggers = .default,
                settings: NamespacedStore? = nil,
                transport: LocalTransport = LocalTransport()) {
        self.tap = tap
        self.typing = typing
        self.sources = sources
        self.translation = translation
        self.spell = spell
        self.secure = secure
        self.scope = AppScope(rules: rules)
        self.exceptions = Exceptions(words: exceptions)
        self.automatic = automatic
        self.triggers = triggers
        self.settings = settings
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    // MARK: - Module lifecycle

    public func activate() {
        running = true
        startTap()
        // Permission is usually granted while Helm is already running — the
        // note in settings sends people to System Settings and they come back.
        // Without this the tap stayed dead until the next launch, which is the
        // same "switch that looks like it works" defect the note exists to
        // prevent.
        NotificationCenter.default.addObserver(
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
        lock.lock()
        guard running, !tapped else { lock.unlock(); return }
        lock.unlock()
        let started = tap.start { [weak self] event in self?.handle(event) }
        lock.lock(); tapped = started; lock.unlock()
        if started {
            HelmLog.shared.info("layout", "watching for mislayout words")
        } else {
            HelmLog.shared.warn("layout", "no accessibility grant — not watching")
        }
        emitState()
    }

    public func deactivate() {
        tap.stop()
        lock.lock(); running = false; tapped = false; buffer.clear(); undo = nil; lock.unlock()
        emitState()
    }

    // MARK: - The pipeline

    private func handle(_ event: TypingBuffer.Event) {
        lock.lock()
        guard !performing else { lock.unlock(); return }
        // Anything that could have moved the caret ends the chance to undo.
        if case .character = event {} else { undo?.invalidate() }
        let finished = buffer.accept(event)
        let auto = automatic
        let confirms = triggers.converts(event)
        lock.unlock()
        // Ended and meant are different things: leaving the word by clicking or
        // moving the caret ends it without asking for a conversion.
        guard auto, confirms, let word = finished else { return }
        convert(word, force: false)
    }

    /// `force` is the hotkey: the user asked for this word by name, so the
    /// dictionary's opinion is not consulted. The secure checks still are.
    private func convert(_ word: String, force: Bool) {
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

        guard let plan = SwitchPlan.make(replacing: word, with: replacement) else { return }
        perform(plan)
        sources.select(to)
        lock.lock()
        undo = UndoRecord(event: ConversionEvent(before: word, after: replacement, app: bundleID))
        conversions += 1
        lock.unlock()
        // Counts, never content: the words themselves stay out of the log.
        HelmLog.shared.info("layout", "converted a word in \(Redact.app(bundleID))")
        emitState()
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
        lock.lock(); let word = buffer.word; lock.unlock()
        guard !word.isEmpty else { return }
        convert(word, force: true)
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
        triggers = ConversionTriggers(onSpace: settings.bool("onSpace", default: true),
                                      onReturn: settings.bool("onReturn", default: true),
                                      onPunctuation: settings.bool("onPunctuation", default: true))
        lock.unlock()
        emitState()
    }

    private func perform(_ plan: SwitchPlan) {
        lock.lock(); performing = true; lock.unlock()
        _ = typing.perform(plan)
        lock.lock(); performing = false; buffer.clear(); lock.unlock()
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
        lock.lock()
        let state = LayoutState(enabled: tapped, automatic: automatic,
                                suspended: secure.isSecure(),
                                lastConversion: undo?.event,
                                conversionsToday: conversions)
        lock.unlock()
        if let data = try? JSONEncoder().encode(state) {
            localTransport.emit(EngineEvent(name: "layoutState", payload: data))
        }
    }
}

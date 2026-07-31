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
    private var lastCompleted: RememberedWord?
    private var activeObserver: NSObjectProtocol?
    private var undo: UndoRecord?
    private var scope: AppScope
    private var exceptions: Exceptions
    private let selection: SelectionPort?
    private var autoReplace: AutoReplace
    private var fixCapitals: Bool
    private var automatic: Bool
    private var triggers: ConversionTriggers
    private var audible: Bool
    /// The single key bound to "fix / put it back", if any.
    private var tapKey = ModifierTap(key: .off)
    private var conversions = DailyCount()
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
                selection: SelectionPort? = nil,
                autoReplace: [AutoReplace.Entry] = [],
                fixCapitals: Bool = false,
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
        self.selection = selection
        self.autoReplace = AutoReplace(entries: autoReplace)
        self.fixCapitals = fixCapitals
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
        // Read the stored settings before the first key arrives. This used to
        // happen only when the transport announced a change, so a launch kept
        // whatever the initialiser held — and the tap key, which has no
        // initialiser parameter, stayed `.off`. The gesture worked only in a
        // session where the page had been opened, and silently, because `.off`
        // refuses before there is anything to refuse.
        reloadSettings()
        startTap()
        // Permission is usually granted while Helm is already running — the
        // note in settings sends people to System Settings and they come back.
        // Without this the tap stayed dead until the next launch, which is the
        // same "switch that looks like it works" defect the note exists to
        // prevent.
        // Dropped rather than overwritten: `deactivate` removes one observer,
        // so two activates in a row left the first registered for good.
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
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
        forgetTheWord()
        lock.unlock()
        emitState()
    }

    // MARK: - The pipeline

    /// Everything a later gesture could use to edit text that is no longer in
    /// front of the caret. A blind edit measured against a word must not
    /// outlive the word — four paths used to clear two of these three and leave
    /// the third standing, so a refused conversion, an expanded abbreviation or
    /// a corrected capital left a word the gesture would then delete out of the
    /// middle of the sentence that had replaced it.
    ///
    /// Call with the lock held.
    /// The layout to convert *into*.
    ///
    /// Not "the first other source": on a Mac with three layouts that is
    /// whichever the system lists first, so the module converted into a language
    /// the word has nothing to do with — and then switched the keyboard to it.
    /// Each candidate is asked whether the result is a real word; `Fix` still
    /// forces a conversion when none is (`OtherSource`).
    private func target(for word: String, from: String) -> String? {
        OtherSource.pick(current: from, installed: sources.installed()) { candidate in
            guard let attempt = translation.translate(word, from: from, to: candidate)
            else { return false }
            return spell.isWord(attempt, sourceID: candidate) == true
        }
    }

    private func forgetTheWord() {
        buffer.clear()
        undo = nil
        lastCompleted = nil
    }

    private func handle(_ event: TypingBuffer.Event) {
        // The cheap half of the secure check, on every key rather than at the
        // word boundary: a password typed without spaces would otherwise sit in
        // the buffer until the next one. No AX call here — this is one syscall.
        if secure.isSecureInput() {
            // All three places a word lives, as in deactivate: a retained
            // lastCompleted could later be typed back by the hotkey into
            // whatever field happens to be focused.
            lock.lock(); forgetTheWord(); lock.unlock()
            return
        }
        lock.lock()
        guard !performing else { lock.unlock(); return }
        // Typing, clicking, navigating and leaving end the chance to undo: an
        // undo is a blind edit of a fixed length, and "привет abc" undone
        // becomes "приghbdtn ". A chord is the exception, and not a convenient
        // one — the undo shortcut *is* a chord, it reaches the tap before
        // Carbon delivers it, and treating it like the rest meant the shortcut
        // destroyed its own precondition and could never fire once.
        //
        // Only a chord. This forgave every `.navigation`, which the tap emitted
        // for the shortcut's own keys *and* for a bare arrow, Home, End, Tab or
        // Escape — so one ordinary caret move spent the budget, and with the
        // default gesture nothing spends the rest of it afterwards, because a
        // solo-modifier tap goes through `deliverModifier` and never arrives
        // here. One Left Arrow after a conversion and the gesture typed
        // backspaces into the middle of the sentence.
        switch event {
        case .chord: undo?.soften()
        default: undo?.invalidate()
        }
        let finished = buffer.accept(event)
        let auto = automatic
        let confirms = triggers.converts(event)
        lock.unlock()
        // Ended and meant are different things: leaving the word by clicking or
        // moving the caret ends it without asking for a conversion.
        // Converting a word the caret has left types six backspaces into
        // whatever is in front of it now — possibly an hour later. Through
        // `movedTheCaret`, which is the same fact the undo above spends, because
        // this used to carry its own shorter list: a click and a focus change
        // dropped the word and a bare arrow, Home, End, Tab or Escape *stored*
        // the one it had just ended. Press ←, tap the key, and the conversion
        // landed wherever the arrow had gone.
        if event.movedTheCaret {
            lock.lock(); lastCompleted = nil; lock.unlock()
        } else {
            // An event that ends no word still ends the last one's usefulness:
            // a token too long for the buffer to hold refuses, and the word
            // from before it used to stay remembered — by then it is as many
            // characters upstream of the caret as the token is long.
            let here = secure.frontmostBundleID()
            lock.lock()
            lastCompleted = finished.map { RememberedWord($0, in: here) }
            lock.unlock()
        }
        guard let completed = finished else { return }
        // Three things can happen to a finished word, and exactly one does.
        // The order is fixed and is not a preference: an abbreviation is an
        // instruction somebody wrote down, a habit correction is about how the
        // keyboard was held, and a layout conversion is a guess — most explicit
        // first. Two edits to one word would be one edit the undo shortcut
        // cannot take back in a single press.
        guard confirms else { return }
        if replaceWord(completed) { return }
        guard auto else { return }
        convert(completed.word, trailing: completed.ending, force: false)
    }

    /// An abbreviation or a held capital. True when the word was dealt with and
    /// the layout conversion must not also look at it.
    private func replaceWord(_ completed: TypingBuffer.Completion) -> Bool {
        lock.lock()
        let expansion = autoReplace.expansion(for: completed.word)
        let habit = fixCapitals ? TypingHabits.corrected(completed.word) : nil
        lock.unlock()
        guard let replacement = expansion ?? habit else { return false }

        let bundleID = secure.frontmostBundleID()
        lock.lock(); let allowed = scope.allows(bundleID); lock.unlock()
        guard allowed, !secure.isSecure() else { return false }

        // The trailing character was typed and stays typed, so the plan puts it
        // back after the replacement — otherwise the space that confirmed the
        // word is eaten by the backspaces that follow it.
        // Through `make`, so the grapheme counting lives in one place: the
        // arithmetic duplicated here counted a combining ending twice.
        guard let plan = SwitchPlan.make(replacing: completed.word,
                                         with: replacement,
                                         trailing: completed.ending) else { return false }
        // `perform` forgets the word, which is what this path needs and used to
        // spell out for itself: an expansion leaves no undo record — the app's
        // own undo covers it, and one here would let the shortcut retype an
        // abbreviation nobody asked to see again — and leaves no remembered
        // word, because `brb` is not in the field any more and a gesture
        // converting it would cut four characters out of the middle of the
        // sentence that replaced it.
        let done = perform(plan)
        if done, audible { sound?.playSwitch() }
        return done
    }

    // MARK: - The selection

    /// The one action that acts on whatever is selected rather than on what was
    /// typed.
    ///
    /// It had three — transliteration and case-walking went with them, and
    /// `SelectionAction` records why. This comment said three long after they
    /// were gone, which reads as two missing cases to find.
    ///
    /// A different mechanism from the word conversion and a stricter one. The
    /// word one only ever edits text it watched being typed, a keystroke ago;
    /// this edits text Helm has never seen, in an app it did not choose. So the
    /// same two refusals apply — a blocked app, a secure field — and one more:
    /// nothing happens unless the result actually differs, because replacing a
    /// selection with itself still clears that app's undo stack.
    /// `selected` is the text the caller has already read, when it has.
    ///
    /// `fix()` reads the selection off the main thread precisely because that
    /// read can block, then hopped back and let this read it again — on the
    /// tap's own callback thread, where `selectedText()` can fall through to
    /// the ⌘C route and poll the pasteboard for up to 200 ms. The expensive
    /// probe was paid twice and the second time on the one thread the comment
    /// above `fix()` says it must never be on. The transport's
    /// `convertSelection` has nothing read yet and still asks here.
    private func transform(_ action: SelectionAction, selected: String? = nil) {
        guard let selection else { return }
        let bundleID = secure.frontmostBundleID()
        lock.lock()
        // A module that was turned off types nothing. The word path has always
        // asked and this one did not, which showed up as nothing only because
        // the gesture reaches it through `fix()` and the transport's
        // `convertSelection` is the second door — both live, both here.
        let live = running
        let allowed = scope.allows(bundleID)
        lock.unlock()
        guard live, allowed, !secure.isSecure() else { return }
        guard let text = selected ?? selection.selectedText(), !text.isEmpty else { return }

        let transform = SelectionTransform(convert: { [weak self] source in
            guard let self,
                  let current = self.sources.current(),
                  // The same choice as a single word makes, judged on the first
                  // word of the selection — a selection carries no record of the
                  // layout it was typed with, so this is the only evidence there
                  // is. `Fix` still forces a conversion when nothing fits.
                  let firstWord = source.split(separator: " ").first.map(String.init),
                  let other = self.target(for: firstWord, from: current)
            else { return nil }
            // Both ways round. A selection carries no record of the layout it
            // was typed with, so the active one is not evidence — see
            // `TwoWayConversion`.
            return TwoWayConversion.result(
                for: source,
                forward: { self.translation.translate($0, from: current, to: other) },
                backward: { self.translation.translate($0, from: other, to: current) })
        })
        guard let replacement = transform.apply(action, to: text) else {
            // Silence was the whole problem with this path: the gesture fired,
            // the translation declined, and nothing on screen or in the log
            // said so. A count, not the text — the log carries no content.
            HelmLog.shared.info("layout",
                                "selection left alone: no conversion for \(text.count) characters")
            return
        }

        // `performing` for the same reason the word path sets it: the
        // replacement is typed, the tap sees it, and without this it is read
        // back as somebody typing a paragraph.
        lock.lock(); performing = true; lock.unlock()
        let done = selection.replaceSelection(with: replacement)
        lock.lock(); performing = false; forgetTheWord(); lock.unlock()

        guard done else {
            HelmLog.shared.warn("layout", "selection \(action.rawValue) refused by \(Redact.app(bundleID))")
            return
        }
        if audible { sound?.playSwitch() }
    }

    /// `force` is the hotkey: the user asked for this word by name, so the
    /// dictionary's opinion is not consulted. The secure checks still are.
    private func convert(_ word: String, trailing: Character?, force: Bool) {
        let bundleID = secure.frontmostBundleID()
        lock.lock(); let allowed = scope.allows(bundleID); lock.unlock()
        guard allowed else { return }
        guard !secure.isSecure() else {
            // Not just the buffer. `isSecureInput()` is the cheap check and it
            // is false for an app's own password field, which is why this
            // expensive one exists — but by the time it refuses, the password
            // is already the remembered word, and a refusal that leaves it
            // there hands the gesture a password to type into the next field.
            lock.lock(); forgetTheWord(); lock.unlock()
            emitState()
            return
        }
        // Not "the first other source": on a Mac with three layouts that is
        // whichever the system lists first, and the module converted into a
        // language the word has nothing to do with — then switched the keyboard
        // to it. Ask each candidate whether the result is a word (`OtherSource`).
        guard let from = sources.current(),
              let to = target(for: word, from: from),
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
            // Counts and shapes, never the word itself.
            HelmLog.shared.warn("layout", "\(Redact.app(bundleID)) refused a replacement of "
                                + "\(plan.backspaces) characters (\(from) → \(to))")
            return
        }
        sources.select(to)
        lock.lock(); let announce = audible; lock.unlock()
        if announce { sound?.playSwitch() }
        lock.lock()
        undo = UndoRecord(event: ConversionEvent(before: word, after: replacement,
                                                 app: bundleID,
                                                 trailing: trailing.map(String.init) ?? ""))
        _ = conversions.add(on: Date())
        lock.unlock()
        // Counts, never content: the words themselves stay out of the log.
        HelmLog.shared.info("layout", "converted a word in \(Redact.app(bundleID))")
        emitState()
    }

    /// The key the gesture is bound to. Read at start and on every change.
    public var boundTapKey: TapKey {
        lock.lock(); defer { lock.unlock() }
        return tapKey.key
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
        let refusal = tapKey.lastRefusal
        // Taken here rather than read again below: `reloadSettings` assigns the
        // whole struct under this lock, and a struct several words wide read
        // outside it can be torn.
        let bound = tapKey.key.keyCode
        lock.unlock()
        guard fired else {
            // A gesture that never fires looks exactly like a gesture that was
            // never made: the key still does its own job and nothing is said.
            // Only the bound key's own release is reported, so an ordinary
            // day's typing adds nothing to the log.
            if case let .up(code, _) = input, code == bound, let refusal {
                HelmLog.shared.info("layout", "tap refused: \(refusal.rawValue)")
            }
            return
        }
        fix()
    }

    /// The whole module in one gesture: fix whatever is in front of you.
    ///
    /// Selected text is an explicit act — somebody chose those characters — so
    /// it wins. With nothing selected this is what it always was: put the last
    /// conversion back if it is still undoable here, otherwise convert the last
    /// word. There used to be five bindings for these three outcomes, and the
    /// user was asked to assemble the gesture the app can assemble itself.
    ///
    /// Off the main thread first. This runs from the event tap's callback,
    /// which is on the main run loop, and the accessibility tree can take a
    /// noticeable moment to answer in an app that is busy — long enough to
    /// stall the very key that is being tapped.
    public func fix() {
        // Only the accessibility probe goes off the main thread, and only
        // because it can block for as long as the app in front takes to answer
        // — on the tap's own callback that would stall the very key being
        // tapped. What comes back to main is the acting: the frontmost app, the
        // pasteboard, the sound.
        //
        // The text read here is carried into `transform` rather than read
        // again. It used to be discarded, and the second read landed on main,
        // which is exactly the thread this hop exists to keep clear.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let selected = selection?.selectedTextWithoutClipboard()
            let hasSelection = !(selected ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            DispatchQueue.main.async { [self] in
                HelmLog.shared.info("layout",
                                    "gesture: \(hasSelection ? "selection" : "last word")")
                if hasSelection { transform(.convert, selected: selected); return }
                let bundleID = secure.frontmostBundleID()
                lock.lock()
                let undoable = undo?.canUndo(in: bundleID) ?? false
                lock.unlock()
                if undoable { undoLast() } else { convertLastWord() }
            }
        }
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
        let bundleID = secure.frontmostBundleID()
        lock.lock()
        // `wholeWord`, not `word`: the buffer refuses a word it could not hold
        // in full, and this is the second door into the same blind edit.
        let live = buffer.wholeWord
        let previous = lastCompleted
        lock.unlock()
        if let live {
            // Mid-word: nothing ended it, so there is nothing extra to delete.
            convert(live, trailing: nil, force: true)
        } else if let previous, previous.belongs(to: bundleID) {
            // Only where it was typed. The backspaces are counted against text
            // this app is holding; anywhere else they eat somebody else's.
            convert(previous.word, trailing: previous.ending, force: true)
        }
    }

    /// Re-reads what the settings page wrote. The page owns the store; the
    /// engine owns the behaviour, and this is the one line between them.
    private func reloadSettings() {
        guard let settings else { return }
        let rules = settings.boolTable(LayoutKey.appRules)
        lock.lock()
        automatic = settings.bool(LayoutKey.automatic, default: true)
        exceptions = Exceptions(words: settings.stringArray(LayoutKey.exceptions))
        scope = AppScope(rules: rules)
        audible = settings.bool(LayoutKey.audible, default: false)
        fixCapitals = settings.bool(LayoutKey.fixCapitals, default: false)
        // Decoded here rather than in the page: the engine is the only thing
        // that acts on the table, so it is the thing that has to have the
        // current one — a page that pushed entries would leave the engine
        // holding yesterday's list whenever the window had never been opened.
        if let data = settings.data(LayoutKey.autoReplace),
           let entries = try? JSONDecoder().decode([AutoReplace.Entry].self, from: data) {
            autoReplace = AutoReplace(entries: entries)
        } else {
            autoReplace = AutoReplace(entries: [])
        }
        tapKey = ModifierTap(key: TapKey.from(settings.string(LayoutKey.tapKey, default: TapKey.rightCommand.rawValue)))
        triggers = ConversionTriggers(onSpace: settings.bool(LayoutKey.onSpace, default: ConversionTriggers.default.onSpace),
                                      onReturn: settings.bool(LayoutKey.onReturn, default: ConversionTriggers.default.onReturn),
                                      onPunctuation: settings.bool(LayoutKey.onPunctuation, default: ConversionTriggers.default.onPunctuation))
        lock.unlock()
        emitState()
    }

    @discardableResult
    private func perform(_ plan: SwitchPlan) -> Bool {
        lock.lock(); performing = true; lock.unlock()
        let done = typing.perform(plan)
        lock.lock(); performing = false; forgetTheWord(); lock.unlock()
        return done
    }

    // MARK: - Transport

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "fix": self.fix()
            case "convertSelection": self.transform(.convert)
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
                                conversionsToday: conversions.value(on: Date()))
        lock.unlock()
        if let data = try? JSONEncoder().encode(state) {
            localTransport.emit(EngineEvent(name: "layoutState", payload: data))
        }
    }
}

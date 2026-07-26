# Layout Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Helm module that notices a word typed in the wrong keyboard layout, rewrites it, switches the input source, and can undo what it did.

**Architecture:** The house pattern — a headless engine plus a UI descriptor, talking over `LocalTransport`. Every decision lives in pure logic under `Engine/Logic/` and is tested without a keyboard; the syscall surface is six thin ports. Spec: [2026-07-26-layout-switcher-design.md](../specs/2026-07-26-layout-switcher-design.md).

**Tech Stack:** Swift 6, SwiftPM, `CGEventTap`, `UCKeyTranslate` (Carbon), Text Input Sources, `NSSpellChecker`, `AXUIElement`.

---

## File structure

Two new targets, mirroring `Module_Disk_*`.

**`Sources/Modules/Layout/Engine/`**

| File | Responsibility |
|---|---|
| `Model.swift` | Wire types: `LayoutState`, `ConversionEvent`, `LayoutRule`. |
| `Ports.swift` | The six protocols the engine is written against. |
| `Logic/TypingBuffer.swift` | Current word as a state machine over key events. |
| `Logic/LayoutVerdict.swift` | Convert or leave, given both spell verdicts and the guards. |
| `Logic/SwitchPlan.swift` | Backspace count and replacement string. |
| `Logic/Exceptions.swift` | Words the user marked "never touch". |
| `Logic/AppScope.swift` | Which apps take conversions. |
| `Logic/UndoRecord.swift` | What the last conversion changed, and whether it is still safe to undo. |
| `LayoutEngine.swift` | Wires ports to logic; owns the transport. |
| `SystemPorts.swift` | Production ports. |

**`Sources/Modules/Layout/UI/`**

| File | Responsibility |
|---|---|
| `LayoutDescriptor.swift` | Module metadata, engine construction, settings page. |
| `LayoutSettingsPage.swift` | The settings screen. |
| `LayoutViewModel.swift` | Observable state for the page and the tile. |
| `LayoutStrings.swift` | `L()` strings, eight languages. |

**Tests:** `Tests/Modules/Layout/EngineTests/` — one file per logic unit.

Tasks 1–7 are pure logic and land with no system access at all. Task 8 wires the engine, 9 the production ports, 10 the UI, 11 the registration and release.

---

### Task 1: Targets and a wire model

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Modules/Layout/Engine/Model.swift`
- Test: `Tests/Modules/Layout/EngineTests/ModelTests.swift`

- [ ] **Step 1: Add the targets**

In `Package.swift`, after the `Module_Disk_UI` target, add:

```swift
        .target(
            name: "Module_Layout_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/Layout/Engine"
        ),
        .target(
            name: "Module_Layout_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_Layout_Engine"],
            path: "Sources/Modules/Layout/UI"
        ),
```

and in the `HelmApp` target's dependency list add `"Module_Layout_UI"`. Then, with the other test targets:

```swift
        .testTarget(
            name: "Module_Layout_EngineTests",
            dependencies: ["Module_Layout_Engine"],
            path: "Tests/Modules/Layout/EngineTests"
        ),
```

- [ ] **Step 2: Write the failing test**

`Tests/Modules/Layout/EngineTests/ModelTests.swift`:

```swift
import XCTest
@testable import Module_Layout_Engine

final class ModelTests: XCTestCase {
    /// The wire types cross a JSON boundary; a field that does not survive the
    /// round trip is a command the UI sends and the engine never sees.
    func testConversionEventRoundTrips() throws {
        let event = ConversionEvent(before: "ghbdtn", after: "привет", app: "com.apple.Notes")
        let data = try JSONEncoder().encode(event)
        let back = try JSONDecoder().decode(ConversionEvent.self, from: data)
        XCTAssertEqual(back, event)
    }

    func testStateRoundTrips() throws {
        let state = LayoutState(enabled: true, automatic: true, suspended: false,
                                lastConversion: nil, conversionsToday: 3)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LayoutState.self, from: data), state)
    }
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `swift test --filter Module_Layout_EngineTests`
Expected: FAIL — `cannot find 'ConversionEvent' in scope`.

- [ ] **Step 4: Write the model**

`Sources/Modules/Layout/Engine/Model.swift`:

```swift
import Foundation

/// One conversion, as it happened. The words themselves stay in memory and in
/// this struct; they are never logged and never written to disk (spec §
/// Decisions 5).
public struct ConversionEvent: Codable, Equatable, Sendable {
    public let before: String
    public let after: String
    /// Bundle id of the app it happened in, so an undo cannot land elsewhere.
    public let app: String

    public init(before: String, after: String, app: String) {
        self.before = before
        self.after = after
        self.app = app
    }
}

/// What the panel and the settings page show.
public struct LayoutState: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let automatic: Bool
    /// True while secure input is on: the module is deliberately silent, and
    /// silence needs a visible reason.
    public let suspended: Bool
    public let lastConversion: ConversionEvent?
    public let conversionsToday: Int

    public init(enabled: Bool, automatic: Bool, suspended: Bool,
                lastConversion: ConversionEvent?, conversionsToday: Int) {
        self.enabled = enabled
        self.automatic = automatic
        self.suspended = suspended
        self.lastConversion = lastConversion
        self.conversionsToday = conversionsToday
    }
}

/// A per-app rule, the same shape Keep Awake and VPN already use.
public struct LayoutRule: Codable, Equatable, Sendable {
    public let bundleID: String
    public let allowed: Bool

    public init(bundleID: String, allowed: Bool) {
        self.bundleID = bundleID
        self.allowed = allowed
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter Module_Layout_EngineTests`
Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/Modules/Layout Tests/Modules/Layout
git commit -m "feat(layout): module targets and wire model"
```

---

### Task 2: TypingBuffer

**Files:**
- Create: `Sources/Modules/Layout/Engine/Logic/TypingBuffer.swift`
- Test: `Tests/Modules/Layout/EngineTests/TypingBufferTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_Layout_Engine

/// The buffer decides what a "word" is, and everything downstream trusts it.
/// A boundary it misses is a conversion applied to half of something.
final class TypingBufferTests: XCTestCase {
    private func feed(_ events: [TypingBuffer.Event]) -> TypingBuffer {
        var buffer = TypingBuffer()
        for event in events { _ = buffer.accept(event) }
        return buffer
    }

    func testCharactersAccumulate() {
        let buffer = feed([.character("g"), .character("h"), .character("b")])
        XCTAssertEqual(buffer.word, "ghb")
    }

    /// Every boundary returns the finished word exactly once, and clears.
    func testEachBoundaryCompletesTheWord() {
        for boundary in [TypingBuffer.Event.space, .newline, .punctuation("."),
                         .navigation, .click, .focusChange] {
            var buffer = TypingBuffer()
            for character in "ghbdtn" { _ = buffer.accept(.character(character)) }
            XCTAssertEqual(buffer.accept(boundary), "ghbdtn", "\(boundary)")
            XCTAssertEqual(buffer.word, "")
        }
    }

    /// A boundary with nothing before it must not report an empty word as a
    /// candidate — downstream would spell-check "".
    func testABoundaryOnAnEmptyBufferCompletesNothing() {
        var buffer = TypingBuffer()
        XCTAssertNil(buffer.accept(.space))
    }

    /// Backspace walks back through what was typed, and past the start it stops
    /// rather than going negative.
    func testBackspaceRemovesTheLastCharacter() {
        var buffer = feed([.character("a"), .character("b")])
        _ = buffer.accept(.backspace)
        XCTAssertEqual(buffer.word, "a")
        _ = buffer.accept(.backspace)
        _ = buffer.accept(.backspace)
        XCTAssertEqual(buffer.word, "")
    }

    /// Losing focus mid-word abandons it: by the time focus returns the text
    /// underneath may be anywhere.
    func testFocusChangeAbandonsRatherThanCompletesWhenAsked() {
        var buffer = feed([.character("x")])
        _ = buffer.accept(.focusChange)
        XCTAssertEqual(buffer.word, "")
    }

    /// A word longer than any real one is dropped rather than grown without
    /// bound — a key tap that never sees a boundary must not become a leak.
    func testTheBufferIsBounded() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength + 50) { _ = buffer.accept(.character("a")) }
        XCTAssertLessThanOrEqual(buffer.word.count, TypingBuffer.maxLength)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter TypingBufferTests`
Expected: FAIL — `cannot find 'TypingBuffer' in scope`.

- [ ] **Step 3: Write the buffer**

```swift
import Foundation

/// The current word, as a state machine over key events.
///
/// It holds what has been typed since the last boundary and nothing else: no
/// history, no file, nothing that outlives the word. That is not tidiness — a
/// tap sees passwords typed into fields an app forgot to mark secure, and the
/// only safe place for them is a buffer that is already gone.
public struct TypingBuffer {
    public enum Event: Equatable {
        case character(Character)
        case backspace
        case space
        case newline
        case punctuation(Character)
        /// Arrow keys, home, end — the caret moved, so what came before is no
        /// longer adjacent to what comes next.
        case navigation
        case click
        case focusChange
    }

    /// Longer than any word in any language Helm can judge. Past it the tap is
    /// seeing something that is not prose, and holding on to it is a leak.
    public static let maxLength = 64

    private var characters: [Character] = []

    public init() {}

    public var word: String { String(characters) }

    /// Feeds one event. Returns the completed word when this event ended one,
    /// and nil otherwise.
    @discardableResult
    public mutating func accept(_ event: Event) -> String? {
        switch event {
        case .character(let character):
            guard characters.count < Self.maxLength else { return nil }
            characters.append(character)
            return nil
        case .backspace:
            if !characters.isEmpty { characters.removeLast() }
            return nil
        case .space, .newline, .punctuation, .navigation, .click, .focusChange:
            guard !characters.isEmpty else { return nil }
            let finished = String(characters)
            characters.removeAll()
            return finished
        }
    }

    public mutating func clear() { characters.removeAll() }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter TypingBufferTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Layout/Engine/Logic/TypingBuffer.swift Tests/Modules/Layout/EngineTests/TypingBufferTests.swift
git commit -m "feat(layout): typing buffer"
```

---

### Task 3: LayoutVerdict

**Files:**
- Create: `Sources/Modules/Layout/Engine/Logic/LayoutVerdict.swift`
- Test: `Tests/Modules/Layout/EngineTests/LayoutVerdictTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_Layout_Engine

/// The one unit that can ruin somebody's sentence. Every case here is a reason
/// to decline; the single reason to act is that the word is wrong as typed and
/// right when translated.
final class LayoutVerdictTests: XCTestCase {
    private func decide(_ word: String, translated: String,
                        validAsTyped: Bool, validTranslated: Bool,
                        exceptions: Set<String> = []) -> LayoutVerdict.Decision {
        LayoutVerdict.decide(word: word, translated: translated,
                             validAsTyped: validAsTyped,
                             validTranslated: validTranslated,
                             exceptions: exceptions)
    }

    func testWrongAsTypedAndRightTranslatedConverts() {
        XCTAssertEqual(decide("ghbdtn", translated: "привет",
                              validAsTyped: false, validTranslated: true),
                       .convert("привет"))
    }

    /// The rule that outranks every other: a real word is never touched, even
    /// when its translation is also a real word.
    func testAValidWordIsNeverConverted() {
        XCTAssertEqual(decide("ras", translated: "кфы",
                              validAsTyped: true, validTranslated: true),
                       .leave)
        XCTAssertEqual(decide("ras", translated: "кфы",
                              validAsTyped: true, validTranslated: false),
                       .leave)
    }

    func testNonsenseInBothLayoutsIsLeftAlone() {
        XCTAssertEqual(decide("qqqq", translated: "ййыы",
                              validAsTyped: false, validTranslated: false),
                       .leave)
    }

    func testShortWordsAreLeftAlone() {
        for word in ["a", "ab", "gh"] {
            XCTAssertEqual(decide(word, translated: "хх",
                                  validAsTyped: false, validTranslated: true),
                           .leave, word)
        }
    }

    func testWordsWithDigitsAreLeftAlone() {
        XCTAssertEqual(decide("ghb1", translated: "прив1",
                              validAsTyped: false, validTranslated: true),
                       .leave)
    }

    /// A path, a URL or an address is not prose, and converting one breaks
    /// something that was correct.
    func testAddressesAndPathsAreLeftAlone() {
        for word in ["/usr/local", "http://x.dev", "me@example.com", "~/Documents"] {
            XCTAssertEqual(decide(word, translated: "ннн",
                                  validAsTyped: false, validTranslated: true),
                           .leave, word)
        }
    }

    func testAcronymsAreLeftAlone() {
        XCTAssertEqual(decide("HTTP", translated: "РТТР",
                              validAsTyped: false, validTranslated: true),
                       .leave)
    }

    func testTheUsersExceptionsWin() {
        XCTAssertEqual(decide("ghbdtn", translated: "привет",
                              validAsTyped: false, validTranslated: true,
                              exceptions: ["ghbdtn"]),
                       .leave)
    }

    /// Case is the user's business, not the dictionary's.
    func testExceptionsIgnoreCase() {
        XCTAssertEqual(decide("Ghbdtn", translated: "Привет",
                              validAsTyped: false, validTranslated: true,
                              exceptions: ["ghbdtn"]),
                       .leave)
    }

    /// If translation produced nothing, or produced the same string, there is
    /// no conversion to make.
    func testAnEmptyOrIdenticalTranslationIsLeftAlone() {
        XCTAssertEqual(decide("ghbdtn", translated: "",
                              validAsTyped: false, validTranslated: true), .leave)
        XCTAssertEqual(decide("ghbdtn", translated: "ghbdtn",
                              validAsTyped: false, validTranslated: true), .leave)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter LayoutVerdictTests`
Expected: FAIL — `cannot find 'LayoutVerdict' in scope`.

- [ ] **Step 3: Write the verdict**

```swift
import Foundation

/// Convert, or leave alone.
///
/// Written as a list of reasons to decline, with exactly one way through. A
/// false positive here does not show a wrong number — it rewrites a sentence
/// somebody was in the middle of, in an app Helm does not own.
public enum LayoutVerdict {
    public enum Decision: Equatable {
        case leave
        case convert(String)
    }

    /// Shorter than this and there is not enough evidence for a dictionary to
    /// mean anything: "gj" is as much a typo as a mislayout.
    public static let minimumLength = 3

    public static func decide(word: String,
                              translated: String,
                              validAsTyped: Bool,
                              validTranslated: Bool,
                              exceptions: Set<String>) -> Decision {
        // The rule that outranks the rest: what the user typed is already a
        // word, so it is what they meant.
        guard !validAsTyped else { return .leave }
        guard validTranslated else { return .leave }
        guard !translated.isEmpty, translated != word else { return .leave }
        guard word.count >= minimumLength else { return .leave }
        guard !word.contains(where: \.isNumber) else { return .leave }
        guard !looksLikeAddress(word) else { return .leave }
        guard !isAcronym(word) else { return .leave }
        guard !exceptions.contains(word.lowercased()) else { return .leave }
        return .convert(translated)
    }

    /// Paths, URLs and email addresses are not prose, and each is correct as
    /// typed even when no dictionary agrees.
    private static func looksLikeAddress(_ word: String) -> Bool {
        word.contains("/") || word.contains("@") || word.contains("\\")
            || word.contains("~") || word.contains(":")
    }

    /// All caps is an acronym often enough that the dictionary's opinion of it
    /// is worth less than the risk.
    private static func isAcronym(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter LayoutVerdictTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Layout/Engine/Logic/LayoutVerdict.swift Tests/Modules/Layout/EngineTests/LayoutVerdictTests.swift
git commit -m "feat(layout): conversion verdict"
```

---

### Task 4: SwitchPlan

**Files:**
- Create: `Sources/Modules/Layout/Engine/Logic/SwitchPlan.swift`
- Test: `Tests/Modules/Layout/EngineTests/SwitchPlanTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_Layout_Engine

/// The plan is counted in keystrokes an app will receive. One backspace too
/// few leaves debris; one too many eats the word before it.
final class SwitchPlanTests: XCTestCase {
    func testOneBackspacePerTypedCharacter() {
        let plan = SwitchPlan.make(replacing: "ghbdtn", with: "привет")
        XCTAssertEqual(plan.backspaces, 6)
        XCTAssertEqual(plan.insert, "привет")
    }

    /// Backspaces are counted in characters as the app sees them, not in bytes
    /// or scalars: "ё" is one key press to delete, whatever it is encoded as.
    func testMultiByteCharactersCountAsOne() {
        let plan = SwitchPlan.make(replacing: "£€ё", with: "abc")
        XCTAssertEqual(plan.backspaces, 3)
    }

    /// A composed character is one grapheme, and one backspace removes it.
    func testComposedCharactersCountAsOne() {
        let plan = SwitchPlan.make(replacing: "e\u{0301}", with: "x")
        XCTAssertEqual(plan.backspaces, 1)
    }

    /// Nothing to replace is not a plan to send zero keystrokes; it is no plan.
    func testAnEmptyWordHasNoPlan() {
        XCTAssertNil(SwitchPlan.make(replacing: "", with: "x"))
        XCTAssertNil(SwitchPlan.make(replacing: "x", with: ""))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter SwitchPlanTests`
Expected: FAIL — `cannot find 'SwitchPlan' in scope`.

- [ ] **Step 3: Write the plan**

```swift
import Foundation

/// How a conversion is performed, counted in keystrokes the target app will
/// receive: delete what is there, then type the replacement.
public struct SwitchPlan: Equatable {
    public let backspaces: Int
    public let insert: String

    /// Counted in graphemes, which is what one press of delete removes — not
    /// scalars, and certainly not bytes.
    public static func make(replacing word: String, with replacement: String) -> SwitchPlan? {
        guard !word.isEmpty, !replacement.isEmpty else { return nil }
        return SwitchPlan(backspaces: word.count, insert: replacement)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SwitchPlanTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Layout/Engine/Logic/SwitchPlan.swift Tests/Modules/Layout/EngineTests/SwitchPlanTests.swift
git commit -m "feat(layout): switch plan"
```

---

### Task 5: Exceptions and AppScope

**Files:**
- Create: `Sources/Modules/Layout/Engine/Logic/Exceptions.swift`
- Create: `Sources/Modules/Layout/Engine/Logic/AppScope.swift`
- Test: `Tests/Modules/Layout/EngineTests/ScopeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_Layout_Engine

final class ScopeTests: XCTestCase {
    // MARK: - Exceptions

    func testExceptionsAreCaseInsensitiveAndTrimmed() {
        let list = Exceptions(words: ["  Ghbdtn ", "тест"])
        XCTAssertTrue(list.contains("ghbdtn"))
        XCTAssertTrue(list.contains("GHBDTN"))
        XCTAssertTrue(list.contains("Тест"))
        XCTAssertFalse(list.contains("other"))
    }

    func testBlankEntriesAreDropped() {
        let list = Exceptions(words: ["", "   ", "word"])
        XCTAssertEqual(list.words.count, 1)
        // An empty entry would otherwise match the empty word and disable
        // everything quietly.
        XCTAssertFalse(list.contains(""))
    }

    // MARK: - AppScope

    /// Terminals and password managers are refused before any rule is read: in
    /// a terminal "ghbdtn" may be a filename, and in a password manager the
    /// text is not prose at all.
    func testTheDefaultBlocklistIsRefusedOutright() {
        let scope = AppScope(rules: [:])
        for bundle in ["com.apple.Terminal", "com.googlecode.iterm2",
                       "com.agilebits.onepassword7", "com.1password.1password"] {
            XCTAssertFalse(scope.allows(bundle), bundle)
        }
    }

    func testAnythingElseIsAllowedByDefault() {
        let scope = AppScope(rules: [:])
        XCTAssertTrue(scope.allows("com.apple.Notes"))
    }

    func testAnExplicitRuleWins() {
        let scope = AppScope(rules: ["com.apple.Notes": false, "com.apple.Terminal": true])
        XCTAssertFalse(scope.allows("com.apple.Notes"))
        // Even against the built-in blocklist: the user said so.
        XCTAssertTrue(scope.allows("com.apple.Terminal"))
    }

    /// No frontmost app means no idea where the text would land.
    func testAnUnknownAppIsRefused() {
        XCTAssertFalse(AppScope(rules: [:]).allows(""))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter ScopeTests`
Expected: FAIL — `cannot find 'Exceptions' in scope`.

- [ ] **Step 3: Write both units**

`Exceptions.swift`:

```swift
import Foundation

/// Words the user has told Helm to leave alone.
///
/// Case-insensitive because case is the user's business, not the dictionary's,
/// and trimmed because a trailing space in a settings field is not a decision.
public struct Exceptions: Equatable {
    public let words: Set<String>

    public init(words: [String]) {
        self.words = Set(words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    public func contains(_ word: String) -> Bool {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        return words.contains(key)
    }
}
```

`AppScope.swift`:

```swift
import Foundation

/// Which apps take conversions.
///
/// Two apps are refused before any rule is consulted: a terminal, where
/// `ghbdtn` is as likely to be a filename as a mistake, and a password manager,
/// where the text is not prose. The user can overrule both — it is their
/// machine — but not by accident.
public struct AppScope: Equatable {
    /// bundle id → allowed. Absent means "no opinion".
    public let rules: [String: Bool]

    public static let blockedByDefault: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
    ]

    public init(rules: [String: Bool]) { self.rules = rules }

    public func allows(_ bundleID: String) -> Bool {
        // Nowhere to type is not somewhere safe to type.
        guard !bundleID.isEmpty else { return false }
        if let explicit = rules[bundleID] { return explicit }
        return !Self.blockedByDefault.contains(bundleID)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter ScopeTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Layout/Engine/Logic Tests/Modules/Layout/EngineTests/ScopeTests.swift
git commit -m "feat(layout): exception list and per-app scope"
```

---

### Task 6: UndoRecord

**Files:**
- Create: `Sources/Modules/Layout/Engine/Logic/UndoRecord.swift`
- Test: `Tests/Modules/Layout/EngineTests/UndoRecordTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_Layout_Engine

/// An undo applied to text that has moved on does not restore anything — it
/// corrupts a second place. Everything here is about knowing when to refuse.
final class UndoRecordTests: XCTestCase {
    private func record() -> UndoRecord {
        UndoRecord(event: ConversionEvent(before: "ghbdtn", after: "привет",
                                          app: "com.apple.Notes"))
    }

    func testAFreshRecordCanBeUndoneInTheSameApp() {
        XCTAssertTrue(record().canUndo(in: "com.apple.Notes"))
    }

    /// The caret is somewhere else entirely now.
    func testAnotherAppCannotBeUndoneInto() {
        XCTAssertFalse(record().canUndo(in: "com.apple.Mail"))
    }

    func testTypingInvalidatesIt() {
        var undo = record()
        undo.invalidate()
        XCTAssertFalse(undo.canUndo(in: "com.apple.Notes"))
    }

    /// The reverse plan puts back exactly what was replaced.
    func testTheReversePlanRestoresTheOriginal() {
        let plan = record().reversePlan()
        XCTAssertEqual(plan?.backspaces, 6)      // "привет"
        XCTAssertEqual(plan?.insert, "ghbdtn")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter UndoRecordTests`
Expected: FAIL — `cannot find 'UndoRecord' in scope`.

- [ ] **Step 3: Write the record**

```swift
import Foundation

/// The last conversion, and whether it is still safe to take back.
///
/// An undo is a blind edit: it deletes a number of characters at the caret and
/// types others. That is only correct while the caret is still where the
/// conversion left it — same app, nothing typed since. Anywhere else it eats
/// somebody's text.
public struct UndoRecord: Equatable {
    public let event: ConversionEvent
    private var valid = true

    public init(event: ConversionEvent) { self.event = event }

    public func canUndo(in bundleID: String) -> Bool {
        valid && bundleID == event.app
    }

    /// Called when anything happens that could have moved the caret.
    public mutating func invalidate() { valid = false }

    public func reversePlan() -> SwitchPlan? {
        SwitchPlan.make(replacing: event.after, with: event.before)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter UndoRecordTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Layout/Engine/Logic/UndoRecord.swift Tests/Modules/Layout/EngineTests/UndoRecordTests.swift
git commit -m "feat(layout): undo record"
```

---

### Task 7: Ports

**Files:**
- Create: `Sources/Modules/Layout/Engine/Ports.swift`

- [ ] **Step 1: Write the protocols**

No test: these are declarations, and the fakes in Task 8 are their first users.

```swift
import Foundation

/// Everything the engine needs from the system, one protocol per syscall
/// family, so the engine itself can be tested without a keyboard.
public protocol KeyTapPort: AnyObject, Sendable {
    /// Starts a listen-only tap. The closure receives one event per key.
    /// Returns false when Accessibility has not been granted — the caller must
    /// say so rather than appear to work.
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void) -> Bool
    func stop()
}

public protocol TypingPort: Sendable {
    /// Sends `plan.backspaces` deletes then types `plan.insert`. Returns false
    /// if the target refused the events; a partial retype is worse than none.
    func perform(_ plan: SwitchPlan) -> Bool
}

public protocol LayoutSourcePort: Sendable {
    /// Input source ids, current first.
    func installed() -> [String]
    func current() -> String?
    func select(_ sourceID: String)
}

public protocol TranslationPort: Sendable {
    /// The same key presses, read through another layout. Returns nil when the
    /// pair cannot be translated rather than approximating it.
    func translate(_ word: String, from: String, to: String) -> String?
}

public protocol SpellPort: Sendable {
    /// Whether the word is a word, for the language of the given input source.
    /// Returns nil when no dictionary is available for that language, which is
    /// different from "not a word".
    func isWord(_ word: String, sourceID: String) -> Bool?
}

public protocol SecureContextPort: Sendable {
    /// True while the system has secure input on, or the focused element is a
    /// password field.
    func isSecure() -> Bool
    /// Bundle id of the frontmost app, empty when there is none.
    func frontmostBundleID() -> String
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Modules/Layout/Engine/Ports.swift
git commit -m "feat(layout): engine ports"
```

---

### Task 8: LayoutEngine

**Files:**
- Create: `Sources/Modules/Layout/Engine/LayoutEngine.swift`
- Test: `Tests/Modules/Layout/EngineTests/LayoutEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import HelmContract
@testable import Module_Layout_Engine

private final class FakeTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    var succeeds = true
    func perform(_ plan: SwitchPlan) -> Bool {
        performed.append(plan)
        return succeeds
    }
}

private final class FakeSecure: SecureContextPort, @unchecked Sendable {
    var secure = false
    var bundle = "com.apple.Notes"
    func isSecure() -> Bool { secure }
    func frontmostBundleID() -> String { bundle }
}

private struct FakeTranslation: TranslationPort {
    let table: [String: String]
    func translate(_ word: String, from: String, to: String) -> String? { table[word] }
}

private struct FakeSpell: SpellPort {
    let valid: Set<String>
    func isWord(_ word: String, sourceID: String) -> Bool? { valid.contains(word) }
}

private final class FakeTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var granted = true
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void) -> Bool {
        handler = onEvent
        return granted
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
}

private struct FakeSources: LayoutSourcePort {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

final class LayoutEngineTests: XCTestCase {
    private func engine(typing: FakeTyping = FakeTyping(),
                        secure: FakeSecure = FakeSecure(),
                        tap: FakeTap = FakeTap()) -> LayoutEngine {
        LayoutEngine(tap: tap, typing: typing, sources: FakeSources(),
                     translation: FakeTranslation(table: ["ghbdtn": "привет", "ras": "кфы"]),
                     spell: FakeSpell(valid: ["привет", "ras"]),
                     secure: secure,
                     rules: [:], exceptions: [])
    }

    func testAMislayoutWordIsConverted() {
        let typing = FakeTyping(), tap = FakeTap()
        let e = engine(typing: typing, tap: tap)
        e.activate()
        tap.type("ghbdtn")
        tap.handler?(.space)
        XCTAssertEqual(typing.performed.first?.insert, "привет")
        XCTAssertEqual(typing.performed.first?.backspaces, 6)
        _ = e
    }

    /// A real word is left alone even though the fake can translate it.
    func testAValidWordIsUntouched() {
        let typing = FakeTyping(), tap = FakeTap()
        let e = engine(typing: typing, tap: tap)
        e.activate()
        tap.type("ras")
        tap.handler?(.space)
        XCTAssertTrue(typing.performed.isEmpty)
        _ = e
    }

    /// Secure input stops conversions and takes the buffer with it.
    func testSecureInputSuspendsAndClears() {
        let typing = FakeTyping(), secure = FakeSecure(), tap = FakeTap()
        secure.secure = true
        let e = engine(typing: typing, secure: secure, tap: tap)
        e.activate()
        tap.type("ghbdtn")
        tap.handler?(.space)
        XCTAssertTrue(typing.performed.isEmpty)
        _ = e
    }

    /// A blocked app never reaches the dictionary, let alone the keyboard.
    func testABlockedAppIsNotTouched() {
        let typing = FakeTyping(), secure = FakeSecure(), tap = FakeTap()
        secure.bundle = "com.apple.Terminal"
        let e = engine(typing: typing, secure: secure, tap: tap)
        e.activate()
        tap.type("ghbdtn")
        tap.handler?(.space)
        XCTAssertTrue(typing.performed.isEmpty)
        _ = e
    }

    /// Undo puts the original back, once, and only in the app it happened in.
    func testUndoRestoresTheOriginalOnlyOnce() {
        let typing = FakeTyping(), tap = FakeTap()
        let e = engine(typing: typing, tap: tap)
        e.activate()
        tap.type("ghbdtn")
        tap.handler?(.space)
        e.undoLast()
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn")
        let count = typing.performed.count
        e.undoLast()
        XCTAssertEqual(typing.performed.count, count, "a second undo has nothing to undo")
        _ = e
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter LayoutEngineTests`
Expected: FAIL — `cannot find 'LayoutEngine' in scope`.

- [ ] **Step 3: Write the engine**

```swift
import Foundation
import HelmContract
import HelmRuntime

/// Wires the ports to the logic. Holds no rules of its own: every decision
/// below is made by a unit in `Logic/`, so it can be checked without typing.
public final class LayoutEngine: ModuleEngine, @unchecked Sendable {
    private let tap: KeyTapPort
    private let typing: TypingPort
    private let sources: LayoutSourcePort
    private let translation: TranslationPort
    private let spell: SpellPort
    private let secure: SecureContextPort
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    private let lock = NSLock()
    private var buffer = TypingBuffer()
    private var undo: UndoRecord?
    private var scope: AppScope
    private var exceptions: Exceptions
    private var conversions = 0
    /// Set while performing a conversion, so the events it generates are not
    /// read back as typing.
    private var performing = false

    public init(tap: KeyTapPort,
                typing: TypingPort,
                sources: LayoutSourcePort,
                translation: TranslationPort,
                spell: SpellPort,
                secure: SecureContextPort,
                rules: [String: Bool],
                exceptions: [String],
                transport: LocalTransport = LocalTransport()) {
        self.tap = tap
        self.typing = typing
        self.sources = sources
        self.translation = translation
        self.spell = spell
        self.secure = secure
        self.scope = AppScope(rules: rules)
        self.exceptions = Exceptions(words: exceptions)
        self.localTransport = transport
        self.transport = transport
    }

    public func activate() {
        _ = tap.start { [weak self] event in self?.handle(event) }
        emitState()
    }

    public func deactivate() {
        tap.stop()
        lock.lock(); buffer.clear(); undo = nil; lock.unlock()
        emitState()
    }

    // MARK: - The pipeline

    private func handle(_ event: TypingBuffer.Event) {
        lock.lock()
        guard !performing else { lock.unlock(); return }
        // Anything that could have moved the caret ends the chance to undo.
        if case .character = event {} else { undo?.invalidate() }
        let finished = buffer.accept(event)
        lock.unlock()
        guard let word = finished else { return }
        convertIfNeeded(word)
    }

    private func convertIfNeeded(_ word: String) {
        let bundleID = secure.frontmostBundleID()
        guard scope.allows(bundleID) else { return }
        guard !secure.isSecure() else {
            lock.lock(); buffer.clear(); lock.unlock()
            emitState()
            return
        }
        guard let from = sources.current(),
              let to = sources.installed().first(where: { $0 != from }),
              let translated = translation.translate(word, from: from, to: to),
              let typedIsWord = spell.isWord(word, sourceID: from),
              let translatedIsWord = spell.isWord(translated, sourceID: to)
        else { return }

        let decision = LayoutVerdict.decide(word: word, translated: translated,
                                            validAsTyped: typedIsWord,
                                            validTranslated: translatedIsWord,
                                            exceptions: exceptions.words)
        guard case .convert(let replacement) = decision,
              let plan = SwitchPlan.make(replacing: word, with: replacement) else { return }

        perform(plan)
        sources.select(to)
        lock.lock()
        undo = UndoRecord(event: ConversionEvent(before: word, after: replacement,
                                                 app: bundleID))
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

    private func perform(_ plan: SwitchPlan) {
        lock.lock(); performing = true; lock.unlock()
        _ = typing.perform(plan)
        lock.lock(); performing = false; buffer.clear(); lock.unlock()
    }

    private func emitState() {
        lock.lock()
        let state = LayoutState(enabled: true, automatic: true,
                                suspended: secure.isSecure(),
                                lastConversion: undo?.event,
                                conversionsToday: conversions)
        lock.unlock()
        if let data = try? JSONEncoder().encode(state) {
            localTransport.emit(EngineEvent(name: "layoutState", payload: data))
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter LayoutEngineTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Layout/Engine/LayoutEngine.swift Tests/Modules/Layout/EngineTests/LayoutEngineTests.swift
git commit -m "feat(layout): engine"
```

---

### Task 9: Production ports

**Files:**
- Create: `Sources/Modules/Layout/Engine/SystemPorts.swift`

- [ ] **Step 1: Write the ports**

The four workarounds from the spec live here and nowhere else: the tap is
listen-only, replacement is synthesised Unicode rather than the clipboard,
translation goes through `UCKeyTranslate` against installed layouts, and Helm's
own events carry a marker so the tap does not eat its own output.

```swift
import AppKit
import Carbon
import HelmRuntime

/// Marks every event Helm synthesises. The tap drops anything carrying it —
/// without this the tap reads its own replacement back as typing and converts
/// it again, forever.
private let helmEventMarker: Int64 = 0x48_45_4C_4D   // "HELM"

public final class CGKeyTap: KeyTapPort, @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@Sendable (TypingBuffer.Event) -> Void)?

    public init() {}

    public func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        handler = onEvent
        // Listen-only: `listenOnly` means the tap reports keys and never
        // delays or swallows them, so a hung handler cannot freeze typing.
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let port = Unmanaged<CGKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                port.deliver(event)
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
        tap = nil; source = nil; handler = nil
    }

    private func deliver(_ event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) != helmEventMarker else { return }
        if event.type == .leftMouseDown { handler?(.click); return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch Int(keyCode) {
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
            guard length > 0, let scalar = String(utf16CodeUnits: characters, count: length).first
            else { return }
            if scalar.isLetter { handler?(.character(scalar)) } else { handler?(.punctuation(scalar)) }
        }
    }
}

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

public struct TISLayoutSources: LayoutSourcePort {
    public init() {}

    public func installed() -> [String] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        return list.compactMap(Self.identifier(of:))
    }

    public func current() -> String? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue().flatMap(Self.identifier(of:))
    }

    public func select(_ sourceID: String) {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource],
              let match = list.first(where: { Self.identifier(of: $0) == sourceID })
        else { return }
        TISSelectInputSource(match)
    }

    private static func identifier(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

/// The same key presses read through another layout, via `UCKeyTranslate`
/// against the layouts actually installed — a hard-coded ЙЦУКЕН↔QWERTY table
/// would support exactly two layouts and mangle a third.
public struct UCTranslation: TranslationPort {
    public init() {}

    public func translate(_ word: String, from: String, to: String) -> String? {
        guard let fromKeys = Self.keyCodes(for: word, in: from) else { return nil }
        return Self.string(fromKeyCodes: fromKeys, in: to)
    }

    private static func layoutData(_ sourceID: String) -> Data? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return nil }
        for source in list {
            guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  (Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String) == sourceID,
                  let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { continue }
            return Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        }
        return nil
    }

    /// Which keys would produce this string in the given layout. Built by
    /// walking the layout once — the same table the system uses, so a layout
    /// Helm has never heard of still works.
    private static func keyCodes(for word: String, in sourceID: String) -> [UInt16]? {
        guard let table = characterTable(sourceID) else { return nil }
        var codes: [UInt16] = []
        for character in word.lowercased() {
            guard let code = table.first(where: { $0.value == character })?.key else { return nil }
            codes.append(code)
        }
        return codes
    }

    private static func string(fromKeyCodes codes: [UInt16], in sourceID: String) -> String? {
        guard let table = characterTable(sourceID) else { return nil }
        var out = ""
        for code in codes {
            guard let character = table[code] else { return nil }
            out.append(character)
        }
        return out
    }

    /// keyCode → the character it types, for the printable range.
    private static func characterTable(_ sourceID: String) -> [UInt16: Character]? {
        guard let data = layoutData(sourceID) else { return nil }
        var table: [UInt16: Character] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            var deadKeyState: UInt32 = 0
            for code in UInt16(0)...UInt16(50) {
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0,
                                            UInt32(LMGetKbdType()),
                                            UInt32(kUCKeyTranslateNoDeadKeysBit),
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

/// The system's own dictionaries. Nil means "no dictionary for this language",
/// which is not the same as "not a word" and must not be read as one.
public struct SystemSpell: SpellPort {
    public init() {}

    public func isWord(_ word: String, sourceID: String) -> Bool? {
        let checker = NSSpellChecker.shared
        guard let language = Self.language(for: sourceID),
              checker.availableLanguages.contains(where: { $0.hasPrefix(language) })
        else { return nil }
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language,
                                          wrap: false, inSpellDocumentWithTag: 0,
                                          wordCount: nil)
        return range.location == NSNotFound
    }

    /// "com.apple.keylayout.Russian" → "ru".
    private static func language(for sourceID: String) -> String? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return nil }
        for source in list {
            guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  (Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String) == sourceID,
                  let languagesPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            else { continue }
            let languages = Unmanaged<CFArray>.fromOpaque(languagesPointer)
                .takeUnretainedValue() as? [String]
            return languages?.first
        }
        return nil
    }
}

public struct AXSecureContext: SecureContextPort {
    public init() {}

    public func isSecure() -> Bool {
        if IsSecureEventInputEnabled() { return true }
        // A password field the app did mark: role is the only signal there is.
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXRoleAttribute as CFString, &role) == .success
        else { return false }
        return (role as? String) == (kAXSecureTextFieldRole as String)
    }

    public func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Modules/Layout/Engine/SystemPorts.swift
git commit -m "feat(layout): production ports"
```

---

### Task 10: UI

**Files:**
- Create: `Sources/Modules/Layout/UI/LayoutStrings.swift`
- Create: `Sources/Modules/Layout/UI/LayoutViewModel.swift`
- Create: `Sources/Modules/Layout/UI/LayoutSettingsPage.swift`
- Create: `Sources/Modules/Layout/UI/LayoutDescriptor.swift`

- [ ] **Step 1: Strings**

All eight languages, per the house rule. `LayoutStrings.swift`:

```swift
import HelmUI

enum LyStr {
    static var moduleName: String { L("Layout", [.ru: "Раскладка", .es: "Distribución", .fr: "Disposition", .de: "Belegung", .ja: "キーボード配列", .zh: "键盘布局", .pt: "Layout"]) }
    static var summary: String { L("Fixes words typed in the wrong keyboard layout.", [.ru: "Исправляет слова, набранные не в той раскладке.", .es: "Corrige palabras escritas en la distribución equivocada.", .fr: "Corrige les mots tapés dans la mauvaise disposition.", .de: "Korrigiert Wörter, die in der falschen Belegung getippt wurden.", .ja: "誤った配列で入力した単語を修正します。", .zh: "修正用错误键盘布局输入的单词。", .pt: "Corrige palavras digitadas no layout errado."]) }
    static var automatic: String { L("Fix as I type", [.ru: "Исправлять по ходу набора", .es: "Corregir mientras escribo", .fr: "Corriger pendant la saisie", .de: "Beim Tippen korrigieren", .ja: "入力しながら修正", .zh: "输入时自动修正", .pt: "Corrigir enquanto digito"]) }
    static var needsAccessibility: String { L("Without Accessibility Helm cannot see what you type, and this does nothing.", [.ru: "Без универсального доступа Helm не видит набранное, и это не работает.", .es: "Sin Accesibilidad, Helm no ve lo que escribes y esto no funciona.", .fr: "Sans l’Accessibilité, Helm ne voit pas ce que vous tapez et ceci ne fait rien.", .de: "Ohne Bedienungshilfen sieht Helm nichts von dem, was du tippst — das hier bleibt wirkungslos.", .ja: "アクセシビリティがないと入力内容を読み取れず、この機能は動作しません。", .zh: "没有辅助功能权限，Helm 无法读取输入，此功能不起作用。", .pt: "Sem Acessibilidade o Helm não vê o que você digita e isto não faz nada."]) }
    static var suspended: String { L("Paused — the system is in secure input", [.ru: "Приостановлено — система в защищённом вводе", .es: "En pausa: el sistema está en entrada segura", .fr: "En pause — le système est en saisie sécurisée", .de: "Pausiert — das System ist in sicherer Eingabe", .ja: "一時停止中 — システムがセキュア入力です", .zh: "已暂停——系统处于安全输入状态", .pt: "Pausado — o sistema está em entrada segura"]) }
    static var exceptions: String { L("Never change these words", [.ru: "Никогда не менять эти слова", .es: "Nunca cambiar estas palabras", .fr: "Ne jamais changer ces mots", .de: "Diese Wörter nie ändern", .ja: "これらの単語は変更しない", .zh: "从不修改这些词", .pt: "Nunca alterar estas palavras"]) }
    static var exceptionsHint: String { L("One per line.", [.ru: "По одному в строке.", .es: "Uno por línea.", .fr: "Un par ligne.", .de: "Eines pro Zeile.", .ja: "1行に1つ。", .zh: "每行一个。", .pt: "Um por linha."]) }
    static var metricToday: String { L("TODAY", [.ru: "СЕГОДНЯ", .es: "HOY", .fr: "AUJOURD’HUI", .de: "HEUTE", .ja: "本日", .zh: "今天", .pt: "HOJE"]) }
    static var metricState: String { L("STATE", [.ru: "СОСТОЯНИЕ", .es: "ESTADO", .fr: "ÉTAT", .de: "STATUS", .ja: "状態", .zh: "状态", .pt: "ESTADO"]) }
    static var on: String { L("On", [.ru: "Вкл", .es: "Sí", .fr: "Oui", .de: "An", .ja: "オン", .zh: "开", .pt: "Sim"]) }
    static var off: String { L("Off", [.ru: "Выкл", .es: "No", .fr: "Non", .de: "Aus", .ja: "オフ", .zh: "关", .pt: "Não"]) }
    static var apps: String { L("Apps", [.ru: "Приложения", .es: "Apps", .fr: "Apps", .de: "Apps", .ja: "アプリ", .zh: "应用", .pt: "Apps"]) }
    static var appsHint: String { L("Terminals and password managers are left alone unless you say otherwise.", [.ru: "Терминалы и менеджеры паролей не трогаются, пока вы не разрешите.", .es: "Los terminales y gestores de contraseñas se dejan en paz salvo que indiques lo contrario.", .fr: "Les terminaux et gestionnaires de mots de passe sont ignorés sauf indication contraire.", .de: "Terminals und Passwortmanager bleiben unangetastet, sofern du nichts anderes sagst.", .ja: "ターミナルとパスワード管理アプリは、許可しない限り対象外です。", .zh: "除非你另行允许，终端和密码管理器不会被处理。", .pt: "Terminais e gerenciadores de senha ficam de fora, a menos que você permita."]) }
}
```

- [ ] **Step 2: View model**

`LayoutViewModel.swift`:

```swift
import SwiftUI
import HelmContract
import HelmUI
import Module_Layout_Engine

@MainActor public final class LayoutViewModel: ObservableObject {
    @Published public private(set) var state = LayoutState(enabled: false, automatic: false,
                                                           suspended: false,
                                                           lastConversion: nil,
                                                           conversionsToday: 0)
    public let vm: ModuleViewModel
    private static var cached: LayoutViewModel?

    public static func shared(vm: ModuleViewModel) -> LayoutViewModel {
        if let cached, cached.vm === vm { return cached }
        let created = LayoutViewModel(vm: vm)
        cached = created
        return created
    }

    private init(vm: ModuleViewModel) {
        self.vm = vm
        let events = vm.transport.events
        Task { [weak self] in
            for await event in events { await self?.handle(event) }
        }
    }

    private func handle(_ event: EngineEvent) {
        guard event.name == "layoutState",
              let decoded = try? JSONDecoder().decode(LayoutState.self, from: event.payload)
        else { return }
        state = decoded
    }
}
```

- [ ] **Step 3: Settings page**

`LayoutSettingsPage.swift`:

```swift
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

public struct LayoutSettingsPage: View {
    @ObservedObject private var vm: LayoutViewModel
    private let store: NamespacedStore

    @State private var automatic: Bool
    @State private var exceptions: String
    @State private var accessibility: PermissionState = .granted

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = LayoutViewModel.shared(vm: vm)
        self.store = store
        _automatic = State(initialValue: store.bool("automatic", default: true))
        _exceptions = State(initialValue: store.stringArray("exceptions", default: [])
            .joined(separator: "\n"))
    }

    public var body: some View {
        Form {
            Section {
                HelmMetricStrip([
                    .init(vm.state.suspended ? LyStr.off : LyStr.on, LyStr.metricState,
                          tint: vm.state.suspended ? .orange : .green),
                    .init("\(vm.state.conversionsToday)", LyStr.metricToday),
                ])
            }
            Section {
                Toggle(LyStr.automatic, isOn: $automatic)
                    .onChange(of: automatic) { _, value in
                        store.set(value, for: "automatic")
                        vm.vm.send("settingsChanged")
                    }
                // macOS gives a tap nothing without this grant, so the switch
                // above would be on and silent.
                if accessibility == .denied {
                    HelmPermissionNote(need: .accessibility, text: LyStr.needsAccessibility)
                }
                if vm.state.suspended {
                    Text(LyStr.suspended).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(LyStr.exceptions) {
                Text(LyStr.exceptionsHint).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $exceptions)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 90)
                    .onChange(of: exceptions) { _, value in
                        store.set(value.split(separator: "\n").map(String.init), for: "exceptions")
                        vm.vm.send("settingsChanged")
                    }
            }
            Section(LyStr.apps) {
                Text(LyStr.appsHint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 744, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task { accessibility = PermissionCheck.currentAccessibility() }
    }
}
```

- [ ] **Step 4: Descriptor**

`LayoutDescriptor.swift`:

```swift
import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Layout_Engine

public struct LayoutDescriptor: ModuleDescriptor {
    public static let id = ModuleID(rawValue: "layout")
    public static let metadata = ModuleMetadata(name: LyStr.moduleName,
                                                summary: LyStr.summary,
                                                sfSymbol: "keyboard")
    public static let isolation = ModuleIsolation.inProcess
    public static let category = ModuleCategory.utilities

    private var store: NamespacedStore?

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        LayoutEngine(tap: CGKeyTap(),
                     typing: SynthesisTyping(),
                     sources: TISLayoutSources(),
                     translation: UCTranslation(),
                     spell: SystemSpell(),
                     secure: AXSecureContext(),
                     rules: [:],
                     exceptions: store.stringArray("exceptions", default: []))
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { nil }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(LayoutSettingsPage(
            vm: vm,
            store: store ?? NamespacedStore(namespace: "layout", backing: UserDefaults.standard)))
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds clean. Match `ModuleMetadata`, `ModuleCategory` and the descriptor's `store` handling to `DiskDescriptor.swift`, which is the closest existing example — copy its shape exactly rather than inventing one.

- [ ] **Step 6: Commit**

```bash
git add Sources/Modules/Layout/UI
git commit -m "feat(layout): settings page and descriptor"
```

---

### Task 11: Register, permission, release

**Files:**
- Modify: `Sources/HelmApp/ModuleRegistry.swift`
- Modify: `Sources/HelmRuntime/PermissionNeed.swift`
- Modify: `ARCHITECTURE.md`, `CHANGELOG.md`, `Sources/HelmApp/ChangelogData.swift`, `README.md`

- [ ] **Step 1: Register the module**

In `Sources/HelmApp/ModuleRegistry.swift` add `import Module_Layout_UI` and append `LayoutDescriptor()` to `all`.

- [ ] **Step 2: Declare the permission**

In `Sources/HelmRuntime/PermissionNeed.swift` add a `layoutSwitch` case to `Feature` mapping to `.accessibility`, following the existing `pointerNudge` entry exactly.

- [ ] **Step 3: Run the whole suite**

Run: `swift test`
Expected: every test passes, including the ~31 new ones.

- [ ] **Step 4: Verify on the machine**

```bash
bash Scripts/package-app.sh
```

Expected: `==> Signature verified`. Then install and grant Accessibility to the new build:

```bash
pkill -f 'MacOS/HelmApp'; rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

Then, by hand in TextEdit: type `ghbdtn` and a space, and watch it become `привет`. Type `ras` and a space, and watch nothing happen. Open Terminal and type `ghbdtn ` — nothing happens there either.

- [ ] **Step 5: Documentation**

Add the module to the `README.md` table, a `## Layout switching` section to `ARCHITECTURE.md` describing the four workarounds and why the tap is listen-only, an entry to `CHANGELOG.md`, and a user-facing `ChangeItem` to `ChangelogData.swift` in all eight languages.

- [ ] **Step 6: Commit and release to dev**

```bash
git add -A
git commit -m "feat(layout): register the module, docs"
```

Then bump `Resources/HelmApp/Info.plist`, and follow VERSIONING.md — `git push` **before** `gh release create`, both dmg and zip attached, and the `sha256` lines from `make-zip.sh` and `make-dmg.sh` in the notes, or the updater will refuse to install it silently.

---

## Self-review

**Spec coverage.** `TypingBuffer` → Task 2. `LayoutVerdict` and every guard rule → Task 3. `SwitchPlan` → Task 4. `Exceptions`, `AppScope` → Task 5. `UndoRecord` → Task 6. All six ports → Task 7, implemented in Task 9 with the four documented workarounds. Automatic conversion, secure-context refusal and undo → Task 8. Permission surface → Tasks 10 and 11. The two hotkeys are **not** covered by a task: `undoLast()` exists on the engine and the "convert last word" path does not. That is a gap in this plan, and it is deliberate — hotkey registration goes through `HotkeyManager`, which today is hard-wired to Keep Awake, and generalising it is its own change. **Task 12 below closes it.**

**Placeholders.** None: every step carries the code or the exact command.

**Type consistency.** `TypingBuffer.Event` is used identically by `KeyTapPort` (Task 7), the engine (Task 8) and `CGKeyTap` (Task 9). `SwitchPlan.make(replacing:with:)` returns an optional in Task 4 and is unwrapped at both call sites. `LayoutState` is encoded in Task 8 under the event name `layoutState` and decoded under the same name in Task 10.

---

### Task 12: Hotkeys

**Files:**
- Modify: `Sources/HelmApp/HotkeyManager.swift`
- Modify: `Sources/HelmApp/AppDelegate.swift`

- [ ] **Step 1: Give the manager more than one action**

`HotkeyManager` currently exposes a single `onFire`. Change it to a dictionary keyed by an action name, registering one Carbon hotkey per entry, and — this is the bug the accessibility pass found in the recorder, do not reintroduce it — keep the registration result so a combination already taken by another app can be reported rather than silently ignored.

- [ ] **Step 2: Wire the two layout actions**

In `AppDelegate.applicationDidFinishLaunching`, beside the existing Keep Awake binding, send `undoLastConversion` and `convertLastWord` to the layout engine's transport.

- [ ] **Step 3: Handle them in the engine**

In `LayoutEngine.wireTransport`, add `case "undoLastConversion": self.undoLast()` and a `convertLastWord` case that runs the same pipeline as `convertIfNeeded` but skips `LayoutVerdict` — the user asked explicitly — while still refusing in secure contexts.

- [ ] **Step 4: Test**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HelmApp Sources/Modules/Layout
git commit -m "feat(layout): convert and undo hotkeys"
```

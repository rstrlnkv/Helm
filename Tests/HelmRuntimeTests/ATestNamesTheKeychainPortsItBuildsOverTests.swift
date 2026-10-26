import Foundation
import HelmTestSupport
import XCTest

/// A test that builds an engine or a view model names the ports it builds it
/// over — or it runs against the person's own login keychain.
///
/// Three separate incidents in one wave, each the same shape and each invisible
/// to every other check in this suite:
///
/// - an Autopilot test left `sequence:` on its default and raised the high-water
///   mark of the rule-set item on the machine running the suite, which is the
///   number a rolled-back rule set is judged against for ever after;
/// - the undo fakes were added while a keychain port was still defaulted, so the
///   first run of the file created the item it was meant to stand in for;
/// - three files in Duplicates' UI target built a `DuplicatesViewModel` on the
///   production `SettingGuard`, and `init` reads the keep policy through it —
///   `DuplicatesSettings.keepPolicy` answers `.unset` for an empty store and
///   spends `establishKey()` on the way out, which is `SecItemAdd` of
///   `com.helm.app / settings-seal` into somebody's login keychain.
///
/// **The machine is a boundary of its own.** A test may read the Mac it runs on;
/// it may not leave an item in its keychain. Nothing else in the suite can see
/// this happen: the call compiles, the default is the production port, and the
/// only evidence is an item that appears on the developer's machine and is then
/// indistinguishable from one the app itself created.
///
/// **The list of subjects is not written here.** A hand-written list of types is
/// tied to the thing it names or it is a comment (CLAUDE.md), so the subjects are
/// *derived*: every `init` in `Sources/` with a parameter whose default reaches
/// the keychain is a subject, and that parameter's own label is what a test has
/// to name. A module that grows a fourth port arrives in this scan without
/// anybody remembering it, and a port renamed makes the scan ask for the new
/// label.
///
/// **Why the source and not the behaviour.** The behaviour is "the suite left
/// nothing in the keychain", and the only way to ask it is to read the keychain
/// — which is the boundary this test defends.
/// `StoresOfTheirsAskIfThisIsATestTests` is the family sibling and gives the same
/// reason for the same shape.
///
/// **What it deliberately does not cover.** A type whose port has *no* default —
/// `SealedRules(store:keys:sequence:)` — cannot be built wrong, because the
/// compiler asks for the argument. That is the better fix, and this scan does not
/// need to know about it: a port with a production default is exactly the case
/// the compiler cannot help with, which is why the default is what selects a
/// subject.
final class ATestNamesTheKeychainPortsItBuildsOverTests: XCTestCase {

    // MARK: - Exceptions

    /// Constructions where the production port is the *subject* of the test, so
    /// handing it a double would be testing the double.
    ///
    /// Empty, and that is a finding rather than an oversight: nothing in this
    /// tree exercises `KeychainSealKey`, `KeychainRuleKey` or
    /// `KeychainRuleSequence` against the real item, because doing so would write
    /// into the developer's own keychain. All three are covered through doubles.
    /// The list exists so the next person who genuinely needs the real item — a
    /// check gated behind `HELM_BENCH=1`, say — writes the reason down beside it
    /// instead of deleting the rule. The shape is a repo-relative `file:line`
    /// and why.
    private static let allowed: [String: String] = [:]

    // MARK: - The rule

    func testEveryTestConstructionNamesThePortsThatWouldReachTheKeychain() throws {
        let unported = try Self.scanOfTests().misses
            .filter { Self.allowed[$0.where_] == nil }
            .map { "\($0.where_) \($0.type)(…) leaves "
                   + $0.missing.sorted().map { "\($0):" }.joined(separator: " ")
                   + " on its production default" }
        XCTAssertEqual(unported, [], """
            these build a type over a port whose default is the login keychain, so running them \
            reads — and where the item is absent, creates — an item in the keychain of whoever \
            runs the suite. Hand each one a double: SealKeyProbe or SilentSealKey \
            (HelmTestSupport), TestRuleKey / TestRuleSequence (Autopilot), PlantedSealKey \
            (Duplicates).
            """)
    }

    // MARK: - The scan itself, which is the half that goes quiet

    /// A scan that has stopped matching is a green test about nothing, so both
    /// halves are asserted before the rule that reads them.
    ///
    /// The floors name types rather than counting them, because a count is the
    /// thing this suite has been wrong about before. `AutopilotEngine` and
    /// `DuplicatesViewModel` are the two the incidents happened on; both take a
    /// keychain-defaulted port today, and a build in which neither does is a
    /// build where this rule guards nothing and should be read rather than left
    /// green.
    func testTheScanStillFindsTheSubjectsAndTheirCallSites() throws {
        let subjects = try Self.subjects()
        XCTAssertEqual(subjects["AutopilotEngine"], ["keys", "sequence"],
                       "AutopilotEngine's keychain defaults are gone, or the scan is not reading "
                       + "Sources — it found \(subjects.keys.sorted())")
        XCTAssertEqual(subjects["DuplicatesViewModel"], ["settings"],
                       "DuplicatesViewModel's settings: default is gone, or the scan is not "
                       + "reading Sources — it found \(subjects.keys.sorted())")

        let constructions = try Self.scanOfTests().constructions
        XCTAssertGreaterThanOrEqual(constructions, 15, """
            \(constructions) constructions of \(subjects.keys.sorted()) in Tests/, where the \
            tree has well over a dozen — the walk, the extension filter or the balance reader \
            has broken rather than the tree having improved.
            """)
    }

    /// The one constant in this tree a keychain port hides behind, spelled as a
    /// use site outside its own type has to spell it.
    static let constant = "DuplicatesSettings.guardOfScanSettings"

    /// The indirection is followed, or `settings:` would never be a subject at
    /// all: its default is `DuplicatesSettings.guardOfScanSettings`, and the word
    /// «Keychain» is one declaration further down.
    ///
    /// The owner is half of what is asserted, and deliberately: the member name
    /// alone is what this scan used to key by, and
    /// two statics sharing a name overwrote each other, which is why it no longer does (`merge`).
    func testAPortNamedThroughAConstantIsStillAPort() throws {
        let names = try Self.keychainNames()
        XCTAssertTrue(names.contains(Self.constant), """
            DuplicatesSettings.guardOfScanSettings is a SettingGuard over KeychainSealKey and the \
            scan did not recognise it, so every settings: default reads as harmless. It found \
            \(names.sorted().prefix(40)).
            """)
    }

    // MARK: - Deriving the subjects

    /// **Every derivation below is computed once a process, and the reason is
    /// XCTest's own shape.** It builds a fresh instance per test case, so an
    /// instance's worth of scanning is paid by every case in the class — this
    /// one has three, and each of them starts a whole-tree derivation. Before
    /// these three memos it walked and parsed `Sources/` five times over and
    /// `Tests/` twice more, and the class cost 11.1 s of a suite whose other
    /// hundred-odd classes are milliseconds.
    ///
    /// A `static let` is the memo because Swift computes one lazily and exactly
    /// once, however many cases race for it, and `Result` is what lets a
    /// throwing derivation live in one. `SwiftSource.code(under:)` underneath
    /// does the same for the reading itself, so the two derivations that both
    /// read `Sources/` load it once between them.
    private static let namesOnce = Result { try deriveKeychainNames() }
    private static let subjectsOnce = Result { try deriveSubjects() }
    private static let scanOfTestsOnce = Result {
        try PortsAtConstruction.misses(of: subjects(), under: "Tests")
    }

    /// Every static declaration in `Sources/` whose value reaches the keychain,
    /// by name — so a default naming one of them is recognised as a port however
    /// many constants it hides behind.
    ///
    /// Two hops is all the tree has (`guardOfScanSettings` → `SettingGuard` →
    /// `KeychainSealKey`); the fixed point below would find a third.
    static func keychainNames() throws -> Set<String> { try namesOnce.get() }

    /// Every type in `Sources/` with an `init` parameter defaulted to a keychain
    /// port, and the labels those parameters carry.
    static func subjects() throws -> [String: [String]] { try subjectsOnce.get() }

    /// The offending constructions and how many were seen at all — one reading
    /// of `Tests/` for the two cases that ask.
    static func scanOfTests() throws
    -> (misses: [PortsAtConstruction.Miss], constructions: Int) {
        try scanOfTestsOnce.get()
    }

    private static func deriveKeychainNames() throws -> Set<String> {
        var bodies: [String: String] = [:]
        for file in try SwiftSource.code(under: "Sources") {
            merge(&bodies, from: file.text)
        }
        return closure(of: bodies)
    }

    /// The fixed point: a declaration reaches the keychain when its own value
    /// spells `Keychain`, or names a declaration that does.
    private static func closure(of bodies: [String: String]) -> Set<String> {
        var reaching = Set(bodies.filter { $0.value.contains("Keychain") }.keys)
        var grew = true
        while grew {
            grew = false
            for (name, body) in bodies where !reaching.contains(name) {
                guard references(body, from: owner(of: name), reaching) else { continue }
                reaching.insert(name)
                grew = true
            }
        }
        return reaching
    }

    /// The type a key names, or nothing where the declaration had no type around
    /// it — which `merge` writes as a bare key, and Swift does not allow.
    private static func owner(of key: String) -> String? {
        let parts = key.split(separator: ".")
        return parts.count == 2 ? String(parts[0]) : nil
    }

    /// Whether `text`, written inside `owner`, names one of `reaching`.
    ///
    /// Two spellings and no more, because they are the two Swift itself resolves:
    /// the qualified `Owner.member`, which is how every use site outside the
    /// owning type writes it — `DuplicatesSettings.guardOfScanSettings` is the
    /// one this tree turns on — and the bare `member`, which means that
    /// declaration only inside the type that declares it.
    ///
    /// **A bare name is never matched across owners**, and that is the half that
    /// keeps the qualified key honest. Match `shared` against every `X.shared`
    /// and the fixed point swallows the tree: a body that merely says the word
    /// joins the set it was being tested against, every `init` defaulted to
    /// anything called `shared` becomes a keychain port, and the rule fails over
    /// call sites that never went near a keychain. A dot counts as a name
    /// character on either side, so `Elsewhere.shared` is not a bare `shared`.
    private static func references(_ text: String, from owner: String?,
                                   _ reaching: Set<String>) -> Bool {
        reaching.contains { name in
            if text.contains(name) { return true }
            let parts = name.split(separator: ".")
            guard parts.count == 2, let owner, String(parts[0]) == owner else { return false }
            return word(String(parts[1]), isIn: text)
        }
    }

    /// `needle` in `text` with a name character on neither side.
    private static func word(_ needle: String, isIn text: String) -> Bool {
        var rest = text[...]
        while let found = rest.range(of: needle) {
            let before = found.lowerBound == text.startIndex
                ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !isNameCharacter(before) && !isNameCharacter(after) { return true }
            rest = text[found.upperBound...]
        }
        return false
    }

    private static func isNameCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "."
    }

    /// Hoisted out of `merge`, which is called once per file: the pattern was
    /// compiled 483 times a pass and there is one pattern.
    private static let declaration = try? NSRegularExpression(
        pattern: #"static\s+(?:let|var)\s+([A-Za-z_]\w*)\s*(?::[^=]+)?=\s*(.*)$"#,
        options: .anchorsMatchLines)

    /// `Owner.member` → `static let member = <value>` and what its value says,
    /// with three following lines because these declarations spill. A longer one
    /// is simply not recognised, which errs towards reporting a call site rather
    /// than excusing it.
    ///
    /// **The key carries the owner, and that is the whole of it.** It was the
    /// bare member name, so two declarations sharing one overwrote each other
    /// and whichever the walk reached last was the only one this scan could ever
    /// see — `command grep -rn 'static let shared' Sources/` says how many names
    /// are already shared. A keychain port hidden behind the loser never entered
    /// `reaching`, no default naming it was ever a port, and the rule went green
    /// over the call sites it exists for with nothing on screen to say so.
    /// `SwiftSource.innermost` over
    /// `SwiftSource.typeBodies` is the same owner reading `ports(in:reaching:)`
    /// does, and it is right for the same reason: the owner is the type whose
    /// braces are around the declaration, not the last one declared above it.
    private static func merge(_ bodies: inout [String: String], from source: String) {
        guard let declaration = Self.declaration else { return }
        let types = SwiftSource.typeBodies(in: source)
        let lines = source.components(separatedBy: "\n")
        var offset = 0
        for (index, line) in lines.enumerated() {
            defer { offset += line.count + 1 }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = declaration.firstMatch(in: line, range: range),
                  let name = Range(match.range(at: 1), in: line)
            else { continue }
            let at = offset + line.distance(from: line.startIndex, to: name.lowerBound)
            let owner = SwiftSource.innermost(types, around: at)?.name
            let key = [owner, String(line[name])].compactMap { $0 }.joined(separator: ".")
            bodies[key] = lines[index...].prefix(4).joined(separator: " ")
        }
    }

    private static func deriveSubjects() throws -> [String: [String]] {
        let reaching = try keychainNames()
        var out: [String: [String]] = [:]
        // The same reading `keychainNames` walked; it had its own second walk
        // of `Sources/` here, so one call to this cost two loads and two parses
        // of the tree.
        for file in try SwiftSource.code(under: "Sources") {
            for (owner, labels) in ports(in: file.text, reaching: reaching) {
                out[owner, default: []] += labels
            }
        }
        return out.mapValues { Array(Set($0)).sorted() }
    }

    /// The same reading, of one file's text.
    static func ports(in source: String, reaching: Set<String>) -> [String: [String]] {
        let bodies = SwiftSource.typeBodies(in: source)
        var out: [String: [String]] = [:]
        for call in SwiftSource.callSites(of: "init", in: source, wholeWords: false) {
            // The owner is read before the labels rather than after, because a
            // default written bare — `= guardOfScanSettings`, inside the type
            // that declares it — only resolves once we know which type that is.
            guard let owner = SwiftSource.innermost(bodies, around: call.characterOffset)?.name
            else { continue }
            let labels = call.arguments.compactMap { argument -> String? in
                guard let equals = argument.range(of: "=") else { return nil }
                let value = String(argument[equals.upperBound...])
                guard value.contains("Keychain") || references(value, from: owner, reaching)
                else { return nil }
                return label(of: argument)
            }
            guard !labels.isEmpty else { continue }
            out[owner, default: []] += labels
        }
        return out.mapValues { Array(Set($0)).sorted() }
    }

    /// The label of a parameter declaration — `keys: RuleKeyPort = …` → `keys`,
    /// and `_ store: X = …` → nothing a call site could name.
    private static func label(of parameter: String) -> String? {
        guard let head = parameter.split(separator: ":", maxSplits: 1).first else { return nil }
        let words = head.split(separator: " ").map(String.init)
        guard let first = words.first, first != "_" else { return nil }
        return first
    }

}

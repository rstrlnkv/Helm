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
    /// instead of deleting the rule. The shape is `knownAbsent`'s, one document
    /// over: a repo-relative `file:line` and why.
    private static let allowed: [String: String] = [:]

    // MARK: - The rule

    func testEveryTestConstructionNamesThePortsThatWouldReachTheKeychain() throws {
        let subjects = try Self.subjects()
        var unported: [String] = []
        for site in try Self.constructions(of: subjects) {
            guard Self.allowed[site.where_] == nil else { continue }
            let missing = site.required.filter { !site.call.names.contains($0) }
            guard !missing.isEmpty else { continue }
            unported.append("\(site.where_) \(site.type)(…) leaves "
                            + missing.sorted().map { "\($0):" }.joined(separator: " ")
                            + " on its production default")
        }
        XCTAssertEqual(unported.sorted(), [], """
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

        let sites = try Self.constructions(of: subjects)
        XCTAssertGreaterThanOrEqual(sites.count, 15, """
            \(sites.count) constructions of \(subjects.keys.sorted()) in Tests/, where the tree \
            has well over a dozen — the walk, the extension filter or the balance reader has \
            broken rather than the tree having improved.
            """)
    }

    /// The indirection is followed, or `settings:` would never be a subject at
    /// all: its default is `DuplicatesSettings.guardOfScanSettings`, and the word
    /// «Keychain» is one declaration further down.
    func testAPortNamedThroughAConstantIsStillAPort() throws {
        XCTAssertTrue(try Self.keychainNames().contains("guardOfScanSettings"), """
            DuplicatesSettings.guardOfScanSettings is a SettingGuard over KeychainSealKey and the \
            scan did not recognise it, so every settings: default reads as harmless.
            """)
    }

    // MARK: - And it reads code, not prose

    /// A fixture, because the rule has to be provably able to fail on input this
    /// tree does not contain today — and because every rule in this repository is
    /// explained in a comment that quotes the thing it forbids, so a scan that
    /// reads comments reports the explanation as the offence.
    func testTheReaderSeesCodeAndSpansLines() {
        let source = SwiftSource.code("""
        // AutopilotEngine(store: s) with no keys: — the offence, in prose
        let a = AutopilotEngine(store: s, keys: TestRuleKey(),
                                sequence: TestRuleSequence())
        let b = AutopilotEngine(store: s)  // sequence: is only mentioned here
        let c = AutopilotEngine(store: s, keys: TestRuleKey())
        """)
        let calls = SwiftSource.callSites(of: "AutopilotEngine", in: source)
        XCTAssertEqual(calls.count, 3, "a comment was read as a construction, or one was missed")
        // Spanning two lines, with the second label found on the far side of the
        // break.
        XCTAssertEqual(calls[0].names, ["store", "keys", "sequence"])
        XCTAssertEqual(calls[1].names, ["store"],
                       "a label from the line's comment tail was read as an argument")
        XCTAssertEqual(calls[2].names, ["store", "keys"])
    }

    /// A nested call must not end the argument list early, and a label inside one
    /// is not the outer call's.
    func testALabelInsideANestedCallIsNotTheOuterCalls() {
        let source = "let m = DuplicatesViewModel(vm: ModuleViewModel(settings: x), store: s)"
        XCTAssertEqual(SwiftSource.callSites(of: "DuplicatesViewModel", in: source).map(\.names),
                       [["vm", "store"]])
    }

    /// A parenthesis inside a string literal does not close the argument list.
    func testAParenthesisInAStringDoesNotCloseTheCall() {
        let source = #"let m = DuplicatesViewModel(vm: v, note: "a) b", settings: g)"#
        XCTAssertEqual(SwiftSource.callSites(of: "DuplicatesViewModel", in: source).map(\.names),
                       [["vm", "note", "settings"]])
    }

    /// And a longer name ending with a subject's is not the subject:
    /// `FakeDuplicatesViewModel(` is not `DuplicatesViewModel(`.
    func testATypeWhoseNameMerelyEndsWithASubjectsIsNotOne() {
        XCTAssertEqual(SwiftSource.callSites(of: "DuplicatesViewModel",
                                             in: "let m = FakeDuplicatesViewModel(vm: v)").count, 0)
    }

    /// A parameter with no default is not a port this rule can be about, so a
    /// type whose ports are all required contributes nothing — which is how
    /// `SealedRules` stays out of it.
    func testAPortWithNoDefaultIsNotASubject() {
        let source = SwiftSource.code("""
        final class SealedRules {
            init(store: NamespacedStore, keys: RuleKeyPort, sequence: RuleSequencePort) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: source, reaching: ["guardOfScanSettings"]), [:])
    }

    /// And one that *is* defaulted to a port is, wherever the type is declared.
    func testADefaultedPortIsFoundWithItsOwnersName() {
        let source = SwiftSource.code("""
        public final class Widget {
            public init(store: Store, keys: SealKeyPort = KeychainSealKey(service: "s"),
                        guarded: SettingGuard = DuplicatesSettings.guardOfScanSettings,
                        home: String = NSHomeDirectory()) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: source, reaching: ["guardOfScanSettings"]),
                       ["Widget": ["guarded", "keys"]],
                       "home: is not a keychain port and must not be demanded of a call site")
    }

    /// The owner of an `init` is the type whose braces are around it, not the
    /// last type declared above it.
    ///
    /// This is the reading the first version of the scan got wrong, on the very
    /// file it was written for: `DuplicatesViewModel` declares a nested
    /// `enum Phase`, the init was filed under `Phase`, and the rule then went
    /// green over three call sites — a guard that had stopped being able to fail,
    /// with nothing on screen to say so.
    func testAnInitBelowANestedTypeBelongsToTheOuterOne() {
        let source = SwiftSource.code("""
        public final class Page {
            public enum Phase { case start, running }
            public init(settings: SettingGuard = DuplicatesSettings.guardOfScanSettings) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: source, reaching: ["guardOfScanSettings"]),
                       ["Page": ["settings"]])
    }

    /// And Swift quoted inside Swift is not Swift. This file's own fixtures are
    /// `"""` blocks holding call sites, and the first run of this guard reported
    /// two of them as offences in `Tests/`.
    func testAConstructionInsideAStringLiteralIsNotAConstruction() {
        let source = SwiftSource.code(#"""
        let explanation = """
        let a = AutopilotEngine(store: s)
        """
        let real = AutopilotEngine(store: s, keys: k, sequence: q)
        """#)
        XCTAssertEqual(SwiftSource.callSites(of: "AutopilotEngine", in: source).map(\.names),
                       [["store", "keys", "sequence"]])
    }

    /// The other half of the same reading: a `//` inside a string is not a
    /// comment, so blanking it must not swallow the rest of the line.
    func testASlashInsideAStringDoesNotStartAComment() {
        let source = SwiftSource.code(#"""
        let url = "https://example.com"; let real = AutopilotEngine(store: s, keys: k)
        """#)
        XCTAssertEqual(SwiftSource.callSites(of: "AutopilotEngine", in: source).map(\.names),
                       [["store", "keys"]])
    }


    // MARK: - Deriving the subjects

    /// Every static declaration in `Sources/` whose value reaches the keychain,
    /// by name — so a default naming one of them is recognised as a port however
    /// many constants it hides behind.
    ///
    /// Two hops is all the tree has (`guardOfScanSettings` → `SettingGuard` →
    /// `KeychainSealKey`); the fixed point below would find a third.
    static func keychainNames() throws -> Set<String> {
        var bodies: [String: String] = [:]
        for file in try RepoSource.swiftFiles(under: "Sources") {
            merge(&bodies, from: SwiftSource.code(try RepoSource.text(of: file)))
        }
        var reaching = Set(bodies.filter { $0.value.contains("Keychain") }.keys)
        var grew = true
        while grew {
            grew = false
            for (name, body) in bodies where !reaching.contains(name) {
                guard reaching.contains(where: body.contains) else { continue }
                reaching.insert(name)
                grew = true
            }
        }
        return reaching
    }

    /// `static let x = <value>` and what its value says, with three following
    /// lines because these declarations spill. A longer one is simply not
    /// recognised, which errs towards reporting a call site rather than excusing
    /// it.
    private static func merge(_ bodies: inout [String: String], from source: String) {
        guard let declaration = try? NSRegularExpression(
            pattern: #"static\s+(?:let|var)\s+([A-Za-z_]\w*)\s*(?::[^=]+)?=\s*(.*)$"#,
            options: .anchorsMatchLines)
        else { return }
        let lines = source.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = declaration.firstMatch(in: line, range: range),
                  let name = Range(match.range(at: 1), in: line)
            else { continue }
            bodies[String(line[name])] = lines[index...].prefix(4).joined(separator: " ")
        }
    }

    /// Every type in `Sources/` with an `init` parameter defaulted to a keychain
    /// port, and the labels those parameters carry.
    static func subjects() throws -> [String: [String]] {
        let reaching = try keychainNames()
        var out: [String: [String]] = [:]
        for file in try RepoSource.swiftFiles(under: "Sources") {
            for (owner, labels) in ports(in: SwiftSource.code(try RepoSource.text(of: file)),
                                         reaching: reaching) {
                out[owner, default: []] += labels
            }
        }
        return out.mapValues { Array(Set($0)).sorted() }
    }

    /// The same reading, of one file's text — which is what makes the fixtures
    /// above go through exactly what the tree goes through.
    static func ports(in source: String, reaching: Set<String>) -> [String: [String]] {
        let bodies = SwiftSource.typeBodies(in: source)
        var out: [String: [String]] = [:]
        for call in SwiftSource.callSites(of: "init", in: source, wholeWords: false) {
            let labels = call.arguments.compactMap { argument -> String? in
                guard let equals = argument.range(of: "=") else { return nil }
                let value = String(argument[equals.upperBound...])
                guard value.contains("Keychain") || reaching.contains(where: value.contains)
                else { return nil }
                return label(of: argument)
            }
            guard !labels.isEmpty,
                  let owner = SwiftSource.innermost(bodies, around: call.characterOffset)?.name
            else { continue }
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

    // MARK: - The call sites in Tests/

    /// One construction of a subject in a test file.
    private struct Site {
        let file: String
        let type: String
        let call: SwiftSource.Call
        /// The labels this type's ports are spelled with.
        let required: [String]

        var where_: String { "\(file):\(call.line)" }
    }

    private static func constructions(of subjects: [String: [String]]) throws -> [Site] {
        var out: [Site] = []
        for file in try RepoSource.swiftFiles(under: "Tests") {
            let text = SwiftSource.code(try RepoSource.text(of: file))
            for (type, required) in subjects {
                out += SwiftSource.callSites(of: type, in: text).map {
                    Site(file: file, type: type, call: $0, required: required)
                }
            }
        }
        return out.sorted { ($0.file, $0.call.line) < ($1.file, $1.call.line) }
    }
}

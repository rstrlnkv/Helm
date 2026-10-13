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

    /// The files that have a descriptor or the shared host build an engine, how
    /// many calls in each do it, and why that file has no other way.
    ///
    /// Such a call names no port: `makeEngine(store:)` takes a store and nothing
    /// else, and the host hands it one over `UserDefaults.standard` and then
    /// activates the engine. So the list is the whole of what is allowed, a file
    /// at a time and by count: a file that is not here is red, a listed file with
    /// one call more is red, and so is an entry whose file has fewer than it
    /// says — the list follows the tree down and never up.
    ///
    /// **What the list does not hold.** Which calls: a file may trade one call
    /// for another and stay at its number. Which module: the reason names the
    /// descriptors as they were read, and nothing compares it with the file. And
    /// whether a real engine starts — a stub descriptor handed to the host is one
    /// more call here, told from the rest only by its reason.
    private static let builtThroughTheHost: [String: (sites: Int, why: String)] = [
        "Tests/Modules/KeepAwake/UITests/TheNoticeSaysWhatTheBannerSaysTests.swift": (1, """
            `KeepAwakeDescriptor().makeEngine`, over an in-memory store and never activated. The \
            subject is the descriptor's own wiring — whether it hands the engine the port that \
            reaches macOS — and an engine built by name would test the test's argument.
            """),
        "Tests/Modules/Layout/UITests/BuildingAnEngineDoesNotDecorateTheMenuBarTests.swift": (3, """
            `makeEngine` on a `LayoutDescriptor()` the row holds, never activated. The call is the \
            subject: what building Keyboard's engine through its descriptor puts in the menu bar.
            """),
        "Tests/HelmAppTests/ModulePageRender.swift": (1, """
            `descriptor.makeEngine` for whichever module's page is being rendered, over an \
            in-memory store. The engine is held for its type and its lifetime and never asked \
            anything: the page is answered by a fixture transport.
            """),
        "Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift": (1, """
            `descriptor.makeEngine` in a map over `ModuleRegistry.all`, over an in-memory store \
            and never activated. The subject is the registry: which of its engines conform can \
            only be asked of the engines its descriptors build.
            """),
        "Tests/HelmAppTests/AboutKeepsItsNameOnEveryRouteTests.swift": (1, """
            `ModuleHost.shared.setEnabled` with Keep Awake's descriptor: a real engine, activated. \
            The real `SettingsWindow` reads the shared host, and one route into About needs a \
            module live in it.
            """),
        "Tests/HelmAppTests/DisclosureProbe.swift": (1, """
            `ModuleHost.shared.bootstrap()`: a real engine for every module not switched off, \
            activated, dropped by `shutdown()` in `tearDown`. The panel's card is measured over \
            the host's own enabled modules.
            """),
        "Tests/HelmAppTests/TheStatusBadgeMovesToTheWindowsTrailingEdgeTests.swift": (3, """
            `ModuleHost.shared.setEnabled` with Keep Awake's, the VPN's and Keyboard's descriptors: \
            real engines, activated. The status item is patched from the shared host's live \
            modules, and the file's header says why they are real and not a recorder.
            """),
        "Tests/HelmAppTests/TheWindowIsBuiltFromTheShellsViewTests.swift": (4, """
            `setEnabled` with Keep Awake's descriptor, on and off, twice — once on \
            `ModuleHost.shared` and once on a `host` bound to it: a real engine, activated. The \
            subject is what the window's model does when the host's live set moves.
            """),
        "Tests/HelmAppTests/AModuleSwitchReachesTheBarWithoutShakingItTests.swift": (19, """
            `ModuleHost.shared.setEnabled` with Keep Awake's and the VPN's descriptors, on and off: \
            real engines, activated. The subject is the pair of notifications a module switch \
            posts, and `setEnabled` is what posts them.
            """),
        "Tests/HelmAppTests/TheStatusBadgeSitsAsFarFromTheRightEdgeAsFromTheTopTests.swift": (1, """
            `ModuleHost.shared.setEnabled` in a loop over the descriptors a row asks for — Keep \
            Awake's, and the VPN's beside it in one row: real engines, activated. The real \
            `SettingsWindow` it measures reads the shared host.
            """),
        "Tests/HelmAppTests/TheStatusItemHoldsUnderTheInputsTheFirstGuardSkippedTests.swift": (5, """
            `ModuleHost.shared.setEnabled` with Keep Awake's, the VPN's and Keyboard's descriptors, \
            and Keep Awake's off and on again: real engines, activated. The subject is what the \
            status item draws as a module goes off and comes back.
            """),
        "Tests/HelmAppTests/ShutdownLetsTheEnginesGoTests.swift": (1, """
            `bootstrap()` on a `host` bound to `ModuleHost.shared`: a real engine for every module \
            not switched off, activated. The host is the subject — that `shutdown()` frees what \
            `bootstrap()` built.
            """),
        "Tests/HelmAppTests/BootstrapDoesNotOrphanEnginesTests.swift": (2, """
            `bootstrap()` twice on a `host` bound to `ModuleHost.shared`: a real engine for every \
            module not switched off, activated. The host is the subject — the second call must \
            keep the engines the first one built.
            """),
        "Tests/HelmAppTests/TheHostPutsAModulesOwnItemInTheMenuBarTests.swift": (3, """
            `setEnabled`, on and off, on a `host` bound to `ModuleHost.shared`, with a descriptor \
            the file declares whose `makeEngine` returns a stub: no module's engine is built. The \
            host is the subject — that it attaches and detaches a module's menu-bar presence.
            """),
    ]

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
    ///
    /// Written once because four cases name it: three fixtures and the tree
    /// reading below, and a name that appears in a check four times is a rename
    /// away from three of them going quiet.
    static let constant = "DuplicatesSettings.guardOfScanSettings"

    /// The indirection is followed, or `settings:` would never be a subject at
    /// all: its default is `DuplicatesSettings.guardOfScanSettings`, and the word
    /// «Keychain» is one declaration further down.
    ///
    /// The owner is half of what is asserted, and deliberately: the member name
    /// alone is what this scan used to key by, and
    /// `testTwoStaticsSharingANameAreBothRead` is why it no longer does.
    func testAPortNamedThroughAConstantIsStillAPort() throws {
        let names = try Self.keychainNames()
        XCTAssertTrue(names.contains(Self.constant), """
            DuplicatesSettings.guardOfScanSettings is a SettingGuard over KeychainSealKey and the \
            scan did not recognise it, so every settings: default reads as harmless. It found \
            \(names.sorted().prefix(40)).
            """)
    }

    /// **Two declarations of one name, and the scan reads both.**
    ///
    /// The key was the bare member name, so these two overwrote each other and
    /// only the last one walked survived — `Reaching` is declared first here, so
    /// the harmless one buried it, `reaching` never grew through it, and a
    /// default naming it read as a plain value. The rule then passed over every
    /// call site it exists for, which is the one failure a guard must not have.
    ///
    /// `command grep -rn 'static let shared' Sources/` says how many names this
    /// tree already shares; the next keychain-reaching constant to take one would
    /// have taken the whole rule green with it.
    func testTwoStaticsSharingANameAreBothRead() {
        let source = SwiftSource.code("""
        public enum Reaching {
            public static let shared = SettingGuard(keys: KeychainSealKey(service: "s"))
        }
        public enum Harmless {
            public static let shared = SettingGuard(keys: InMemorySealKey())
        }
        """)
        XCTAssertEqual(Self.declarations(in: source).keys.sorted(),
                       ["Harmless.shared", "Reaching.shared"],
                       "one declaration overwrote the other, so the scan can see only one of them")
        XCTAssertEqual(Self.keychainNames(in: source), ["Reaching.shared"],
                       "either the buried declaration never reached the keychain, or the bare "
                       + "word «shared» carried its harmless namesake in with it")

        // And the half that goes quiet: the port behind the buried constant is
        // demanded of a call site again.
        let site = SwiftSource.code("""
        public final class Page {
            public init(settings: SettingGuard = Reaching.shared) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: site, reaching: Self.keychainNames(in: source)),
                       ["Page": ["settings"]])

        // A namesake that does not reach is not a port, or the fix would be a
        // rule that reports every call site and proves nothing.
        let harmless = SwiftSource.code("""
        public final class Page {
            public init(settings: SettingGuard = Harmless.shared) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: harmless, reaching: Self.keychainNames(in: source)), [:])
    }

    /// A bare `member`, written inside the type that declares it, is that
    /// declaration — and written anywhere else it is not.
    func testABareNameResolvesOnlyInsideItsOwnType() {
        let reaching: Set<String> = ["Reaching.shared"]
        let inside = SwiftSource.code("""
        public enum Reaching {
            public static let shared = SettingGuard(keys: KeychainSealKey(service: "s"))
            public init(settings: SettingGuard = shared) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: inside, reaching: reaching), ["Reaching": ["settings"]])

        let elsewhere = SwiftSource.code("""
        public enum Elsewhere {
            public static let shared = SettingGuard(keys: InMemorySealKey())
            public init(settings: SettingGuard = shared) {}
        }
        """)
        XCTAssertEqual(Self.ports(in: elsewhere, reaching: reaching), [:],
                       "a bare name matched across owners, so every «shared» in the tree is a "
                       + "keychain port")
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

    /// The property under `callSites`' own early return: **a source that never
    /// spells `Type(` holds no call of it.**
    ///
    /// The walk looks for exactly that substring and then asks what precedes
    /// it, so the guard is the same question asked before the source is copied
    /// into `[Character]` — it can save the copy, never an answer. Asserted
    /// rather than assumed, because it is what lets every scan in this suite
    /// skip a file unread: a guard that could say no to a source holding a call
    /// site would take offences out of all of them at once, with nothing on
    /// screen to say so.
    func testAFileThatNeverSpellsTheTypeHoldsNoConstructionOfIt() {
        let source = SwiftSource.code("""
        let a = SomethingElse(store: s, keys: k)
        // AutopilotEngine(store: s) — named in prose, and prose is blanked
        """)
        XCTAssertFalse(source.contains("AutopilotEngine("),
                       "the guard would have let this source through, so the case below "
                       + "proves nothing")
        XCTAssertEqual(SwiftSource.callSites(of: "AutopilotEngine", in: source).count, 0)
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
        XCTAssertEqual(Self.ports(in: source, reaching: [Self.constant]), [:])
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
        XCTAssertEqual(Self.ports(in: source, reaching: [Self.constant]),
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
        XCTAssertEqual(Self.ports(in: source, reaching: [Self.constant]),
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

    // MARK: - An engine the host builds

    /// **The host builds engines too, and the walk over `<Type>(` cannot be
    /// asked about them.** `AutopilotDescriptor.makeEngine(store:)` constructs
    /// `AutopilotEngine(store:sweepNotice:)` and leaves `keys:` and `sequence:`
    /// on their keychain defaults, and `ModuleHost.bootstrap()` runs that for
    /// every module a person has not switched off. A test that goes through
    /// either builds over the production keychain ports as surely as one that
    /// spells `AutopilotEngine(store: s)`, and no `<Type>(` in its text says
    /// so; what keeps such a run out of the login keychain is then
    /// `TestProcess.isRunning` inside those ports, and no double.
    ///
    /// The rows below read the tree's own files rather than a copy of them,
    /// because the scan asked is `PortsAtConstruction.hostBuilt(under:)` over
    /// `Tests`, the one the list above is applied to, and a directory entry
    /// point takes a directory of the repository: its walk resolves a path
    /// outside the repository to a different one, so a scratch tree cannot be
    /// handed to it. Each row names a file that builds engines by one spelling
    /// and asks whether that scan names the file.
    /// The subject is checked to occur first — the file is read and its code
    /// form holds the spelling — so a red here is the scan's blindness and not
    /// a fixture that never loaded. That `AutopilotEngine` is a keychain
    /// subject is checked beside it, and is no condition of what the scan
    /// answers: the last message leans on it where it says that
    /// `AutopilotDescriptor.makeEngine` leaves `keys:` and `sequence:` on the
    /// keychain.
    private func assertTheScanNames(_ files: [String], builtBy needle: String,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNotNil(try Self.subjects()["AutopilotEngine"],
                        "AutopilotEngine is no longer a keychain subject, so a host that builds it "
                        + "is no longer what these rows are about", file: file, line: line)
        let read = try SwiftSource.code(under: "Tests")
        for path in files {
            XCTAssertTrue(read.first { $0.path == path }?.text.contains(needle) == true,
                          "\(path) is not read by the scan, or no longer spells `\(needle)` in code",
                          file: file, line: line)
        }
        let named = Set(try Self.hostBuiltInTests().map(\.file))
        let unnamed = files.filter { !named.contains($0) }
        XCTAssertEqual(unnamed, [], """
            these files build engines through `\(needle)`, which takes every port on its \
            production default — AutopilotDescriptor.makeEngine leaves `keys:` and `sequence:` on \
            the keychain — and the scan for what the host builds does not name them. It names \
            \(named.count) file(s) under Tests.
            """, file: file, line: line)
    }

    /// One reading of `Tests/` for every row that asks what the host builds,
    /// computed once a process for the reason the memos under «Deriving the
    /// subjects» give.
    private static let hostBuiltOnce = Result { try PortsAtConstruction.hostBuilt(under: "Tests") }

    static func hostBuiltInTests() throws -> [PortsAtConstruction.HostBuilt] {
        try hostBuiltOnce.get()
    }

    /// Where the list and the scan part, as the two rows below report it:
    /// `grown` is a file the list does not name or one with more calls than its
    /// entry allows, `stale` an entry whose file has fewer.
    static func drift(found: [String: Int], listed: [String: Int])
    -> (grown: [String], stale: [String]) {
        var grown: [String] = []
        var stale: [String] = []
        for file in Set(found.keys).union(listed.keys).sorted() {
            let now = found[file] ?? 0
            guard let was = listed[file] else {
                grown.append("\(file): \(now) call(s), and no entry")
                continue
            }
            if now > was {
                grown.append("\(file): \(now) call(s) where its entry allows \(was)")
            } else if now == 0 {
                stale.append("\(file): no call left — delete the entry")
            } else if now < was {
                stale.append("\(file): \(now) call(s) where its entry says \(was) — lower it")
            }
        }
        return (grown, stale)
    }

    private static func driftOfTheTree() throws -> (grown: [String], stale: [String]) {
        drift(found: Dictionary(grouping: try hostBuiltInTests(), by: \.file).mapValues(\.count),
              listed: builtThroughTheHost.mapValues { $0.sites })
    }

    func testOnlyTheListedFilesHaveTheHostBuildAnEngine() throws {
        XCTAssertEqual(try Self.driftOfTheTree().grown, [], """
            these have a descriptor or the shared host build an engine, which names no port: the \
            engine gets whatever the app would give it, and through the host it is activated over \
            `UserDefaults.standard`. Build the engine by its type's name instead, with a double \
            at every port, the way that module's own tests do. Where the descriptor or the host \
            is itself what the test is about, the file goes into `builtThroughTheHost` with its \
            number of calls and that reason.
            """)
    }

    /// The list only shrinks: an entry the tree has moved under is a red that
    /// names the entry, so a file rewritten to build by name takes its line
    /// with it.
    func testNoEntryOfTheListOutlivesTheCallsItAllows() throws {
        XCTAssertEqual(try Self.driftOfTheTree().stale, [], """
            `builtThroughTheHost` allows more than the scan finds in these files now. Open the \
            file first: if its calls are still there, the scan has stopped reading them, and \
            `testNoReadingOfTheCalleeAloneSeparatesTheHostFromItsNamesakes` says whether it still \
            reads text. If they are gone, lower or delete each entry as said, so the call that \
            went cannot come back unseen.
            """)
    }

    /// **The floor.** While the list names a file, the row above fails on a scan
    /// that reads nothing, entry by entry. This is the same question with the
    /// list emptied: zero is then what a clean tree and a dead scan both print,
    /// so the floor goes by somebody deciding to delete it and never by itself.
    func testTheScanForWhatTheHostBuildsFindsSomething() throws {
        XCTAssertFalse(try Self.hostBuiltInTests().isEmpty, """
            no call under Tests/ has a descriptor or the shared host build an engine. Either \
            the scan has stopped reading — `testNoReadingOfTheCalleeAloneSeparatesTheHostFromItsNamesakes` \
            says whether it still reads text — or the last such file was rewritten, and this \
            floor is deleted with the last entry of `builtThroughTheHost`.
            """)
    }

    /// The comparison, on made-up input: every direction the tree is not in
    /// today, so each of the two rows is known to be able to fail.
    func testTheListIsHeldInBothDirections() {
        let drift = Self.drift(found: ["New.swift": 1, "Grown.swift": 3, "Same.swift": 2,
                                       "Fewer.swift": 1],
                               listed: ["Grown.swift": 2, "Same.swift": 2, "Fewer.swift": 4,
                                        "Gone.swift": 1])
        XCTAssertEqual(drift.grown, ["Grown.swift: 3 call(s) where its entry allows 2",
                                     "New.swift: 1 call(s), and no entry"])
        XCTAssertEqual(drift.stale, ["Fewer.swift: 1 call(s) where its entry says 4 — lower it",
                                     "Gone.swift: no call left — delete the entry"])
    }

    /// What the reading by receiver answers on spellings the table in
    /// `testNoReadingOfTheCalleeAloneSeparatesTheHostFromItsNamesakes` does not
    /// have: two more ways to a host, two calls it counts because it cannot
    /// tell, the argument label it must not take for a binding, and the two
    /// hosts it does not see.
    func testTheReceiverIsReadOnSpellingsTheTableDoesNotHave() {
        let rows: [(label: String, source: String, sites: Int)] = [
            ("a host taken as a parameter", "func drive(_ host: ModuleHost) { host.bootstrap() }", 1),
            ("a bound host reached through self",
             "private let host = ModuleHost.shared\nfunc f() { self.host.setEnabled(d, true) }", 1),
            ("a module switched off", "ModuleHost.shared.setEnabled(d, false)", 1),
            ("a helper called through self", "let e = self.makeEngine(store: s)", 1),
            ("an argument label beside an unrelated host",
             "let model = SettingsModel(host: ModuleHost.shared)\nlet host = Hoster()\nhost.bootstrap()", 0),
            ("the shared host in parentheses — not seen", "(ModuleHost.shared).bootstrap()", 0),
            ("an optional host — not seen", "var host: ModuleHost?\nhost?.bootstrap()", 0),
        ]
        for row in rows {
            XCTAssertEqual(PortsAtConstruction.hostBuilt(in: SwiftSource.code(row.source)).count,
                           row.sites, row.label)
        }
    }

    /// **The dot in front of `makeEngine` is the whole of what tells a descriptor's
    /// call from a test's own helper**, so one source holds all three: the
    /// helper's declaration, a bare call of it, and a call on a descriptor. Only
    /// the last is the host's, and it is on line 3.
    func testADotInFrontOfMakeEngineIsWhatSeparatesADescriptorFromAHelper() {
        let source = """
            func makeEngine() -> KeepAwakeEngine { KeepAwakeEngine() }
            let helper = makeEngine()
            let built = descriptor.makeEngine(store: store)
            """
        let found = PortsAtConstruction.hostBuilt(in: SwiftSource.code(source))
        XCTAssertEqual(found.map(\.line), [3], "the declaration or the bare call was counted, or the dotted one was not")
        XCTAssertEqual(found.map(\.callee), ["makeEngine"])
    }

    /// A callee at the first character of a source has nothing in front of it
    /// to read, and asking for the character before it is an index below zero.
    func testACalleeAtTheFirstCharacterIsNotReadFromBeforeTheSource() {
        let found = PortsAtConstruction.hostBuilt(
            in: SwiftSource.code("bootstrap()\nModuleHost.shared.bootstrap()"))
        XCTAssertEqual(found.map(\.line), [2])
    }

    /// Swift lets a chain break in front of every dot, and a comment may stand
    /// on a line of its own between two of them.
    func testAChainBrokenInFrontOfEveryDotStillEndsAtTheSharedHost() {
        let rows: [(label: String, source: String)] = [
            ("every dot on a line of its own", "ModuleHost\n    .shared\n    .setEnabled(d, true)"),
            ("a comment between the lines", "ModuleHost.shared\n    // why\n    .bootstrap()"),
        ]
        for row in rows {
            XCTAssertEqual(PortsAtConstruction.hostBuilt(in: SwiftSource.code(row.source)).count, 1,
                           row.label)
        }
    }

    /// `check` asks the same reading as the whole-tree pair does, and it asks it
    /// of the directory it was given. The row leans on the tree for both halves:
    /// it needs a directory with files that have the host build, and takes
    /// `Tests/HelmAppTests` for as long as `builtThroughTheHost` names files
    /// there; and one with none, `Tests/Modules/Leftovers`. When the last listed
    /// file under `Tests/HelmAppTests` is rewritten, this row goes red for want
    /// of the failure it expects: point it at a directory the list still names,
    /// or delete it with the floor. The engine named here is built nowhere, so
    /// the host's clause is the only one that can speak, and the failure is
    /// expected by its text — any other failure still fails the row.
    func testCheckReportsWhatTheHostBuildsUnderTheDirectoryItIsGiven() throws {
        var options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("have a descriptor or the host build the engine") }
        try XCTExpectFailure("Tests/HelmAppTests holds files that have the host build an engine — "
                             + "if none is recorded, `check` has stopped reporting them or "
                             + "no file `builtThroughTheHost` lists is left there",
                             options: options) {
            try PortsAtConstruction.check("NoEngineIsBuiltUnderThisName", under: "Tests/HelmAppTests",
                                          naming: ["store"], atLeast: 0)
        }
        try PortsAtConstruction.check("NoEngineIsBuiltUnderThisName", under: "Tests/Modules/Leftovers",
                                      naming: ["store"], atLeast: 0)
    }

    /// Spellings the receiver is read through that no other row has: a tab or a
    /// carriage return in front of the dot, a bound name typed as the host and
    /// given `.shared`, a `try` in front, a closure around the call.
    func testTheReceiverIsReadThroughWhiteSpaceAnAnnotationAndAClosure() {
        let rows: [(label: String, source: String)] = [
            ("a tab in front of the dot", "ModuleHost.shared\n\t.bootstrap()"),
            ("a carriage return in front of the dot", "ModuleHost.shared\r\n    .bootstrap()"),
            ("a name typed as the host and given .shared", "let host: ModuleHost = .shared\nhost.bootstrap()"),
            ("a try in front", "try ModuleHost.shared.bootstrap()"),
            ("a closure around the call", "DispatchQueue.main.async { ModuleHost.shared.bootstrap() }"),
        ]
        for row in rows {
            XCTAssertEqual(PortsAtConstruction.hostBuilt(in: SwiftSource.code(row.source)).count, 1,
                           row.label)
        }
    }

    /// Three more ways a host arrives that the reading does not follow, pinned
    /// as it stands so that widening it is a decision: a name bound to another
    /// name that is bound to the host, the type written with its module, and the
    /// function taken without being called.
    func testAHostThatArrivesByAnotherRouteIsNotSeen() {
        let rows: [(label: String, source: String)] = [
            ("a name bound to a bound name", "let host = ModuleHost.shared\nlet other = host\nother.bootstrap()"),
            ("the type written with its module", "HelmApp.ModuleHost.shared.bootstrap()"),
            ("the function taken without a call", "let build = ModuleHost.shared.bootstrap\nbuild()"),
        ]
        for row in rows {
            XCTAssertEqual(PortsAtConstruction.hostBuilt(in: SwiftSource.code(row.source)).count, 0,
                           row.label)
        }
    }

    /// `descriptor.makeEngine(store: store)` in a helper that holds one descriptor.
    func testAnEngineBuiltByADescriptorsMakeEngineIsAskedAboutItsPorts() throws {
        try assertTheScanNames(["Tests/HelmAppTests/ModulePageRender.swift"],
                               builtBy: "descriptor.makeEngine(store: store)")
    }

    /// The same call inside a `map` over `ModuleRegistry.all`, with its argument
    /// spilling onto the next line.
    func testEveryEngineBuiltByAMapOverTheRegistryIsAskedAboutItsPorts() throws {
        try assertTheScanNames(["Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift"],
                               builtBy: "descriptor.makeEngine(store: NamespacedStore(")
    }

    /// `ModuleHost.shared.bootstrap()`, which enables every module on its first launch.
    func testTheSharedHostsBootstrapIsAskedAboutThePortsOfWhatItBuilds() throws {
        try assertTheScanNames(["Tests/HelmAppTests/DisclosureProbe.swift"],
                               builtBy: "ModuleHost.shared.bootstrap()")
    }

    /// `let host = ModuleHost.shared` and then `host.bootstrap()` — the name
    /// `ModuleHost.shared` is not on the line that builds.
    func testABootstrapThroughAnAliasOfTheSharedHostIsAskedAboutThePorts() throws {
        try assertTheScanNames(["Tests/HelmAppTests/ShutdownLetsTheEnginesGoTests.swift",
                                "Tests/HelmAppTests/BootstrapDoesNotOrphanEnginesTests.swift"],
                               builtBy: "host.bootstrap()")
    }

    /// **Why the walk over `<Type>(` does not count them: it skips a call with
    /// a dot in front of it.** `callSites` rejects a longer name ending in the
    /// callee, and a dot counts as a name character, so `descriptor.makeEngine(`
    /// and `ModuleHost.shared.setEnabled(` are not seen at all by the reading
    /// every construction goes through — only `wholeWords: false` sees them,
    /// and that reading sees their namesakes as well.
    ///
    /// Each row is a source, the callee a scan would look for, and how many
    /// sites each reading finds. The host rows are the spellings this tree has
    /// and one it does not, a chain broken across lines; the namesake rows are
    /// the ones a scan must not count and cannot tell from them by the callee's
    /// name alone — which is what this pins: the receiver is what separates
    /// them, and a spelling in a comment or a string is blanked before any
    /// reading sees it. The last assertion puts every row to
    /// `PortsAtConstruction.hostBuilt(in:)`, the reading that does go by the
    /// receiver: one site in each host row, none in a namesake.
    func testNoReadingOfTheCalleeAloneSeparatesTheHostFromItsNamesakes() {
        struct Row {
            let label: String
            let source: String
            let callee: String
            let hostBuilt: Bool
        }
        let rows = [
            Row(label: "a descriptor variable", source: "let e = descriptor.makeEngine(store: s)",
                callee: "makeEngine", hostBuilt: true),
            Row(label: "a descriptor built on the spot",
                source: "let e = KeepAwakeDescriptor().makeEngine(store: s)",
                callee: "makeEngine", hostBuilt: true),
            Row(label: "the shared host enabling a module",
                source: "ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)",
                callee: "setEnabled", hostBuilt: true),
            Row(label: "the shared host bootstrapping", source: "ModuleHost.shared.bootstrap()",
                callee: "bootstrap", hostBuilt: true),
            Row(label: "an alias of the shared host, bootstrapping",
                source: "let host = ModuleHost.shared\nhost.bootstrap()",
                callee: "bootstrap", hostBuilt: true),
            Row(label: "an alias of the shared host, enabling a module",
                source: "let host = ModuleHost.shared\nhost.setEnabled(descriptor, true)",
                callee: "setEnabled", hostBuilt: true),
            Row(label: "a chain broken across lines",
                source: "ModuleHost.shared\n    .setEnabled(KeepAwakeDescriptor(), true)",
                callee: "setEnabled", hostBuilt: true),
            Row(label: "the log's own switch", source: "HelmLog.shared.setEnabled(true)",
                callee: "setEnabled", hostBuilt: false),
            Row(label: "the hosts file's switch",
                source: "_ = HostsFile.setEnabled(false, at: 1, in: &doc)",
                callee: "setEnabled", hostBuilt: false),
            Row(label: "a view model's switch", source: "model.setEnabled(false, folder: f)",
                callee: "setEnabled", hostBuilt: false),
            Row(label: "a test's own helper, declared and called",
                source: "private func makeEngine() -> KeepAwakeEngine { KeepAwakeEngine() }\nlet e = makeEngine()",
                callee: "makeEngine", hostBuilt: false),
            Row(label: "a stub descriptor's declaration",
                source: "func makeEngine(store: NamespacedStore) -> any ModuleEngine { Stub() }",
                callee: "makeEngine", hostBuilt: false),
            Row(label: "a host-looking name bound to something else",
                source: "let host = Hoster()\nhost.bootstrap()",
                callee: "bootstrap", hostBuilt: false),
            Row(label: "the spelling in a comment",
                source: "// ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)\n"
                    + "/* descriptor.makeEngine(store: s) */",
                callee: "setEnabled", hostBuilt: false),
            Row(label: "the spelling in a string",
                source: #"let s = "ModuleHost.shared.bootstrap()""#,
                callee: "bootstrap", hostBuilt: false),
            Row(label: "the spelling in a multi-line string",
                source: "let s = \"\"\"\nModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)\n\"\"\"",
                callee: "setEnabled", hostBuilt: false),
        ]
        // What the reading that ignores the receiver finds in each row: one
        // site, except the helper (its declaration and its call) and the three
        // rows in prose, which blanking empties.
        let blind = ["a test's own helper, declared and called": 2,
                     "the spelling in a comment": 0,
                     "the spelling in a string": 0,
                     "the spelling in a multi-line string": 0]
        for row in rows {
            let code = SwiftSource.code(row.source)
            XCTAssertEqual(
                SwiftSource.callSites(of: row.callee, in: code, wholeWords: false).count,
                blind[row.label] ?? 1,
                "\(row.label): the receiver-blind reading found a different number of sites")
            if row.hostBuilt {
                XCTAssertEqual(
                    SwiftSource.callSites(of: row.callee, in: code).count, 0,
                    "\(row.label): the reading every construction goes through saw a call with a "
                    + "receiver in front of it — the host spellings are not skipped by it any more")
            }
            XCTAssertEqual(
                PortsAtConstruction.hostBuilt(in: code).count, row.hostBuilt ? 1 : 0,
                "\(row.label): the reading by receiver "
                + (row.hostBuilt ? "missed an engine the host builds" : "counted a namesake"))
        }
    }

    // MARK: - Deriving the subjects

    /// **Every derivation below is computed once a process, and the reason is
    /// XCTest's own shape.** It builds a fresh instance per test case, so an
    /// instance's worth of scanning is paid by every case that asks for one —
    /// `command grep -c '^    func test'` over this file says how many cases
    /// there are, and every one that reaches `subjects()`, `keychainNames()`,
    /// `scanOfTests()` or `hostBuiltInTests()` starts a whole-tree derivation.
    /// Before these memos it walked and parsed `Sources/` five times over and
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

    /// Every static declaration in `source`, by `Owner.member` — the seam the
    /// fixtures read, so what they exercise is what the tree goes through.
    static func declarations(in source: String) -> [String: String] {
        var bodies: [String: String] = [:]
        merge(&bodies, from: source)
        return bodies
    }

    /// `keychainNames()` over one source rather than over `Sources/`.
    static func keychainNames(in source: String) -> Set<String> {
        closure(of: declarations(in: source))
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
    /// over the call sites it exists for with nothing on screen to say so
    /// (`testTwoStaticsSharingANameAreBothRead`). `SwiftSource.innermost` over
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

    /// The same reading, of one file's text — which is what makes the fixtures
    /// above go through exactly what the tree goes through.
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

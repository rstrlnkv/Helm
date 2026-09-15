import Foundation
import XCTest
import HelmContract
@testable import Module_Homebrew_Engine

/// **The reading that drew the button is older than the press.**
///
/// `DoctorFixCandidate.judging(_:installed:)` runs on the page's side, against
/// the installed list the page was holding when `brew doctor` answered. That
/// answer is minutes old by the time somebody has read the issue, and a day old
/// if the window was left open — and in between, `periphery` is uninstalled in
/// a terminal, or by Helm's own Installed tab two segments away. The argv the
/// page still carries then names a package that is not on this Mac.
///
/// So the argv arriving over the wire is a *candidate*, never a verdict:
/// `HomebrewEngine.runDoctorFix` reads the installed list at the press and puts
/// it through `DoctorFix.judge` again. The UI's judgement decides what to draw;
/// this one decides what to run.
///
/// **Every absence here is asserted beside a presence.** A test that only
/// checks "no child launched" passes for every wrong reason there is — a fake
/// with no brew path, a gate left shut by the previous case, a typo in the
/// command name — so each refusal below is measured against a run of the *same
/// engine with the same fake* that did launch. The one that matters most,
/// `testTheSamePressRunsAndThenRefusesWhenTheNameLeavesTheCellar`, is one
/// engine pressed twice with nothing changed but the Cellar.
final class AFixIsJudgedAgainstTheCellarAtThePressTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// A brew whose Cellar can change between two calls, because that is the
    /// whole subject: `installed` is read on every `brew list --versions` run,
    /// so a test can uninstall something the way a terminal does.
    ///
    /// The child never exits on its own — `HangingRunner`'s reason in
    /// `OneOperationAtATimeTests`: a fake that calls `onExit` synchronously
    /// releases the busy gate before the call it gates has returned, and a test
    /// built on one passes with the gate deleted. `finishAll` is how an
    /// operation ends here.
    private final class MovingCellar: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _installed: [String]
        private var _launched: [[String]] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        /// Set to nil to make `brew list` refuse — a non-zero exit with nothing
        /// on stdout, which is what a brew holding somebody else's lock does.
        var installed: [String]? {
            get { lock.lock(); defer { lock.unlock() }; return _refuses ? nil : _installed }
            set {
                lock.lock()
                _refuses = newValue == nil
                _installed = newValue ?? []
                lock.unlock()
            }
        }
        private var _refuses = false

        var launched: [[String]] { lock.lock(); defer { lock.unlock() }; return _launched }

        init(installed: [String]) { self._installed = installed }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            lock.lock()
            let refuses = _refuses
            let names = _installed
            lock.unlock()
            guard args.first == "list" else { return (0, "") }
            if refuses { return (1, "") }
            // `brew list --versions` prints "<name> <version>"; the formula
            // half answers with everything and the cask half with nothing, so
            // the engine's two children both come back.
            guard args.contains("--formula") else { return (0, "") }
            return (0, names.map { "\($0) 1.0.0" }.joined(separator: "\n") + "\n")
        }

        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) {
            (0, "")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _launched.append(args); _exits.append(onExit); lock.unlock()
            return NoProcess()
        }

        func finishAll(code: Int32 = 0) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    /// Every port named at construction, the marker included: a defaulted one
    /// would be this Mac's own (`CLAUDE.md`).
    private func engine(_ runner: ProcessRunner,
                        _ transport: LocalTransport = LocalTransport()) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       transport: transport, marker: InMemoryOpMarker())
    }

    /// Everything the engine put on the transport, read back through the replay
    /// — the shape `AVanishedBrewIsNotASilentPressTests` uses, and for the same
    /// reason: with the fakes synchronous, whatever was emitted is already there.
    private func states(_ transport: LocalTransport) async -> [OpState] {
        transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
        var found: [OpState] = []
        for await event in transport.events {
            if event.name == "test.sentinel" { break }
            guard event.name == HomebrewEvent.opState.rawValue,
                  let state = try? JSONDecoder().decode(OpState.self, from: event.payload)
            else { continue }
            found.append(state)
        }
        return found
    }

    // MARK: - The race this design exists for

    /// **One engine, one argv, two presses, and nothing between them but the
    /// Cellar.**
    ///
    /// The first press is the control and it is not decoration: without it, the
    /// second half of this test would pass against an engine that refuses every
    /// fix, against one that cannot find brew, and against one whose command
    /// name is misspelled. With it, the only difference between a run and a
    /// refusal is the list `brew list` answered a line before the act.
    func testTheSamePressRunsAndThenRefusesWhenTheNameLeavesTheCellar() async {
        let runner = MovingCellar(installed: ["periphery", "wget"])
        let transport = LocalTransport()
        let engine = engine(runner, transport)
        let argv = ["uninstall", "periphery"]

        engine.runDoctorFix(argv)
        XCTAssertEqual(runner.launched, [["uninstall", "--", "periphery"]], """
            precondition: with `periphery` installed the very same argv must run, or the \
            refusal below proves nothing about the Cellar and everything about the fixture
            """)
        runner.finishAll()

        // A terminal beside this window, or Helm's own Installed tab.
        runner.installed = ["wget"]
        engine.runDoctorFix(argv)

        XCTAssertEqual(runner.launched.count, 1, """
            the page's own judgement was taken as the verdict: `brew uninstall periphery` was \
            run against a Cellar that no longer has periphery in it, because the argv had been \
            judged when the issue was drawn rather than when the button was pressed — \
            \(runner.launched)
            """)
        let refusals = await states(transport).filter { $0.reason == .fixRefused }
        XCTAssertEqual(refusals.count, 1, """
            the run was refused and nothing was said about it: a press that answers with no \
            state at all is a button that visibly does nothing forever
            """)
    }

    // MARK: - The other ways an argv fails the judge

    /// A Cellar nobody could read is not a Cellar the name is in. `listInstalled`
    /// answers nil for a refused `brew list`, and folding that to an empty list
    /// would refuse `uninstall` by luck while admitting `cleanup` by mistake.
    func testACellarThatCouldNotBeReadRefusesTheRun() async {
        let runner = MovingCellar(installed: ["periphery"])
        let transport = LocalTransport()
        let engine = engine(runner, transport)

        engine.runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.launched.count, 1, "precondition: a readable Cellar ran it")
        runner.finishAll()

        runner.installed = nil          // `brew list` exits 1 with nothing to say
        engine.runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.launched.count, 1, """
            `brew list` refused and the engine ran the uninstall anyway — a refusal was read as \
            an answer about the machine: \(runner.launched)
            """)
        let refusals = await states(transport).filter { $0.reason == .fixRefused }
        XCTAssertEqual(refusals.count, 1, "the refusal was silent")
    }

    /// **The half an `uninstall` cannot see.** Folding an unreadable Cellar to
    /// an empty list refuses `uninstall` by luck — the name is not in an empty
    /// list either — and admits `cleanup`, which takes no name and so is
    /// admitted by every list there is. So the rule has to be read with the one
    /// command whose verdict does not depend on what the list holds.
    func testACellarThatCouldNotBeReadRefusesEvenACommandWithNoOperand() {
        let runner = MovingCellar(installed: [])
        let engine = engine(runner)

        engine.runDoctorFix(["cleanup"])
        XCTAssertEqual(runner.launched, [["cleanup"]], """
            precondition: against a Cellar that answered \u{2014} empty, but answered \u{2014} \
            `cleanup` runs, so the refusal below is about the reading and not about the command
            """)
        runner.finishAll()

        runner.installed = nil          // `brew list` exits 1 with nothing to say
        engine.runDoctorFix(["cleanup"])
        XCTAssertEqual(runner.launched.count, 1, """
            a `brew list` that refused was folded to an empty list, and `cleanup` \u{2014} which \
            no list can refuse \u{2014} ran against a Cellar nothing managed to read: \
            \(runner.launched)
            """)
    }

    /// **Nothing on this wire is trusted to have been judged.** No page draws a
    /// button for `untap`, for an `uninstall` carrying two names, or for one
    /// carrying a flag — but the transport is not a private channel, and the
    /// engine is the gate rather than the page.
    func testAnArgvNoPageEverDrewIsRefused() {
        let never = [
            ["untap", "sozercan/homebrew-repo"],   // off `DoctorFix.Allowed` entirely
            ["update-reset"],                      // the other deliberate absence
            ["uninstall", "periphery", "wget"],    // two names is two acts
            ["uninstall", "--force"],              // a flag, not a name
            ["uninstall", "peri phery"],           // not spellable
            ["brew", "uninstall", "periphery"],    // not parsed: `brew` is not argv[0]
            ["cleanup", "--prune=all"],            // a different act from `cleanup`
        ]
        for argv in never {
            let runner = MovingCellar(installed: ["periphery", "wget"])
            let engine = engine(runner)
            engine.runDoctorFix(argv)
            XCTAssertEqual(runner.launched, [],
                           "\(argv) reached a child: \(runner.launched)")
        }
        // The control for the whole sweep: the same fixture, the one argv the
        // judge does admit. Without this, deleting `runDoctorFix`'s body would
        // leave every case above green.
        let runner = MovingCellar(installed: ["periphery", "wget"])
        engine(runner).runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.launched, [["uninstall", "--", "periphery"]],
                       "the fixture refuses everything, so the refusals above prove nothing")
    }

    /// `cleanup` takes no operand, so it gets no `--`. Every *value* goes behind
    /// one — that is the engine's own first sentence — and a `--` with nothing
    /// after it is not a value.
    func testCleanupRunsWithNoSeparatorBecauseItHasNoOperand() {
        let runner = MovingCellar(installed: [])
        engine(runner).runDoctorFix(["cleanup"])
        XCTAssertEqual(runner.launched, [["cleanup"]],
                       "a command with no operand was given a separator: \(runner.launched)")
    }

    /// The operand goes behind `--` because it is a word parsed out of brew's
    /// own prose, and `brew` reads a leading `-` as a flag wherever it finds one.
    func testTheOperandGoesBehindTheSeparator() {
        let runner = MovingCellar(installed: ["periphery"])
        engine(runner).runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.launched.first, ["uninstall", "--", "periphery"],
                       "the name was passed where brew can read it as a flag")
    }
}

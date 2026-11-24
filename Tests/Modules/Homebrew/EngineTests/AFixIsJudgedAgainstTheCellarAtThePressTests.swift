import Foundation
import XCTest
import HelmContract
@testable import Module_Homebrew_Engine

/// **The reading that drew the button is older than the press.**
///
/// `DoctorFixCandidate.judging(_:installed:)` runs on the page's side against
/// the installed list held when `brew doctor` answered, which may be a day old
/// by the press; meanwhile `periphery` may have been uninstalled in a terminal
/// or on the Installed tab. So the argv through the door is a *candidate*:
/// `HomebrewEngine.runDoctorFix` reads the installed list at the press and
/// judges again. The page's judgement decides what to draw; this one, what runs.
///
/// **Every absence here is asserted beside a presence**: each refusal is
/// measured against a run of the same engine with the same fake that did
/// launch, so a missing brew path or a gate left shut cannot pass for it.
final class AFixIsJudgedAgainstTheCellarAtThePressTests: XCTestCase {

    /// What `brew list --versions` answers for a Cellar holding `installed`. A
    /// test changes the Cellar between two calls by setting `answers` again.
    ///
    /// The runner holds its children (`streams: .hold`): a fake that calls
    /// `onExit` synchronously releases the busy gate before the gated call
    /// returns, and a test on it passes with the gate deleted.
    private func cellar(_ installed: [String]) -> [BrewAnswer] {
        // `brew list --versions` prints "<name> <version>"; the formula half answers
        // with everything and the cask half with nothing, so the engine's two
        // children both come back.
        [BrewAnswer(["list", "--formula"], 0, installed.map { "\($0) 1.0.0" }.joined(separator: "\n") + "\n")]
    }

    /// `brew list` exits 1 with nothing to say, which is what a brew holding
    /// somebody else's lock does.
    private let refusingList = [BrewAnswer(["list"], 1, "")]

    /// Every port named at construction, the marker included: a defaulted one
    /// would be this Mac's own (Architecture/TestsAndMeasurement.md § Fakes).
    /// What the engine put on the news is read back through the replay.
    private func states(_ news: EngineNews<HomebrewNews>) async -> [OpState] { await replay(news).states }

    // MARK: - The race this design exists for

    /// **One engine, one argv, two presses, and nothing between them but the
    /// Cellar.**
    ///
    /// The first press is the control: without it the second half would pass
    /// against an engine that refuses every fix or cannot find brew. With it,
    /// the only difference between a run and a refusal is the list `brew list`
    /// answered a line before the act.
    func testTheSamePressRunsAndThenRefusesWhenTheNameLeavesTheCellar() async {
        let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery", "wget"]))
        let news = EngineNews<HomebrewNews>()
        let engine = brewEngine(runner, news: news)
        let argv = ["uninstall", "periphery"]

        engine.runDoctorFix(argv)
        XCTAssertEqual(runner.streamed, [["uninstall", "--", "periphery"]], """
            precondition: with `periphery` installed the very same argv must run, or the \
            refusal below proves nothing about the Cellar and everything about the fixture
            """)
        runner.finishAll()

        // A terminal beside this window, or Helm's own Installed tab.
        runner.answers = cellar(["wget"])
        engine.runDoctorFix(argv)

        XCTAssertEqual(runner.streamed.count, 1, """
            the page's own judgement was taken as the verdict: `brew uninstall periphery` was \
            run against a Cellar that no longer has periphery in it, because the argv had been \
            judged when the issue was drawn rather than when the button was pressed — \
            \(runner.streamed)
            """)
        let refusals = await states(news).filter { $0.reason == .fixRefused }
        XCTAssertEqual(refusals.count, 1, """
            the run was refused and nothing was said about it: a press that answers with no \
            state at all is a button that visibly does nothing forever
            """)
    }

    // MARK: - The other ways an argv fails the judge

    /// A Cellar nobody could read is not a Cellar the name is in. `listInstalled`
    /// answers nil for a refused `brew list`, and folding that to an empty list
    /// would refuse `uninstall` by luck rather than by reading.
    func testACellarThatCouldNotBeReadRefusesTheRun() async {
        let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery"]))
        let news = EngineNews<HomebrewNews>()
        let engine = brewEngine(runner, news: news)

        engine.runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.streamed.count, 1, "precondition: a readable Cellar ran it")
        runner.finishAll()

        runner.answers = refusingList          // `brew list` exits 1 with nothing to say
        engine.runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.streamed.count, 1, """
            `brew list` refused and the engine ran the uninstall anyway — a refusal was read as \
            an answer about the machine: \(runner.streamed)
            """)
        let refusals = await states(news).filter { $0.reason == .fixRefused }
        XCTAssertEqual(refusals.count, 1, "the refusal was silent")
    }

    /// **Nothing through this door is trusted to have been judged.** No page draws
    /// a button for `untap`, two names or a flag, but `perform(_:)` is public, and
    /// the engine is the gate.
    func testAnArgvNoPageEverDrewIsRefused() {
        let never = [
            ["untap", "sozercan/homebrew-repo"],   // off `DoctorFix.Allowed` entirely
            ["update-reset"],                      // the other deliberate absence
            ["uninstall", "periphery", "wget"],    // two names is two acts
            ["uninstall", "--force"],              // a flag, not a name
            ["uninstall", "peri phery"],           // not spellable
            ["brew", "uninstall", "periphery"],    // not parsed: `brew` is not argv[0]
            ["cleanup"],                           // off the list: no page offers it
            ["cleanup", "--prune=all"],            // not on the list either
        ]
        for argv in never {
            let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery", "wget"]))
            let engine = brewEngine(runner)
            engine.runDoctorFix(argv)
            XCTAssertEqual(runner.streamed, [],
                           "\(argv) reached a child: \(runner.streamed)")
        }
        // The control for the whole sweep: the one argv the judge admits.
        let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery", "wget"]))
        brewEngine(runner).runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.streamed, [["uninstall", "--", "periphery"]],
                       "the fixture refuses everything, so the refusals above prove nothing")
    }

    /// The operand goes behind `--` because it is a word parsed out of brew's
    /// own prose, and `brew` reads a leading `-` as a flag wherever it finds one.
    func testTheOperandGoesBehindTheSeparator() {
        let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery"]))
        brewEngine(runner).runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.streamed.first, ["uninstall", "--", "periphery"],
                       "the name was passed where brew can read it as a flag")
    }
}

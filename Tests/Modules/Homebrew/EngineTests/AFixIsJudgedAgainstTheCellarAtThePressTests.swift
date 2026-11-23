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
/// So the argv arriving through the door is a *candidate*, never a verdict:
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

    /// What `brew list --versions` answers for a Cellar holding `installed`. The Cellar
    /// can change between two calls, because that is the whole subject: the runner's
    /// `answers` are read on every run, so a test can uninstall something the way a
    /// terminal does by setting them again.
    ///
    /// The runner holds its children (`streams: .hold`): a fake that calls `onExit`
    /// synchronously releases the busy gate before the call it gates has returned, and
    /// a test built on one passes with the gate deleted. `finishAll` is how an
    /// operation ends here.
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
    /// would be this Mac's own (ARCHITECTURE.md § Fakes).
    /// Everything the engine put on the news, read back through the replay:
    /// with the fakes synchronous, whatever was emitted is already there.
    private func states(_ news: EngineNews<HomebrewNews>) async -> [OpState] { await replay(news).states }

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
    /// would refuse `uninstall` by luck while admitting `cleanup` by mistake.
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

    /// **The half an `uninstall` cannot see.** Folding an unreadable Cellar to
    /// an empty list refuses `uninstall` by luck — the name is not in an empty
    /// list either — and admits `cleanup`, which takes no name and so is
    /// admitted by every list there is. So the rule has to be read with the one
    /// command whose verdict does not depend on what the list holds.
    func testACellarThatCouldNotBeReadRefusesEvenACommandWithNoOperand() {
        let runner = ScriptedRunner(streams: .hold, answers: cellar([]))
        let engine = brewEngine(runner)

        engine.runDoctorFix(["cleanup"])
        XCTAssertEqual(runner.streamed, [["cleanup"]], """
            precondition: against a Cellar that answered \u{2014} empty, but answered \u{2014} \
            `cleanup` runs, so the refusal below is about the reading and not about the command
            """)
        runner.finishAll()

        runner.answers = refusingList          // `brew list` exits 1 with nothing to say
        engine.runDoctorFix(["cleanup"])
        XCTAssertEqual(runner.streamed.count, 1, """
            a `brew list` that refused was folded to an empty list, and `cleanup` \u{2014} which \
            no list can refuse \u{2014} ran against a Cellar nothing managed to read: \
            \(runner.streamed)
            """)
    }

    /// **Nothing through this door is trusted to have been judged.** No page draws a
    /// button for `untap`, for an `uninstall` carrying two names, or for one
    /// carrying a flag — but `perform(_:)` is public, and the engine is the gate
    /// rather than the page.
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
            let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery", "wget"]))
            let engine = brewEngine(runner)
            engine.runDoctorFix(argv)
            XCTAssertEqual(runner.streamed, [],
                           "\(argv) reached a child: \(runner.streamed)")
        }
        // The control for the whole sweep: the same fixture, the one argv the
        // judge does admit. Without this, deleting `runDoctorFix`'s body would
        // leave every case above green.
        let runner = ScriptedRunner(streams: .hold, answers: cellar(["periphery", "wget"]))
        brewEngine(runner).runDoctorFix(["uninstall", "periphery"])
        XCTAssertEqual(runner.streamed, [["uninstall", "--", "periphery"]],
                       "the fixture refuses everything, so the refusals above prove nothing")
    }

    /// `cleanup` takes no operand, so it gets no `--`. Every *value* goes behind
    /// one — that is the engine's own first sentence — and a `--` with nothing
    /// after it is not a value.
    func testCleanupRunsWithNoSeparatorBecauseItHasNoOperand() {
        let runner = ScriptedRunner(streams: .hold, answers: cellar([]))
        brewEngine(runner).runDoctorFix(["cleanup"])
        XCTAssertEqual(runner.streamed, [["cleanup"]],
                       "a command with no operand was given a separator: \(runner.streamed)")
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

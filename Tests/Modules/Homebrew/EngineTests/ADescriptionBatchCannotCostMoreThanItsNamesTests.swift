// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **A description batch refused wholesale costs no more `brew` runs than it
/// has names, plus one.**
///
/// `describe` asks `brew desc` for a whole batch and, on a non-zero exit, halves
/// it and asks again: one bad name in fifty costs about a dozen calls instead of
/// fifty. When brew refuses **every** call, an unbounded bisection runs to a leaf
/// per name, `2n-1` launches, each a real subprocess taking one of the app's
/// eight `HelmProcess` slots; the page asks over the whole installed list on
/// every load, so 54 packages would be 107 `brew` runs.
///
/// Every name is refused at once whenever the refusal is about the tool rather
/// than a name: a tap that is gone (`brew untap homebrew/cask` leaves every cask
/// installed and listed), a Ruby error, mismatched Command Line Tools.
///
/// **The bound is structural.** One optimistic batch, then at most one call per
/// name, `n + 1`, is the most any strategy can justify. The bisection stays under
/// it for one bad name (the control below) and would exceed it exactly when the
/// refusal is about the tool.
final class ADescriptionBatchCannotCostMoreThanItsNamesTests: XCTestCase {

    /// A brew that resolves the names in `known` and refuses any call carrying
    /// a name it does not know, validating the whole call before printing
    /// anything, as `brew desc` does (exit 1, message on stderr, stdout empty).
    /// With `known` empty it refuses everything, the state under test.
    private func partlyKnowingBrew(known: Set<String>) -> ScriptedRunner {
        ScriptedRunner(reply: { args in
            guard args.first == "desc" else { return nil }
            guard let terminator = args.firstIndex(of: "--") else { return (1, "") }
            let names = Array(args[args.index(after: terminator)...])
            guard names.allSatisfy(known.contains) else { return (1, "") }
            return (0, names.map { "\($0): description of \($0)" }.joined(separator: "\n") + "\n")
        })
    }

    /// The `brew desc` calls the runner saw.
    private func descCalls(_ runner: ScriptedRunner) -> [[String]] {
        runner.queries.filter { $0.first == "desc" }
    }

    private func names(_ count: Int) -> [String] {
        (0..<count).map { "pkg-\($0)" }
    }

    /// The whole batch refused: the bisection walks to a leaf per name and pays
    /// for every interior node on the way.
    func testABatchRefusedWholesaleCostsNoMoreCallsThanNames() {
        let wanted = names(32)
        let runner = partlyKnowingBrew(known: [])

        _ = brewEngine(runner).descriptions(names: wanted, isCask: true)

        XCTAssertLessThanOrEqual(descCalls(runner).count, wanted.count + 1, """
            \(wanted.count) names cost \(descCalls(runner).count) `brew desc` launches — more \
            than one batch plus a call per name, which is the worst case the split \
            exists to beat. Each one takes a slot out of the eight the whole app has.
            """)
    }

    /// The control: one bad name in thirty-two still costs eleven calls, the
    /// "about a dozen instead of fifty" `describe`'s doc comment promises. The
    /// bound above is not "never split".
    func testOneUnresolvableNameStillCostsAboutADozenCalls() {
        let wanted = names(32)
        let runner = partlyKnowingBrew(known: Set(wanted.dropLast()))

        let found = brewEngine(runner).descriptions(names: wanted, isCask: false)

        XCTAssertEqual(found.count, 31, "the good names lost their descriptions to the bad one")
        XCTAssertLessThanOrEqual(descCalls(runner).count, 12,
                                 "the split stopped paying for itself: \(descCalls(runner).count) "
                                 + "calls for one bad name in \(wanted.count)")
    }

    /// And the other control: a batch brew answers is one call. Without it the
    /// bound above holds on an engine that asks for nothing at all.
    func testABatchBrewAnswersIsStillOneCall() {
        let wanted = names(32)
        let runner = partlyKnowingBrew(known: Set(wanted))

        let found = brewEngine(runner).descriptions(names: wanted, isCask: false)

        XCTAssertEqual(found.count, 32)
        XCTAssertEqual(descCalls(runner).count, 1)
    }

    // MARK: - The arithmetic under the bound

    // The number `describe`'s split is allowed to spend, and why it is two floors
    // rather than one:
    //
    //   * a batch brew refuses **wholesale** walks to a leaf per name and pays for
    //     every interior node: `2n-1` calls;
    //   * a batch with **one** name brew cannot resolve costs `2⌈log₂n⌉ + 1` (two
    //     calls a level), and that is the case the split exists for, so it must fit.
    //
    // The second is larger than `n + 1` for a small batch: a budget of `n + 1`
    // alone drops descriptions brew would give for three or five names (4 against
    // 5, and 6 against 7).

    /// Spelled out rather than derived from the production formula, so the two
    /// sides do not read one expression. Each value is counted by hand.
    func testABatchAlwaysAffordsIsolatingOneBadName() {
        for (names, isolating) in [(1, 1), (2, 3), (3, 5), (4, 5), (5, 7), (8, 7),
                                   (16, 9), (32, 11), (54, 13)] {
            XCTAssertGreaterThanOrEqual(DescriptionBudget(forBatchOf: names).allowance, isolating, """
                a batch of \(names) names is cut off before the split can isolate the \
                one name brew cannot resolve, which costs \(isolating) calls — every \
                description in the abandoned half is lost for a reason brew never gave
                """)
        }
    }

    /// The other floor, which bounds the pathological case: one call per name
    /// plus the batch itself.
    func testALargeBatchIsNeverAllowedMoreThanACallPerNameAndOne() {
        for names in [8, 16, 32, 54, 200] {
            XCTAssertLessThanOrEqual(DescriptionBudget(forBatchOf: names).allowance, names + 1,
                                     "a batch of \(names) names may spend "
                                     + "\(DescriptionBudget(forBatchOf: names).allowance) `brew` runs")
        }
    }

    /// And it is far under the `2n-1` the unbounded split reaches.
    func testTheBudgetIsWellUnderTheUnboundedSplit() {
        XCTAssertLessThan(DescriptionBudget(forBatchOf: 54).allowance, 2 * 54 - 1)
    }

    /// And it is spent one call at a time and then refuses — without which the
    /// two floors above are arithmetic nothing enforces.
    func testABudgetIsSpentAndThenRefuses() {
        let budget = DescriptionBudget(forBatchOf: 2)   // three calls, by both floors
        XCTAssertFalse(budget.exhausted)
        XCTAssertTrue(budget.spend())
        XCTAssertTrue(budget.spend())
        XCTAssertTrue(budget.spend())
        XCTAssertFalse(budget.spend(), "a fourth call was allowed out of a budget of three")
        XCTAssertTrue(budget.exhausted)
    }
}

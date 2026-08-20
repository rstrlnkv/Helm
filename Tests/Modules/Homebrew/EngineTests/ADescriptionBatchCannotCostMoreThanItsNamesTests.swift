// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_Homebrew_Engine

/// **The split-and-retry has no floor, and the crash report names this
/// function.**
///
/// `describe` asks `brew desc` for a whole batch, and on a non-zero exit halves
/// the batch and asks again — right for the case it was written for, which is
/// *one* name in fifty that brew can no longer resolve. It is a bisection, so
/// one bad name costs about a dozen calls instead of fifty, exactly as its doc
/// comment says.
///
/// Nothing bounds the other end. When brew refuses **every** call the recursion
/// runs to a leaf per name — `T(n) = 1 + T(n/2) + T(n-n/2)`, `T(1) = 1`, so
/// `2n-1` launches for `n` names — and each of those is a real subprocess taking
/// one of the app's eight `HelmProcess` slots. The page asks for descriptions
/// over the whole installed list on every load (`loadDescriptions` builds one
/// `names` array per kind), so a Cellar of 54 packages turns one page load into
/// 107 `brew` runs the moment brew answers non-zero for a reason that is not
/// about any one name.
///
/// It is not a hypothetical reason. Every name in the batch is unresolvable at
/// once whenever the tap they came from is gone — `brew untap homebrew/cask`
/// leaves every installed cask on disk and reported by `brew list --versions`,
/// and `brew desc --cask` refusing all of them is the same exit status as
/// refusing one. Any refusal that is a property of the *tool* rather than of a
/// name — a broken tap, a Ruby error, a CLT that no longer matches — reaches
/// here identically, and the crash report on 0.10.0-dev.12 has
/// `HelmProcess.runData` ← `HomebrewEngine.describe` inside `NSConcreteTask`.
///
/// **The bound asserted is structural, not a number pulled out of the air.**
/// One optimistic batch, then at most one call per name, is the most any
/// strategy can justify spending — `n + 1`. The bisection is under it for the
/// case it was written for (one bad name in thirty-two costs eleven calls, the
/// control below) and over it, at `2n-1`, exactly when the refusal is about the
/// tool. A threshold above every real case is a check that cannot fail; this
/// one sits at the level of the naive strategy it replaced.
final class ADescriptionBatchCannotCostMoreThanItsNamesTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// A brew that resolves the names in `known` and refuses any call carrying
    /// a name it does not know — validating the whole call before printing
    /// anything, which is what `brew desc` does (`HomebrewEngineQueryTests`
    /// records the observed shape: exit 1, message on stderr, stdout empty).
    ///
    /// With `known` empty it is a brew that refuses everything, which is the
    /// state under test. It is a state the real tool is genuinely in whenever
    /// the refusal is about the tool rather than about a name, and no fake
    /// simpler than this — one that fails a fixed number of times, say — could
    /// represent it.
    private final class PartlyKnowingBrew: ProcessRunner, @unchecked Sendable {
        let known: Set<String>
        private let lock = NSLock()
        private var _descCalls: [[String]] = []
        var descCalls: [[String]] { lock.lock(); defer { lock.unlock() }; return _descCalls }

        init(known: Set<String>) { self.known = known }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            guard args.first == "desc" else { return (0, "") }
            lock.lock(); _descCalls.append(args); lock.unlock()
            guard let terminator = args.firstIndex(of: "--") else { return (1, "") }
            let names = Array(args[args.index(after: terminator)...])
            guard names.allSatisfy(known.contains) else { return (1, "") }
            return (0, names.map { "\($0): description of \($0)" }.joined(separator: "\n") + "\n")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            onExit(0)
            return NoProcess()
        }
    }

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    private func names(_ count: Int) -> [String] {
        (0..<count).map { "pkg-\($0)" }
    }

    /// The whole batch refused: the bisection walks to a leaf per name and pays
    /// for every interior node on the way.
    func testABatchRefusedWholesaleCostsNoMoreCallsThanNames() {
        let wanted = names(32)
        let runner = PartlyKnowingBrew(known: [])

        _ = engine(runner).descriptions(names: wanted, isCask: true)

        XCTAssertLessThanOrEqual(runner.descCalls.count, wanted.count + 1, """
            \(wanted.count) names cost \(runner.descCalls.count) `brew desc` launches — more \
            than one batch plus a call per name, which is the worst case the split \
            exists to beat. Each one takes a slot out of the eight the whole app has.
            """)
    }

    /// The control, and it passes today: the case the split was written for is
    /// still cheap, so the bound above is not "never split" — it is the two of
    /// these together, and both are satisfiable at once by a budget on the
    /// recursion rather than by abandoning it. One bad name in thirty-two costs
    /// eleven calls, which is the "about a dozen instead of fifty" the function's
    /// own doc comment promises; that promise is worth keeping.
    func testOneUnresolvableNameStillCostsAboutADozenCalls() {
        let wanted = names(32)
        let runner = PartlyKnowingBrew(known: Set(wanted.dropLast()))

        let found = engine(runner).descriptions(names: wanted, isCask: false)

        XCTAssertEqual(found.count, 31, "the good names lost their descriptions to the bad one")
        XCTAssertLessThanOrEqual(runner.descCalls.count, 12,
                                 "the split stopped paying for itself: \(runner.descCalls.count) "
                                 + "calls for one bad name in \(wanted.count)")
    }

    /// And the other control: a batch brew answers is one call. Without it the
    /// bound above holds on an engine that asks for nothing at all.
    func testABatchBrewAnswersIsStillOneCall() {
        let wanted = names(32)
        let runner = PartlyKnowingBrew(known: Set(wanted))

        let found = engine(runner).descriptions(names: wanted, isCask: false)

        XCTAssertEqual(found.count, 32)
        XCTAssertEqual(runner.descCalls.count, 1)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import HelmApp
import HelmRuntime

/// The other half of `AResetAsksBeforeItDeletesTests`: the order is a value, and
/// this is what carries it out.
///
/// **Driven through the seam, not through the real steps.** The real steps move
/// this Mac's own `~/Library/Application Support/Helm` and `~/Library/Logs/Helm`
/// to the Trash, forget the preferences domain of whatever bundle is running the
/// suite, and relaunch — and the step under test would put an administrator
/// password dialog on the screen of whoever is running it. So
/// `run(standInIsLive:perform:)` is given a recorder. That the switch carrying a
/// step out has an arm for every step, and no `default:`, is the compiler's.
/// What the host does when it is asked is driven for real one target over,
/// against a fake that can decline — `ALidThatDidNotWorkSaysSoTests`.
@MainActor
final class AResetGoesThroughTheEnginesTests: XCTestCase {

    func testTheResetPerformsExactlyThePlanInItsOrder() {
        var performed: [ResetPlan.Step] = []
        ResetEverything.run(standInIsLive: false) { performed.append($0) }
        XCTAssertEqual(performed, ResetPlan.order,
                       "the reset carries its own order, or skips a step: the list of what a "
                       + "reset does is then two lists, and the one that is tested is not the "
                       + "one that runs")
    }

    /// The contract carries the default, so a module that holds nothing outside
    /// Helm answers this without writing a line — and the reset can ask all of
    /// them without knowing which is which.
    func testAnEngineThatHoldsNothingOutsideHelmAnswersAnyway() {
        FakeEngine().willDisable()
    }
}

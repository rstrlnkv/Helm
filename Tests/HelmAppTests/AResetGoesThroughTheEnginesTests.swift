// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// The other half of `AResetAsksBeforeItDeletesTests`: the order is a value, and
/// this is what carries it out.
///
/// **Read off the source, and the reason is the subject itself.** Driving
/// `ResetEverything.run()` moves this Mac's own `~/Library/Application
/// Support/Helm` and `~/Library/Logs/Helm` to the Trash, forgets the
/// preferences domain of whatever bundle is running the suite, and relaunches —
/// and the step under test would put an administrator password dialog on the
/// screen of whoever is running it. What the host does when it is asked is
/// driven for real one target over, against a fake that can decline —
/// `FakeClamshell.removalSucceeds`, and `ALidThatDidNotWorkSaysSoTests` covers
/// both the ask (`testSwitchingTheModuleOffAsksForTheGrantBack`) and the answer
/// that is no (`testADeclinedRemovalIsPublishedRatherThanDiscarded`). What the
/// *reset* asks for is pinned here.
@MainActor
final class AResetGoesThroughTheEnginesTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let text = try RepoSource.text(of: path)
        XCTAssertGreaterThan(text.count, 500, "\(path) was not read at all")
        return text
    }

    func testTheResetRunsThePlanRatherThanAnOrderOfItsOwn() throws {
        let reset = try source("Sources/HelmApp/ResetEverything.swift")
        XCTAssertTrue(reset.contains("for step in ResetPlan.order"),
                      "the reset carries its own order again — the list of what a reset "
                      + "does is then two lists, and the one that is tested is not the one "
                      + "that runs")
        XCTAssertFalse(reset.contains("default:"),
                       "a `default:` in the switch over the plan's steps turns a step "
                       + "added and never carried out into a silent no-op, which is the "
                       + "shape of the finding this file exists for")
    }

    func testTheResetAsksTheEnginesForWhatIsOutsideHelmsOwnFolders() throws {
        let reset = try source("Sources/HelmApp/ResetEverything.swift")
        XCTAssertTrue(reset.contains("handBackSystemState()"),
                      "«Reset all settings» never asks the engines for anything, so the "
                      + "passwordless pmset rule Keep Awake installed in /etc/sudoers.d "
                      + "outlives a reset that promises the machine is as it was just "
                      + "after installing")
    }

    /// And what the host does with the ask: every live engine, through the one
    /// call that means «the person is here».
    func testTheHostAsksEveryLiveEngine() throws {
        let host = try source("Sources/HelmApp/ModuleHost.swift")
        let after = try XCTUnwrap(host.range(of: "func handBackSystemState()"),
                                  "the host has no way to be asked for what its engines "
                                  + "hold outside Helm")
        let rest = host[after.upperBound...]
        let end = [rest.range(of: "\n    func "), rest.range(of: "\n    private func ")]
            .compactMap { $0?.lowerBound }.min()
        let body = String(end.map { rest[..<$0] } ?? rest)
        XCTAssertTrue(body.contains("willDisable()"),
                      "the host is asked and tells nobody: `willDisable()` is the only "
                      + "call that means «the person is at the screen and this is the "
                      + "last moment to ask», and it is what the grant's removal hangs on")
        XCTAssertTrue(body.contains("live"),
                      "the ask does not go to the live engines, so it reaches whichever "
                      + "engine somebody named by hand and no others")
    }

    /// The contract carries the default, so a module that holds nothing outside
    /// Helm answers this without writing a line — and the reset can ask all of
    /// them without knowing which is which.
    func testAnEngineThatHoldsNothingOutsideHelmAnswersAnyway() {
        final class Bare: ModuleEngine {
            let transport: EngineTransport = LocalTransport()
            func activate() {}
            func deactivate() {}
        }
        Bare().willDisable()
    }
}

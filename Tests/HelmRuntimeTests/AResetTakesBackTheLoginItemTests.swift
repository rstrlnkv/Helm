// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmTestSupport
import XCTest

/// The reset plan says the login item is given back, in the order that makes it
/// possible.
///
/// **Why this is a test.** «Reset all settings» promised, in the changelog and
/// on the button, that Helm goes back to how it was just after installing —
/// while `SMAppService.mainApp.register()` kept it opening at login, in a system
/// database outside both of Helm's folders. Nothing failed, because the plan is
/// a value and nobody asserted about it.
///
/// **Why it asserts about the plan and not about the system.** Registering a
/// login item in a test would register *the test runner*. The plan is where the
/// promise lives, and `ResetEverything`'s exhaustive switch is what turns a step
/// in the plan into work that happens.
final class AResetTakesBackTheLoginItemTests: XCTestCase {

    func testThePlanGivesBackTheLoginItem() {
        XCTAssertTrue(ResetPlan.order.contains(.giveBackTheLoginItem),
                      "a reset that leaves Helm opening at login is not a reset")
    }

    func testItComesAfterTheEnginesAndBeforeThePreferencesAreForgotten() throws {
        let order = ResetPlan.order
        let engines = try XCTUnwrap(order.firstIndex(of: .handBackWhatIsOutsideHelm))
        let login = try XCTUnwrap(order.firstIndex(of: .giveBackTheLoginItem))
        let forget = try XCTUnwrap(order.firstIndex(of: .forgetPreferences))
        XCTAssertLessThan(engines, login,
                          "the engines are asked while the person is still there to answer")
        XCTAssertLessThan(login, forget,
                          "unregistering reads Bundle.main, which is still whole before the domain goes")
    }

    func testEveryStepOfThePlanIsCarriedOut() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/ResetEverything.swift")
        let body = try XCTUnwrap(SwiftSource.body(of: "run", in: source))
        for step in ResetPlan.Step.allCases {
            XCTAssertTrue(body.contains(".\(step)"),
                          "\(step) is in the plan and not in the switch that carries it out")
        }
    }
}

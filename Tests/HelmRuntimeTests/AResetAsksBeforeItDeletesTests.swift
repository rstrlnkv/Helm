// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// **«Helm returns to how it was just after installing» is a promise about the
/// machine, not about two folders.**
///
/// A reset trashed Helm's own two directories and forgot its preferences, and
/// that was all it did — so the one thing Helm changes *outside* those folders
/// stayed: `/etc/sudoers.d/helm-keepawake`, a passwordless `pmset` rule for a
/// feature the reset had just made the app forget it ever had. Nothing in the
/// reset named it and nothing could, because the code that can take it back out
/// belongs to the module that put it there and needs somebody at the screen to
/// answer an administrator dialog.
///
/// So the order is a value rather than the shape of a function body, where the
/// omission was invisible: the engines are asked for what is theirs **first**,
/// while their settings still exist and the person is still there.
final class AResetAsksBeforeItDeletesTests: XCTestCase {

    func testTheEnginesAreAskedBeforeAnythingOfTheirsIsDeleted() throws {
        let ask = try XCTUnwrap(ResetPlan.order.firstIndex(of: .handBackWhatIsOutsideHelm),
                                "a reset never asks the engines for what they hold outside "
                                + "Helm's own folders, so a root grant outlives the feature "
                                + "that asked for it — on the screen whose whole promise is "
                                + "that nothing is left")
        let trash = try XCTUnwrap(ResetPlan.order.firstIndex(of: .trashHelmsOwnFolders))
        let forget = try XCTUnwrap(ResetPlan.order.firstIndex(of: .forgetPreferences))
        XCTAssertLessThan(ask, trash,
                          "the engines are asked after their state is in the Trash, so what "
                          + "they need to decide with is gone by the time they are asked")
        XCTAssertLessThan(ask, forget,
                          "the engines are asked after their settings are forgotten — the "
                          + "lid option that decides whether the grant is still wanted reads "
                          + "false to an engine that has not been told anything yet")
    }

    /// The relaunch is last, and it is what ends this process: anything after it
    /// would be a step nobody runs.
    func testNothingIsAskedOfAProcessThatIsAlreadyGone() {
        XCTAssertEqual(ResetPlan.order.last, .relaunch)
    }

    /// A hand-written list is tied to the thing it names, or it is a comment. A
    /// step added to the enum and forgotten here would simply never happen.
    func testEveryStepIsInTheOrderExactlyOnce() {
        for step in ResetPlan.Step.allCases {
            XCTAssertEqual(ResetPlan.order.filter { $0 == step }.count, 1,
                           "\(step) is in the order \(ResetPlan.order.filter { $0 == step }.count) "
                           + "times — a reset either skips it or does it twice")
        }
        XCTAssertEqual(ResetPlan.order.count, ResetPlan.Step.allCases.count)
    }
}

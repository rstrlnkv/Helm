// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// A press on a cask hands the engine a cask, and a press on a formula a formula.
///
/// `TheDoorRunsWhatItNamesTests` starts at the act, so it cannot see the model
/// build one: a model that dropped the kind on the way (`isCask: false` for every
/// ref) would uninstall a formula that happens to share the cask's name, an
/// irreversible branch. These read what the model hands the work.
/// Defect class kept: the model's press names a different kind than the row.
@MainActor
final class APressOnACaskNamesTheCaskTests: XCTestCase {

    func testInstallingACaskHitNamesACask() {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        model.install(SearchHit(name: "firefox", isCask: true))
        model.install(SearchHit(name: "wget", isCask: false))
        XCTAssertEqual(work.acts, [.install(PackageRef(name: "firefox", isCask: true)),
                                   .install(PackageRef(name: "wget", isCask: false))])
        model.stop()
    }

    func testUninstallingAConfirmedCaskNamesACask() async {
        let work = FakeHomebrewWork()
        work.dependents = []
        let model = HomebrewViewModel(work: work)

        await model.askToUninstall(BrewPackage(name: "firefox", version: "130", isCask: true))
        model.confirmUninstall()
        await model.askToUninstall(BrewPackage(name: "wget", version: "1.25", isCask: false))
        model.confirmUninstall()
        XCTAssertEqual(work.acts, [.uninstall(PackageRef(name: "firefox", isCask: true)),
                                   .uninstall(PackageRef(name: "wget", isCask: false))],
                       "the confirmed press named a different kind than the row")
        model.stop()
    }

    /// `isCask: true` on a formula makes the engine answer `[]`, and the dialog
    /// drops «still needed by».
    func testTheDependentsQuestionNamesTheKindOfTheRow() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)

        await model.askToUninstall(BrewPackage(name: "wget", version: "1.25", isCask: false))
        await model.askToUninstall(BrewPackage(name: "firefox", version: "130", isCask: true))
        XCTAssertEqual(work.dependentsAsked, [PackageRef(name: "wget", isCask: false),
                                              PackageRef(name: "firefox", isCask: true)],
                       "the dependents reading named a different kind than the row")
        model.stop()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// brew can vanish between the status read and the press. Each of the four
/// package operations must then say a failed state labelled with *its own*
/// operation, reason `brewMissing`, and launch nothing. The label is what the
/// page prints next to the refusal.
final class APressAfterBrewVanishedNamesItsOperationTests: XCTestCase {

    private func refusal(_ press: (HomebrewEngine) -> Void) async -> (OpState?, Int) {
        let news = EngineNews<HomebrewNews>()
        let runner = HangingRunner()
        let engine = HomebrewEngine(locator: NoBrew(), runner: runner, privileged: NoPrivileges(),
                                    user: "tester", news: news)
        press(engine)
        let state = await replay(news).states.last
        return (state, runner.streamCalls.count)
    }

    func testEachOperationRefusesUnderItsOwnLabel() async {
        let cases: [(String, (HomebrewEngine) -> Void)] = [
            ("install wget", { $0.install(name: "wget", isCask: false) }),
            ("uninstall wget", { $0.uninstall(name: "wget", isCask: false) }),
            ("upgrade wget", { $0.upgrade(name: "wget") }),
            ("upgrade all", { $0.upgradeAll() }),
        ]
        for (label, press) in cases {
            let (state, launches) = await refusal(press)
            XCTAssertEqual(state?.label, label)
            XCTAssertEqual(state?.phase, .failed, label)
            XCTAssertEqual(state?.reason, .brewMissing, label)
            XCTAssertEqual(launches, 0, label)
        }
    }
}

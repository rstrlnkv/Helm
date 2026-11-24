// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// **A refusal has a verb.**
///
/// A `--nc stop` the tool would not perform must not reach the page as «macOS
/// refused to connect «Office»», read by the person who just asked to bring
/// that tunnel *down*, about a tunnel still up and carrying everything this Mac
/// sends.
final class ARefusalRemembersItsVerbTests: XCTestCase {

    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings.inMemory(),
                  runner: runner, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    private func runner(refusing text: String) -> FakeRunner {
        let runner = FakeRunner(list: "(Connected) \(uuid) IPSec \"Office\"")
        runner.reply = text
        return runner
    }

    func testAStopTheToolRefusedIsRecordedAsAStop() {
        let e = engine(runner(refusing: "cannot stop Office: resource busy"))

        e.disconnect("Office", auto: false)

        XCTAssertEqual(e.lastFailure?.reason, .refused, "precondition: the refusal was read")
        XCTAssertEqual(e.lastFailure?.verb, .disconnect,
                       "the person asked to bring a tunnel down, the tool would not, and the "
                       + "page tells them Helm could not connect it")
    }

    /// The control: not every command is reported as a stop.
    func testAConnectTheToolRefusedIsStillRecordedAsAConnect() {
        let e = engine(runner(refusing: "cannot start Office: resource busy"))

        e.connect("Office", auto: false)

        XCTAssertEqual(e.lastFailure?.verb, .connect)
    }
}

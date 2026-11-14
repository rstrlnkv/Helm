// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_Homebrew_UI

/// Health's refresh, pressed repeatedly, runs at most two `brew doctor` children.
///
/// A control that can be pressed repeatedly never has an unbounded launch behind
/// it. A press while a reading is out asks for one more when it lands; that one
/// starts only after the first has answered, so a reading begun before an
/// operation ended never answers for it.
@MainActor
final class AHealthRefreshPressedRepeatedlyAsksDoctorTwiceAtMostTests: XCTestCase {

    private func doctors(_ work: FakeHomebrewWork) -> Int {
        work.calls.filter { $0 == "readDoctor" }.count
    }

    func testTenPressesAskTwiceAndTheSecondWaitsForTheFirst() async {
        let work = FakeHomebrewWork()
        work.park("readDoctor")
        let model = HomebrewViewModel(work: work)

        let presses = (0..<10).map { _ in Task { await model.refreshDoctor() } }
        await eventually("the first reading is out") { self.doctors(work) == 1 }
        await grace()
        XCTAssertEqual(doctors(work), 1, "a second reading started beside the first")

        work.release("readDoctor")
        for press in presses { await press.value }
        XCTAssertEqual(doctors(work), 2, "ten presses must ask exactly twice")
        XCTAssertEqual(work.completed.filter { $0 == "readDoctor" }.count, 2)
    }

    /// A model closed while a reading is out does not start the asked-for second one:
    /// a closed door answers nil, which that second reading would draw as `.refused`.
    func testAClosedModelStartsNoSecondReading() async {
        let work = FakeHomebrewWork()
        work.park("readDoctor")
        let model = HomebrewViewModel(work: work)

        let presses = (0..<2).map { _ in Task { await model.refreshDoctor() } }
        await eventually("the first reading is out") { self.doctors(work) == 1 }
        await grace()
        model.stop()
        work.release("readDoctor")
        for press in presses { await press.value }

        XCTAssertEqual(doctors(work), 1)
        if case .refused = model.doctor { XCTFail("a second reading ran on a closed model") }
    }
}

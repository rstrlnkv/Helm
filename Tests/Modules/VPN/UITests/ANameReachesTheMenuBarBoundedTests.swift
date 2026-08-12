// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Combine
import HelmContract
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The module's end of `StatusPlan.menuBarTitle`.
///
/// The host draws whatever a descriptor hands it — `StatusItemController` takes
/// `appearance.title` verbatim — so the bound is applied by the module that has
/// an unbounded string, which is this one: the name comes out of a configuration
/// somebody else wrote.
@MainActor
final class ANameReachesTheMenuBarBoundedTests: XCTestCase {

    private func appearance(name: String) -> StatusAppearance {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        descriptor.viewModel(host).setForTesting(
            automation: VPNAutomation(at: Date(), name: name, kind: .connected),
            notice: .menuBar)
        return descriptor.statusAppearance(host)
    }

    func testAnOrdinaryNameIsStillTheName() {
        XCTAssertEqual(appearance(name: "Office").title, "Office")
    }

    func testAFourThousandCharacterNameDoesNotReachTheMenuBar() {
        let title = appearance(name: String(repeating: "M", count: 4000)).title
        XCTAssertEqual(title, StatusPlan.menuBarTitle(String(repeating: "M", count: 4000)),
                       "the module bounded the name by a rule of its own, or not at all")
        XCTAssertLessThanOrEqual(title?.count ?? .max, 24)
    }

    func testANameThatIsNothingButANewlineNamesNothing() {
        XCTAssertNil(appearance(name: "\n").title,
                     "an empty title claims the one title slot from a module that has news")
    }
}

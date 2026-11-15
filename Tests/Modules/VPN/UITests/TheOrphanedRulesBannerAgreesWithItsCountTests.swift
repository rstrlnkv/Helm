// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmUI
import XCTest
@testable import Module_VPN_UI

/// **"1 rule points at…", "3 rules point at…".** The banner above the grid names
/// a count in front of a noun that agrees with it; Russian has three forms, so a
/// picker that sends two counts to the wrong key reads wrong and nothing else fails.
@MainActor
final class TheOrphanedRulesBannerAgreesWithItsCountTests: XCTestCase {

    func testEnglishSingularAndPluralDiffer() {
        XCTAssertEqual(VPNStr.orphanedRules(1, language: .en),
                       "1 rule points at a VPN that is no longer in System Settings")
        XCTAssertEqual(VPNStr.orphanedRules(3, language: .en),
                       "3 rules point at a VPN that is no longer in System Settings")
    }

    func testRussianUsesOneFewAndManyForTheirCounts() {
        let tail = " на VPN, которого больше нет в Системных настройках"
        XCTAssertEqual(VPNStr.orphanedRules(1, language: .ru), "1 правило указывает" + tail)
        XCTAssertEqual(VPNStr.orphanedRules(21, language: .ru), "21 правило указывает" + tail)
        XCTAssertEqual(VPNStr.orphanedRules(2, language: .ru), "2 правила указывают" + tail)
        XCTAssertEqual(VPNStr.orphanedRules(5, language: .ru), "5 правил указывают" + tail)
        XCTAssertEqual(VPNStr.orphanedRules(11, language: .ru), "11 правил указывают" + tail)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A label that wraps puts three cards on three baselines, and the card cannot
/// grow to fix it.**
///
/// «Name in menu bar» was the defect: 117.9 pt in German, 125.0 in Portuguese,
/// 147.3 in Spanish and 148.7 in French against a 104 pt card. Widening the card
/// is not the answer either — the row label beside it takes what is left of the
/// 680 pt row, and «Wenn ein Tunnel von selbst abbricht» is 219.1 pt of it, so
/// the ceiling is about 140. Russian fitted with 3.2 pt to spare, which is what
/// «it fits on my Mac» is worth.
///
/// Measured rather than looked at, because the offender is French and this suite
/// runs in English. The width comes from `VPNSettingsPage.noticeThumbnail` —
/// the page's own number, not a copy of it — and the font from `HelmChoiceCards`'
/// own label: `.caption` at semibold, which is the widest of the two weights
/// that control draws and the one the chosen card gets.
final class TheNoticeLabelsFitTheCardTests: XCTestCase {

    /// `.caption` is 10 pt on macOS, and the control's own comment says that
    /// size may not move because these widths were measured against it.
    private func width(_ text: String) -> CGFloat {
        let label = NSFont.systemFont(ofSize: 10, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: label]).width
    }

    func testEveryNoticeLabelFitsOnOneLineInEveryLanguage() {
        let card = VPNSettingsPage.noticeThumbnail.width
        var offenders: [String] = []
        for language in AppLanguage.allCases {
            for notice in VPNNotice.allCases {
                let text = VPNStr.noticeOption(notice, language: language)
                let measured = width(text)
                if measured > card {
                    offenders.append("  \(language.rawValue) \(notice): «\(text)» is "
                                     + "\(String(format: "%.1f", measured)) pt of \(card)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) notice label(s) are wider than the card they are drawn "
                      + "under, so that card's label wraps and the row loses its baseline:\n"
                      + offenders.sorted().joined(separator: "\n"))
    }

    /// The measurement this file is worth nothing without: that the instrument
    /// still sees the defect. The three labels have 19.7 pt of slack at their
    /// worst, which is close enough to the card that a threshold set above every
    /// real case would look exactly like a pass.
    func testTheInstrumentStillFailsTheLabelThisReplaced() {
        let card = VPNSettingsPage.noticeThumbnail.width
        // The French of the key that was deleted, as it shipped in 0.9.0.
        XCTAssertGreaterThan(width("Nom dans la barre des menus"), card,
                             "the measurement no longer sees a label that was two lines on "
                             + "screen, so a pass above says nothing")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import AppKit
import HelmRuntime
import HelmUI
@testable import HelmApp

/// **The first thing anybody opens when something is wrong, and its sentence used
/// to wrap.**
///
/// The plate reporting withheld grants is the top row of the panel. At the body
/// step it needed 269 pt of the 296 the panel has in English, 293 in Russian and
/// 303 in Portuguese — so two of the eight languages drew two lines, and the plate
/// stood as tall as a whole widget for one sentence. It is drawn at the panel's own
/// step now (`HelmBanner`'s `compact`), where the widest is Portuguese at 278.
///
/// This measures the drawn height rather than the strings, in every language, so a
/// translation that grows fails here instead of wrapping on somebody's screen. The
/// height comes from the view: a test that re-measured the fonts would agree with
/// itself and not with the panel.
@MainActor
final class ThePanelsPermissionPlateFitsOneLineTests: XCTestCase {

    /// The plate's own width inside the panel: the window, less the grid's padding
    /// either side. Read from the app's constants rather than typed, so a panel
    /// that changes width brings this with it.
    private var plateWidth: CGFloat { helmPanelWidth - PanelGrid.padding * 2 }

    private func height<V: View>(_ view: V) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: plateWidth))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    private func plateHeight(_ language: AppLanguage, withheld: [PermissionNeed]) -> CGFloat {
        AppLanguage.override = language
        defer { AppLanguage.override = nil }
        return height(PermissionsWidget(withheld: withheld))
    }

    /// **The measurement can fail**, which is what makes the rest of this file
    /// worth reading: a sentence too long for the row draws taller, and by about a
    /// line. Without this the assertions below would pass on a plate that had
    /// stopped drawing text at all.
    func testAWrappedSentenceIsVisiblyTaller() {
        let oneLine = height(HelmBanner("2 permissions not granted",
                                        symbol: "exclamationmark.circle.fill",
                                        compact: true) { EmptyView() })
        let twoLines = height(HelmBanner(String(repeating: "permissions not granted ", count: 4),
                                         symbol: "exclamationmark.circle.fill",
                                         compact: true) { EmptyView() })
        XCTAssertGreaterThan(twoLines, oneLine + 8,
                             "a sentence four times too long drew \(twoLines) pt against "
                             + "\(oneLine): this measurement cannot see a wrap")
    }

    /// Every language, both counts — one withheld grant and two, because the two
    /// draw different verbs («Grant…» goes to the one place there is, «Show» to the
    /// list) and the verb is what the sentence shares the row with.
    func testEveryLanguageKeepsThePlateOnOneLine() {
        let reference = plateHeight(.en, withheld: [.accessibility])
        var offenders: [String] = []
        for language in AppLanguage.allCases {
            for withheld: [PermissionNeed] in [[.accessibility],
                                               [.accessibility, .fullDiskAccess]] {
                let drawn = plateHeight(language, withheld: withheld)
                if drawn > reference + 4 {
                    offenders.append("  \(language.rawValue) with \(withheld.count): "
                                     + "\(Int(drawn)) pt against \(Int(reference))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) plate(s) wrap at the panel's width, so the first thing "
                      + "somebody opens when a grant is missing is a paragraph:\n"
                      + offenders.sorted().joined(separator: "\n"))
    }

    /// And it is a line rather than a widget: the plate exists because the notice
    /// had been drawn inside a panel card, which gave one sentence a figure's
    /// height. 40 pt is a line with its own padding; a widget body starts at 60.
    func testThePlateIsALineAndNotAWidget() {
        let drawn = plateHeight(.en, withheld: [.accessibility, .fullDiskAccess])
        XCTAssertLessThan(drawn, 40,
                          "the plate is \(Int(drawn)) pt tall, which is a widget's height for one "
                          + "sentence — it is drawn inside a card again")
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import HelmUI

/// The space a row leaves where a checkbox would be is the size of a checkbox.
///
/// Two lists draw rows that can be ticked beside rows that cannot — Login Items
/// holds what macOS protects, the Uninstaller holds the app bundle itself — and
/// both filled the gap with a clear rectangle of a width somebody typed. The
/// Uninstaller's two said 16 and Login Items' said 14, so its protected rows
/// stepped 2 pt to the left of every markable one: the name started at x = 56.0
/// in a row with a checkbox and 54.0 in a row without.
///
/// A number typed twice with one of them wrong is the argument for one place; a
/// number typed at all is the argument for **measuring** it, which is what this
/// test does. AppKit owns the size of a checkbox and can change it in a release,
/// and this is the only thing that would say so.
@MainActor
final class ARowWithNothingToTickKeepsTheColumnTests: XCTestCase {

    /// The real control, hosted on its own and asked what it wants — the same
    /// question `HelmPickerWidth`'s own tests ask a pop-up.
    private func checkbox() -> CGSize {
        let host = NSHostingView(rootView: Toggle("tick", isOn: .constant(false))
            .toggleStyle(.checkbox)
            .labelsHidden())
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// The subject exists before anything is asserted about it: a hosted control
    /// that measured nothing would make the comparison below pass on two zeros.
    func testTheCheckboxWasMeasuredAtAll() {
        let measured = checkbox()

        XCTAssertGreaterThan(measured.width, 10,
                             "no checkbox was hosted — its width came back as \(measured.width), "
                             + "so the comparison this file is about has nothing on either side")
        XCTAssertGreaterThan(measured.height, 10)
    }

    /// And the slot is that size, in both directions: the width holds the column,
    /// and the height keeps a row with nothing to tick as tall as its neighbours.
    func testTheSlotIsTheSizeOfTheControlItStandsIn() {
        let measured = checkbox()

        XCTAssertEqual(HelmCheckboxSlot.side, measured.width, accuracy: 0.5,
                       "a row with nothing to tick reserves \(HelmCheckboxSlot.side) pt where "
                       + "macOS draws a checkbox \(measured.width) pt wide, so every name in "
                       + "such a row starts \(measured.width - HelmCheckboxSlot.side) pt off "
                       + "the column")
        XCTAssertEqual(HelmCheckboxSlot.side, measured.height, accuracy: 0.5)
    }
}

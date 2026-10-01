import XCTest
import AppKit
@testable import HelmUI

/// The rule editor's pickers carry a fixed width so its rows read as columns.
/// Those widths were measured against English and then translated past — the
/// field picker was 150 pt while "Fecha de modificación" needs 184 and even
/// English's own "Downloaded from" needs 155. The width is computed now, so
/// these tests pin the arithmetic against what AppKit actually does.
final class PickerWidthTests: XCTestCase {

    /// The one number written down: everything else is measured text.
    func testTheChromeMatchesWhatAPopUpButtonAddsToItsTitle() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for title in ["Name", "Downloaded from", "Fecha de modificación",
                      "Дата изменения", "In Unterordner einsortieren"] {
            let button = NSPopUpButton(frame: .zero, pullsDown: false)
            button.font = font
            button.addItem(withTitle: title)
            button.sizeToFit()
            let text = (title as NSString).size(withAttributes: [.font: font]).width
            XCTAssertEqual(button.frame.width - text, HelmPickerWidth.chrome, accuracy: 1,
                           "chrome changed for \(title)")
        }
    }

    func testTheWidthFitsTheLongestLabel() {
        let labels = ["Name", "Fecha de modificación", "Дата изменения"]
        let width = HelmPickerWidth.fitting(labels, minimum: 150)
        for label in labels {
            let button = NSPopUpButton(frame: .zero, pullsDown: false)
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            button.addItem(withTitle: label)
            button.sizeToFit()
            XCTAssertGreaterThanOrEqual(width, button.frame.width - 1,
                                        "\(label) would be clipped at \(width)")
        }
    }

    /// A row of short words keeps the column it was designed with.
    func testShortLabelsDoNotShrinkTheColumn() {
        XCTAssertEqual(HelmPickerWidth.fitting(["is", "was"], minimum: 140), 140)
    }

    func testNoLabelsIsStillTheMinimum() {
        XCTAssertEqual(HelmPickerWidth.fitting([], minimum: 160), 160)
    }
}

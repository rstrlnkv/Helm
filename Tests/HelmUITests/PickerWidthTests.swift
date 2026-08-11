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

    // MARK: - A segmented control is not a pop-up

    /// A pop-up shows one title at a time, so it fits the widest. A segmented
    /// control shows every title at once **in equal segments**, so it fits the
    /// widest × the count — and the arithmetic of the one is wrong for the other
    /// in exactly the case that matters: labels of different lengths.
    ///
    /// Pinned against `NSSegmentedControl.sizeToFit` under `.fillEqually`, which
    /// is what SwiftUI's `.segmented` picker asks for to the point
    /// (`AnImposedPickerWidthFitsItsLabelsTests` measured the hosted control
    /// against this same yardstick in 24 readings).
    func testTheSegmentedWidthIsWhatAnEquallyDistributedControlAsksFor() {
        for labels in Self.labelSets {
            let asked = Self.askedFor(labels)
            let computed = HelmPickerWidth.segmented(labels)
            XCTAssertGreaterThanOrEqual(computed, asked,
                                        "\(labels.joined(separator: "|")) asks for \(asked) pt "
                                        + "and is computed at \(computed) — it will clip")
            XCTAssertLessThanOrEqual(computed, asked,
                                     "\(labels.joined(separator: "|")) asks for \(asked) pt and "
                                     + "is computed at \(computed) — slack, and AppKit centres a "
                                     + "segmented control in the width it is given, so the row's "
                                     + "left edge moves off the gutter by half of it")
        }
    }

    /// The shipped defect, kept as its own case: three labels of very different
    /// lengths in Russian. Summing the inks answered 263 pt where the control
    /// asks 403.5, and no test could see it because the two models agree
    /// whenever every label is the same length — which English nearly is.
    func testTheLogsRussianLevelsAreNotMeasuredBySummingThem() {
        let labels = ["Всё", "Предупреждения", "Ошибки"]
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let summed = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .reduce(0, +) + 26 * CGFloat(labels.count)

        XCTAssertGreaterThan(HelmPickerWidth.segmented(labels), summed + 100,
                             "the widest label is drawn three times over here, so the sum of the "
                             + "three is short by more than 100 pt — \(summed) against "
                             + "\(Self.askedFor(labels)) asked for")
    }

    /// Four scripts, two-to-four segments, and label sets both even and ragged.
    private static let labelSets: [[String]] = [
        ["Everything", "Warnings", "Errors"], ["Всё", "Предупреждения", "Ошибки"],
        ["Alles", "Warnungen", "Fehler"], ["Tout", "Avertissements", "Erreurs"],
        ["すべて", "警告", "エラー"], ["全部", "警告", "错误"],
        ["Installed", "Updates", "Search"], ["インストール済み", "アップデート", "検索"],
        ["Leftovers", "All"], ["Программы", "Осиротевшие"],
        ["A", "B", "C", "D"], ["Однажды", "Дважды", "Трижды", "Четырежды"],
    ]

    private static func askedFor(_ labels: [String]) -> CGFloat {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                        target: nil, action: nil)
        control.segmentDistribution = .fillEqually
        control.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        control.sizeToFit()
        return control.frame.width
    }
}

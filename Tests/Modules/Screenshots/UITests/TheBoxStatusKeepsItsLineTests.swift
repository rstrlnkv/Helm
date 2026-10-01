import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The status on a box row ("Still on in macOS") is one line in every
/// language, and the warning under box 184's name is what wraps.** Measured
/// offscreen with the hosting view's own fitting size, the way the bar is.
@MainActor
final class TheBoxStatusKeepsItsLineTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The view's ideal size. No width parameter: a width set on the host is
    /// ignored by its fitting size — `height(_:at:)` below lays out at one.
    private func fitting<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize
    }

    /// Offered a width no sentence fits in, a status that may wrap does; one
    /// held to a line answers with its own single line. The control is a lone
    /// letter at the same font: a status taller than it is wrapped.
    func testEveryStatusIsOneLineEvenWhereTheRowIsNarrow() {
        AppLanguage.each { language in
            let oneLine = fitting(Text("Ag").font(HelmText.rowDetail)).height
            XCTAssertGreaterThan(oneLine, 0, "\(language): the control measured nothing")
            for state in [BoxState.on, .off, .unknown] {
                let squeezed = fitting(BoxStatusSqueezed(state: state))
                XCTAssertEqual(squeezed.height, oneLine, accuracy: 1.0,
                               "\(language): the status '\(ScreenshotsSettingsPage.say(state))' wrapped in a narrow row — \(squeezed.height) against \(oneLine)")
            }
        }
    }
}

extension TheBoxStatusKeepsItsLineTests {

    /// A row's content width on the page: the card less a row's own inset, at
    /// the settings column and at the narrowest the window allows (860 pt with
    /// the sidebar at its 320 pt maximum leaves 539 for the detail).
    private static let rowWidths: [CGFloat] = [HelmLayout.cardWidth - 20, 539 - HelmLayout.formInset * 2 - 20]

    /// Height of `view` laid out at exactly `width` — a frame, because a hosting
    /// view's fitting size answers with the ideal size and ignores a width set
    /// on the host.
    private func height<V: View>(_ view: V, at width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize.height
    }

    /// **At the page's narrowest, in every language, box 184's row is exactly
    /// the row a status that cannot wrap would make.** The control is the same
    /// setting row with the same name and the same warning and, in the status's
    /// place, a rigid block as wide as the status's own single line — so the
    /// warning gets exactly the column the status leaves and nothing else
    /// differs. A status that wraps, or that the label squeezes, changes the
    /// row's height and the column the warning wraps in. The warning must
    /// actually wrap at the narrowest width for the comparison there to mean anything,
    /// and that is asserted first.
    func testThe184RowAtTheNarrowestIsTheWarningsColumnAndNothingElse() {
        AppLanguage.each { language in
            let status = fitting(ScreenshotsSettingsPage.BoxStatus(state: .on, warns: true))
            XCTAssertGreaterThan(status.width, 0, "\(language): the status measured nothing")
            for width in Self.rowWidths {
                let row = height(ScreenshotsSettingsPage.BoxRow(
                    reading: SystemBoxReading(box: .panel, state: .on, keyCode: nil, modifiers: nil), warns: true), at: width)
                let control = height(HelmSettingRow(ScStr.boxName(.panel), note: ScStr.panelBoxWarning) {
                    Color.clear.frame(width: status.width, height: status.height)
                }, at: width)
                let oneLineWarning = fitting(Text(ScStr.panelBoxWarning).font(HelmText.rowDetail)).height
                let wrappedWarning = height(Text(ScStr.panelBoxWarning).font(HelmText.rowDetail)
                    .fixedSize(horizontal: false, vertical: true), at: width - status.width - 12)
                // At the settings column a short language fits on one line; at
                // the narrowest every language must wrap, or the case is not met.
                if width == Self.rowWidths.last {
                    XCTAssertGreaterThan(wrappedWarning, oneLineWarning + 1,
                                         "\(language) at \(width): the warning did not wrap, so this width proves nothing")
                }
                XCTAssertEqual(row, control, accuracy: 0.5,
                               "\(language) at \(width): the 184 row is \(row) pt where a status held to one line makes \(control) pt")
            }
        }
    }
}

/// The status in a row the page could never give it enough width for.
private struct BoxStatusSqueezed: View {
    let state: BoxState
    var body: some View {
        ScreenshotsSettingsPage.BoxStatus(state: state, warns: false).frame(width: 40, alignment: .leading)
    }
}

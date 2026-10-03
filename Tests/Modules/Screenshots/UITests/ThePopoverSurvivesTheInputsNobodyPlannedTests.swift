import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The pop-over is closed by everything that puts its tool down, toggles on a second request, goes with the overlay
/// and with the desk, and says its percent the way the language writes it.**
///
/// The inputs of the plan's list that nobody fed: a second open request while open, each of the actions that end the
/// tool (`.tool` of another tool, `.tool` of the same one, `.select`, a save), the overlay closed or ended by a display
/// change while the pop-over is up, and the sign of the percent, which a fixed "en" locale gets right for ja, pt and zh as well, and not for de, es, fr and ru.
@MainActor
final class ThePopoverSurvivesTheInputsNobodyPlannedTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        AppLanguage.override = nil
        super.tearDown()
    }

    private func build() throws -> (DisplayID, OverlayView, CaptureOverlay) {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.pen))
        return (id, try XCTUnwrap(built.view(for: id)), built)
    }

    private func hosts(in view: OverlayView) -> [NSView] {
        view.subviews.filter { $0 is EditorBarHostingView<EditorPopover> }
    }

    private func opened(_ overlay: CaptureOverlay, file: StaticString = #filePath, line: UInt = #line) {
        overlay.perform(.thicknessAndOpacity(anchorX: 300))
        XCTAssertTrue(overlay.popoverIsOpen, "control: open", file: file, line: line)
    }

    // MARK: asked twice

    func testASecondRequestWhileOpenClosesItAndAThirdOpensItAgain() throws {
        let (id, view, overlay) = try build()
        opened(overlay)
        XCTAssertNotNil(overlay.chrome(on: id)?.popover)
        XCTAssertEqual(hosts(in: view).count, 1, "control: one host while it is open")
        XCTAssertEqual(hosts(in: view).first?.isHidden, false)
        overlay.perform(.thicknessAndOpacity(anchorX: 500))
        XCTAssertFalse(overlay.popoverIsOpen, "the second request toggles")
        XCTAssertNil(overlay.chrome(on: id)?.popover)
        XCTAssertEqual(hosts(in: view).count, 1, "one host, kept hidden, not a second one made")
        XCTAssertEqual(hosts(in: view).first?.isHidden, true, "the host is still on screen after the pop-over closed")
        opened(overlay)
        XCTAssertEqual(hosts(in: view).count, 1, "opening again reuses the host")
        XCTAssertEqual(hosts(in: view).first?.isHidden, false)
    }

    // MARK: what ends the tool ends the pop-over

    func testEveryActionThatPutsTheToolDownClosesIt() throws {
        let cases: [(String, EditorAction)] = [("another tool", .tool(.highlighter)), ("the same tool again", .tool(.pen)),
                                              ("Select", .select), ("Save", .exit(.save))]
        for (name, action) in cases {
            let (_, _, overlay) = try build()
            opened(overlay)
            overlay.perform(action)
            XCTAssertFalse(overlay.popoverIsOpen, "\(name) left the pop-over open")
            overlay.close()
            self.overlay = nil
            results = []
        }
    }

    func testAPickAndAnUndoLeaveItOpenAsItsOwnSlidersAreThePicks() throws {
        let (_, _, overlay) = try build()
        opened(overlay)
        overlay.perform(.thickness(.thick))
        overlay.perform(.opacity(0.4))
        overlay.perform(.undo)
        XCTAssertTrue(overlay.popoverIsOpen, "a slider moved and it closed what edits them")
    }

    // MARK: the end of the overlay

    func testClosingTheOverlayWithItOpenHoldsNoMoreThanClosingItWithoutOne() throws {
        func survivors(open: Bool) throws -> (overlay: Bool, view: Bool) {
            weak var weakView: OverlayView?
            weak var weakOverlay: CaptureOverlay?
            do {
                let (_, view, overlay) = try build()
                if open { opened(overlay) }
                weakView = view
                weakOverlay = overlay
                overlay.close()
                XCTAssertFalse(overlay.popoverIsOpen, "closed with the pop-over up and it is still open")
                self.overlay = nil
            }
            for _ in 0..<20 where weakOverlay != nil || weakView != nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return (weakOverlay != nil, weakView != nil)
        }
        let without = try survivors(open: false)
        let with = try survivors(open: true)
        XCTAssertEqual(with.overlay, without.overlay, "the pop-over's host holds the overlay (control without: \(without))")
        XCTAssertEqual(with.view, without.view, "the pop-over's host holds the view (control without: \(without))")
    }

    func testADisplayChangeWithItOpenEndsTheCaptureAndTheNextOneStartsClosed() throws {
        let (_, _, overlay) = try build()
        opened(overlay)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(results.count, 1, "the capture did not end")
        if case .cancelled? = results.first {} else { XCTFail("ended with \(String(describing: results.first))") }
        // `finish` only reports; the owner closes on the result (`ScreenshotsCapture.overlayFinished`), and that close takes the pop-over.
        overlay.close()
        XCTAssertFalse(overlay.popoverIsOpen, "the owner closed the overlay and the pop-over is still there")
    }

    // MARK: the sign of the percent

    /// «50 %» in some languages, «50%» in others: read here from `NumberFormatter`, which shares no code with the format
    /// style the label uses. A label fixed to English or to the Mac's region passes the digits and fails this.
    func testThePercentIsWrittenTheWayEachLanguageWritesIt() {
        var texts: Set<String> = []
        AppLanguage.each { language in
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: language.rawValue)
            formatter.numberStyle = .percent
            formatter.maximumFractionDigits = 0
            let expected = formatter.string(from: 0.55)
            let text = EditorPopover.opacityText(0.55)
            XCTAssertEqual(text, expected, "\(language): the pop-over says «\(text)»")
            texts.insert(text)
        }
        XCTAssertGreaterThan(texts.count, 1, "control: the languages do not all write the percent alike, so the comparison can fail")
    }

    /// The same process changes language between two calls: nothing is cached from the first.
    func testALanguageChangedBetweenTwoCallsIsReadAtOnce() {
        AppLanguage.override = .en
        let english = EditorPopover.opacityText(0.5)
        let thicknessEnglish = EditorPopover.thicknessText(.thin, for: .pen)
        AppLanguage.override = .fr
        XCTAssertNotEqual(EditorPopover.opacityText(0.5), english)
        XCTAssertNotEqual(EditorPopover.thicknessText(.thin, for: .pen), thicknessEnglish)
    }
}

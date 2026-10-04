import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Through the overlay: the lines Copy Text hands the clipboard are those the person's own blur does not lie on.** A fake reader answers
/// with two lines, one under a blur drawn in the editor and one clear of it, and the copy closure records what it was given.
@MainActor
final class TheCopyOfTheTextLeavesOutWhatThePersonCoveredTests: XCTestCase {

    private final class Tools: @unchecked Sendable {
        private let lock = NSLock()
        private var _copied: [[RecognizedLine]] = []
        let answer: CaptureSession.AreaReading
        init(_ answer: CaptureSession.AreaReading) { self.answer = answer }
        var copied: [[RecognizedLine]] { lock.withLock { _copied } }
        func copy(_ lines: [RecognizedLine]) -> CaptureSession.TextCopy {
            lock.withLock { _copied.append(lines) }
            return .copied
        }
    }

    private var rigged: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView)?

    override func setUp() { super.setUp(); AppLanguage.override = .en }
    override func tearDown() { rigged?.overlay.close(); rigged = nil; AppLanguage.override = nil; super.tearDown() }

    func testALineUnderTheBlurIsNotHandedToTheClipboardAndAClearOneIs() async throws {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        let lines = [RecognizedLine(string: "under", box: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1)),
                     RecognizedLine(string: "clear", box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1))]
        let tools = Tools(.read(lines, RecognizedBoxes.Source(pixels: area, scale: 1)))
        let editorTools = EditorTextTools(read: { [tools] _, _ in tools.answer }, copy: { [tools] in tools.copy($0) })
        let built = try OverlayRig.overlay(scale: 1, area: area, textTools: editorTools) { _ in }
        rigged = built
        let (overlay, display, view) = built
        // "under" lies at y 160...190 of the display, "clear" at 340...370: the blur is drawn over the first only.
        overlay.perform(.tool(.blur))
        overlay.mouseDown(on: display, at: CGPoint(x: 120, y: 150), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 400, y: 220), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(overlay.editedLayers.map(\.tool), [.blur], "the subject: a blur is on the picture")
        overlay.perform(.copyText)
        await waitUntil("the copy was made") { tools.copied.count == 1 }
        XCTAssertEqual(tools.copied.first?.map(\.string), ["clear"])
        await waitUntil("the plate") { !view.visiblePlates.isEmpty }
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.textCopied])
    }
}

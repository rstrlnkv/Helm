import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// A colour panel that is never shown, with the port's states and no others: open on an ink with one closure to hear picks, or put away
/// (and then it hears nothing). A second `open` replaces the closure, as the real panel's target is replaced. `lateDelivery` is the one
/// thing the real panel can do that a state cannot say: an action message already on its way when `close` came.
/// NEVER stands for the real `NSColorPanel`; no test opens that one.
@MainActor final class FakeColourPanel: ColourPanelOpening {
    private(set) var isOpen = false
    private(set) var opened: [AnnotationInk] = []
    private(set) var closed = 0
    private var onPick: ((AnnotationInk) -> Void)?
    private var last: ((AnnotationInk) -> Void)?

    func open(showing ink: AnnotationInk, onPick: @escaping (AnnotationInk) -> Void) {
        isOpen = true
        opened.append(ink)
        self.onPick = onPick
        last = onPick
    }

    func close() {
        isOpen = false
        closed += 1
        onPick = nil
    }

    /// What the person does in the panel: a colour, heard only while it is open.
    func pick(_ ink: AnnotationInk) { onPick?(ink) }

    /// A message that was on its way when the panel was put away.
    func lateDelivery(_ ink: AnnotationInk) { last?(ink) }
}

/// **The wheel's panel is asked for with the ink the editor has and under no pop-over, a colour from it is the editor's colour like a
/// swatch's, and it is sent away with the overlay.** The panel is one the whole app shares, so the overlay that opened it is the one that puts it away.
@MainActor
final class TheAllColoursPanelIsAskedAndSentAwayTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private let area = CGRect(x: 300, y: 100, width: 400, height: 300)

    private func build(panel: FakeColourPanel, store: NamespacedStore? = nil, release: Bool = true) throws -> DisplayID {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store, colourPanel: panel) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        if release {
            built.mouseDown(on: id, at: area.origin, flags: [])
            built.mouseDragged(on: id, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
            built.mouseUp(on: id)
        }
        return id
    }

    func testTheWheelClosesThePopoverAndAsksForThePanelWithTheCurrentInk() throws {
        let panel = FakeColourPanel()
        _ = try build(panel: panel)
        overlay?.perform(.tool(.pen))
        overlay?.perform(.color(.orange))
        overlay?.perform(.colours(anchorX: 100))
        XCTAssertTrue(overlay?.coloursAreOpen == true, "control: the pop-over is open")
        XCTAssertTrue(panel.opened.isEmpty, "control: nothing asked yet")
        overlay?.perform(.allColours)
        XCTAssertFalse(overlay?.popoverIsOpen == true, "the pop-over stayed open under the panel")
        XCTAssertEqual(panel.opened, [.orange], "the panel is not shown on the ink the editor has")
        XCTAssertTrue(panel.isOpen)
        XCTAssertEqual(panel.closed, 0, "the overlay put the panel away as it opened it")
    }

    func testWithNoColourPickedThePanelShowsTheToolsOwnDefault() throws {
        let panel = FakeColourPanel()
        _ = try build(panel: panel)
        overlay?.perform(.tool(.highlighter))
        overlay?.perform(.allColours)
        XCTAssertEqual(panel.opened.count, 1)
        XCTAssertEqual(panel.opened.first, overlay?.palette.style.ink(for: .highlighter), "not the ink the highlighter is drawn in")
        XCTAssertNotEqual(panel.opened.first, AnnotationInk.black, "control: the highlighter's own default is not a stand-in")
    }

    func testAColourFromThePanelIsTheToolInHandsAloneAndIsKept() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let panel = FakeColourPanel()
        let id = try build(panel: panel, store: store)
        overlay?.perform(.tool(.pen))
        overlay?.perform(.color(.orange))
        overlay?.perform(.tool(.rectangle))
        overlay?.perform(.allColours)
        let picked = try XCTUnwrap(AnnotationInk(red: 0.2, green: 0.4, blue: 0.6))
        panel.pick(picked)
        XCTAssertEqual(overlay?.palette.style.color, picked)
        XCTAssertEqual(EditorMemory.read(store).style(for: .rectangle).color, picked, "kept for the next editor")
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, .orange, "the Pen was orange first and the panel's colour took it from the Pen")
        XCTAssertNil(EditorMemory.read(store).style(for: .line).color, "the panel's colour reached the Line")
        overlay?.mouseDown(on: id, at: CGPoint(x: 350, y: 150), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 450, y: 250), flags: [])
        overlay?.mouseUp(on: id)
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(layers.first?.style.color, picked, "the object is not in the panel's colour")
    }

    func testAPickDoesNotCloseThePanelAndTheNextOneArrivesToo() throws {
        let panel = FakeColourPanel()
        _ = try build(panel: panel)
        overlay?.perform(.allColours)
        let first = try XCTUnwrap(AnnotationInk(red: 0.1, green: 0.2, blue: 0.3))
        let second = try XCTUnwrap(AnnotationInk(red: 0.9, green: 0.8, blue: 0.7))
        panel.pick(first)
        XCTAssertTrue(panel.isOpen, "a pick put the panel away: the wheel is dragged through colours")
        panel.pick(second)
        XCTAssertEqual(overlay?.palette.style.color, second)
    }

    func testTheOverlaysCloseSendsThePanelAway() throws {
        let panel = FakeColourPanel()
        _ = try build(panel: panel)
        overlay?.perform(.allColours)
        XCTAssertTrue(panel.isOpen)
        overlay?.close()
        XCTAssertGreaterThanOrEqual(panel.closed, 1, "the overlay ended and the panel is still up over the desktop")
        XCTAssertFalse(panel.isOpen)
        panel.pick(.red)
        XCTAssertNil(overlay?.palette.style.color, "a pick after the close reached the editor")
    }

    func testAPickThatWasOnItsWayWhenTheEditorEndedChangesNothingAndDoesNotCrash() throws {
        let panel = FakeColourPanel()
        _ = try build(panel: panel)
        overlay?.perform(.allColours)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(results.count, 1)
        overlay?.close()
        panel.lateDelivery(.red)
        XCTAssertEqual(results.count, 1, "a late pick finished the overlay a second time")
        overlay = nil
        panel.lateDelivery(.blue)
    }

    func testAskingTwiceHandsOverTheLatestAndAPickIsHeardOnce() throws {
        let panel = FakeColourPanel()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        _ = try build(panel: panel, store: store)
        overlay?.perform(.color(.red))
        overlay?.perform(.allColours)
        overlay?.perform(.color(.blue))
        overlay?.perform(.allColours)
        XCTAssertEqual(panel.opened, [.red, .blue], "the second ask is on the ink the editor has by then")
        panel.pick(.green)
        XCTAssertEqual(overlay?.palette.style.color, .green)
        panel.pick(.green)
        XCTAssertEqual(overlay?.palette.style.color, .green)
    }

    func testWithNoEditOpenTheWheelAsksForNothing() throws {
        let panel = FakeColourPanel()
        _ = try build(panel: panel, release: false)
        overlay?.perform(.allColours)
        XCTAssertTrue(panel.opened.isEmpty, "a panel was opened over an overlay with no editor, whose pick has nowhere to go")
        XCTAssertFalse(panel.isOpen)
    }

    func testTheWheelOpensWhileTheEyedropperIsOnAndPutsItDown() throws {
        let panel = FakeColourPanel()
        let id = try build(panel: panel)
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.perform(.eyedropper)
        overlay?.perform(.allColours)
        XCTAssertEqual(panel.opened.count, 1)
        overlay?.mouseMoved(on: id, at: CGPoint(x: 400, y: 200))
        XCTAssertNil(view.loupeReading, "the eyedropper stayed on under the panel")
    }

    func testNoTestOpensTheRealPanelNoteThatTheDefaultIsTheRealOne() throws {
        // The guard of the guard: the overlay's own default is the real panel, so a construction that does not name a fake is what
        // would open it. Every overlay of the two files of this stage names one.
        for name in ["TheAllColoursPanelIsAskedAndSentAwayTests", "ThePipettePicksTheFrozenPixelNotTheLayersTests"] {
            let text = try String(contentsOfFile: #filePath.replacingOccurrences(of: "TheAllColoursPanelIsAskedAndSentAwayTests", with: name), encoding: .utf8)
            let constructions = text.components(separatedBy: "CaptureOverlay(freeze:").count - 1
            let named = text.components(separatedBy: "colourPanel: ").count - 1
            XCTAssertGreaterThan(constructions, 0, "\(name): control: the file builds overlays")
            XCTAssertEqual(constructions, named, "\(name): an overlay is built without naming its colour panel")
        }
    }
}

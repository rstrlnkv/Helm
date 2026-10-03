import AppKit
import CoreGraphics
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Screenshots_UI

/// **The capsule over the thumbnail offers what is true of this shot, and each cell does what it says.** Show in
/// Finder only for a shot that has a file; Pin only while `PinEntry.isOffered`; nothing at all while the result is not
/// in (Copy and Reveal need what was written), nor while the pointer is away; the ✕ last, always, once.
///
/// Asked twice: by the cells the capsule is built from (`ShotCapsule.cells`, the one list the view reads) and by the
/// controls a rendered tree really holds, so a list that is right and a view that ignores it are both caught.
///
/// Total failure of the subject prints: a Show in Finder on a shot with no file (a button that opens nothing), a Pin
/// that is on the screen while the entry says it is not, a capsule on a working thumbnail, a Pin that opens a window
/// of the reduced copy or leaves a toast standing over its own pin.
@MainActor
final class TheShotsCapsuleOffersOnlyWhatIsTrueTests: XCTestCase {

    private var toasts: [ShotToast] = []
    private let clock = StepClock()

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        clock.finish()
        super.tearDown()
    }

    private func made() -> ShotToast {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        return toast
    }

    // MARK: The cells

    func testTheCellsOfEveryCombinationInTheirOrder() {
        XCTAssertEqual(ShotCapsule.cells(hasFile: false, pinOffered: false), [.copy, .close])
        XCTAssertEqual(ShotCapsule.cells(hasFile: true, pinOffered: false), [.copy, .reveal, .close])
        XCTAssertEqual(ShotCapsule.cells(hasFile: false, pinOffered: true), [.copy, .pin, .close])
        XCTAssertEqual(ShotCapsule.cells(hasFile: true, pinOffered: true), [.copy, .reveal, .pin, .close])
    }

    /// Whatever the two answers are, Copy opens the list, the ✕ closes it and each cell stands once.
    func testCopyFirstCloseLastAndNobodyTwice() {
        for hasFile in [false, true] {
            for pinOffered in [false, true] {
                let cells = ShotCapsule.cells(hasFile: hasFile, pinOffered: pinOffered)
                XCTAssertEqual(cells.first, .copy, "file \(hasFile), pin \(pinOffered)")
                XCTAssertEqual(cells.last, .close, "file \(hasFile), pin \(pinOffered)")
                XCTAssertEqual(Set(cells).count, cells.count, "a cell stands twice: \(cells)")
                XCTAssertEqual(cells.contains(.reveal), hasFile, "Show in Finder and the file disagree")
                XCTAssertEqual(cells.contains(.pin), pinOffered, "Pin and the entry disagree")
            }
        }
    }

    /// The defaults read the tree's own switch: with the entry off, no Pin is offered whatever else is true.
    func testTheDefaultFollowsThePinEntry() {
        for hasFile in [false, true] {
            XCTAssertEqual(ShotCapsule.cells(hasFile: hasFile), ShotCapsule.cells(hasFile: hasFile, pinOffered: PinEntry.isOffered))
            XCTAssertEqual(ShotCapsule.cells(hasFile: hasFile).contains(.pin), PinEntry.isOffered)
        }
    }

    // MARK: What the render holds

    private func controls(_ content: ShotToastModel.Content, hovering: Bool) -> Int {
        ShotToastRig.controls(content, hovering: hovering)
    }

    func testTheRenderedCapsuleHoldsTheCellsOfTheShotAndOnlyWhilePointed() throws {
        let image = try ShotToastRig.picture()
        let file = try ShotToastRig.realFile(self)
        let withFile = ShotCapsule.cells(hasFile: true).count
        let withoutFile = ShotCapsule.cells(hasFile: false).count
        XCTAssertEqual(controls(.picture(image, caption: "x", file: file), hovering: true), withFile,
                       "the capsule of a saved shot draws other cells than its list")
        XCTAssertEqual(controls(.picture(image, caption: "x", file: nil), hovering: true), withoutFile,
                       "the capsule of a clipboard-only shot draws other cells than its list")
        XCTAssertGreaterThan(withFile, withoutFile, "the control: a file adds a cell")
        XCTAssertEqual(controls(.picture(image, caption: "x", file: file), hovering: false), 0, "the capsule is up with no pointer over")
        XCTAssertEqual(controls(.picture(image, caption: nil, file: nil), hovering: true), 0,
                       "a working thumbnail offers controls whose result is not in")
    }

    // MARK: What each cell does

    func testCopyAsksTheOwnerAndPinAsksNobodyWithoutAWindow() throws {
        let toast = made()
        var copies = 0, pins = 0
        toast.onCopy = { copies += 1 }
        toast.onPin = { _, _ in pins += 1 }
        toast.showDone(try ShotToastRig.picture(), caption: "x", file: nil)
        toast.model.copy()
        XCTAssertEqual(copies, 1)
        toast.model.pin()
        XCTAssertEqual(pins, 0, "a pin opened with no thumbnail on a window to say where")
        XCTAssertNotNil(toast.model.content, "a pin that could not open took the toast down")
    }

    /// The pin is the full picture (read back from the file), where the thumbnail stands, and the toast goes.
    func testPinOpensTheFullPictureAtTheThumbnailAndTheToastGoes() throws {
        let toast = made()
        let folder = scratchDirectory("capsule-pin")
        let full = try ShotToastRig.picture(width: 1200, height: 700)
        let file = try ShotToastRig.writePNG(full, in: folder)
        toast.showDone(full, caption: "Saved", file: file)
        let mount = MountedRender(ShotToastView(model: toast.model), width: ShotToast.width, height: 300, appearance: .aqua)
        mount.settle(20)
        XCTAssertNotNil(toast.model.anchor, "the thumbnail's view never reached a window: no pin can be placed")
        var pinned: [(CGImage, CGRect)] = []
        toast.onPin = { pinned.append(($0, $1)) }
        toast.model.pin()
        XCTAssertEqual(pinned.count, 1)
        XCTAssertEqual(pinned.first?.0.width, 1200, "the pin is the thumbnail's reduced copy")
        XCTAssertEqual(pinned.first?.0.height, 700)
        XCTAssertGreaterThan(pinned.first?.1.width ?? 0, 0)
        XCTAssertNil(toast.model.content, "the toast stayed up over its own pin")
    }

    /// The file was removed before the pin re-read it: nothing opens, and the toast is not taken down for it.
    func testPinOfAFileThatWentOpensNothingAndKeepsTheToast() throws {
        let toast = made()
        let folder = scratchDirectory("capsule-pin-gone")
        let full = try ShotToastRig.picture()
        let file = try ShotToastRig.writePNG(full, in: folder)
        toast.showDone(full, caption: "Saved", file: file)
        let mount = MountedRender(ShotToastView(model: toast.model), width: ShotToast.width, height: 300, appearance: .aqua)
        mount.settle(20)
        try FileManager.default.removeItem(at: file)
        var pins = 0
        toast.onPin = { _, _ in pins += 1 }
        toast.model.pin()
        XCTAssertEqual(pins, 0, "a pin opened from a file that is gone")
        XCTAssertNotNil(toast.model.content, "the toast went for a pin that did not open")
        XCTAssertNil(toast.fullPicture(), "a gone file read back as a picture")
    }

    func testTheFullPictureIsHeldOnlyForAShotWithNoFile() throws {
        let toast = made()
        let folder = scratchDirectory("capsule-full")
        let full = try ShotToastRig.picture(width: 900, height: 500)
        toast.showDone(full, caption: "Copied", file: nil)
        XCTAssertEqual(toast.fullPicture()?.width, 900, "a clipboard-only shot lost its picture")
        toast.showDone(full, caption: "Saved", file: try ShotToastRig.writePNG(full, in: folder))
        XCTAssertNil(toast.model.full, "a saved shot holds its full picture in memory as well as in its file")
        XCTAssertEqual(toast.fullPicture()?.width, 900, "a saved shot was not read back from its file")
        toast.showWorking(full)
        XCTAssertNil(toast.fullPicture(), "a working thumbnail has a full picture to hand over")
        toast.dismiss()
        XCTAssertNil(toast.fullPicture(), "a dismissed toast still holds the picture")
    }

    /// A refusal has no picture to copy or pin.
    func testARefusalHasNoPictureToCopyOrPin() throws {
        let toast = made()
        toast.showDone(try ShotToastRig.picture(), caption: "Copied", file: nil)
        toast.showRefusal(.pasteboard)
        XCTAssertNil(toast.fullPicture(), "a refusal kept the last shot's picture for a Copy")
        XCTAssertNil(toast.model.full)
    }
}

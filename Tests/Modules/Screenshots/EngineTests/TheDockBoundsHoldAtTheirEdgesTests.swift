import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// The edges of `DockStrip.placement` that its own tests stand well inside of: the
/// 8 pt floor, the half-on-a-display rule, displays with negative CG origins, a Dock on
/// a side edge, and the window capture refusing for a Dock drawn alone. Each boundary
/// is asserted from both sides, because a bound proven from one side only survives
/// being moved in the other direction.
final class TheDockBoundsHoldAtTheirEdgesTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let strip = CGRect(x: 0, y: 908, width: 1512, height: 74)

    // MARK: - The floor, from both sides

    func testTheFloorIsEightPointsExactly() {
        let below = CGRect(x: 216, y: 904, width: 7.9, height: 68)
        let at = CGRect(x: 216, y: 904, width: 8, height: 68)
        XCTAssertEqual(DockStrip.placement(.bounds(below), displays: [Self.display], strip: Self.strip),
                       DockPlacement(rect: Self.strip, drawnAlone: false), "a sliver under the floor was taken as the Dock")
        XCTAssertEqual(DockStrip.placement(.bounds(at), displays: [Self.display], strip: Self.strip),
                       DockPlacement(rect: at, drawnAlone: true), "bounds at the floor were refused")
        let flat = CGRect(x: 216, y: 904, width: 1080, height: 7.9)
        XCTAssertEqual(DockStrip.placement(.bounds(flat), displays: [Self.display], strip: Self.strip)?.drawnAlone, false)
    }

    func testAnInfiniteRectangleIsNotARectangle() {
        let rect = CGRect(x: 216, y: 904, width: CGFloat.infinity, height: 68)
        XCTAssertEqual(DockStrip.placement(.bounds(rect), displays: [Self.display], strip: Self.strip),
                       DockPlacement(rect: Self.strip, drawnAlone: false))
    }

    // MARK: - Half on a display, from both sides

    func testHalfOnADisplayIsShownAndLessIsHidden() {
        // 100 pt tall at the bottom edge (982): 50 pt on is half, 49 pt on is not.
        let half = CGRect(x: 216, y: 932, width: 1080, height: 100)
        let less = CGRect(x: 216, y: 933, width: 1080, height: 100)
        let most = CGRect(x: 216, y: 900, width: 1080, height: 100)
        XCTAssertEqual(DockStrip.placement(.bounds(half), displays: [Self.display], strip: Self.strip)?.rect, half)
        XCTAssertNil(DockStrip.placement(.bounds(less), displays: [Self.display], strip: Self.strip),
                     "a Dock mostly off the display was listed")
        XCTAssertEqual(DockStrip.placement(.bounds(most), displays: [Self.display], strip: Self.strip)?.rect, most,
                       "a Dock mostly on the display was taken as hidden")
    }

    // MARK: - Displays with negative CG origins, and a side Dock

    func testADockOnADisplayAboveAndLeftOfTheMainOneIsShown() {
        let aboveLeft = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let rect = CGRect(x: -1500, y: -80, width: 1000, height: 68)
        let placement = DockStrip.placement(.bounds(rect), displays: [Self.display, aboveLeft], strip: nil)
        XCTAssertEqual(placement, DockPlacement(rect: rect, drawnAlone: true))
        // The same rectangle with only the main display known is off every display.
        XCTAssertNil(DockStrip.placement(.bounds(rect), displays: [Self.display], strip: nil))
    }

    func testASideDockIsPickedAtItsOwnBounds() {
        let left = CGRect(x: 4, y: 200, width: 68, height: 580)
        let placement = DockStrip.placement(.bounds(left), displays: [Self.display], strip: nil)
        XCTAssertEqual(placement, DockPlacement(rect: left, drawnAlone: true))
        let raw = [RawWindow(number: 20, layer: WindowPick.dockLevel, ownerPID: 70, ownerName: "Dock",
                             frame: Self.display, ownedByDock: true)]
        let windows = WindowListing.visible(raw, excluding: 999, dock: placement)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 30, y: 500), in: windows)?.id, 20)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 30, y: 100), in: windows), "the side strip above the Dock was picked")
    }

    // MARK: - The Dock drawn alone, when the system's window capture refuses

    private func dockFreeze() -> Freeze {
        let list = CGRect(x: 216, y: 904, width: 1080, height: 68)
        let windows = [FrozenWindow(id: 20, frame: list, layer: WindowPick.dockLevel, ownerName: "Dock", drawnAlone: true)]
        let frame = FrozenDisplay(id: DisplayID(1), frame: Self.display, scale: 1,
                                  image: makeImage(width: 1512, height: 982, red: 255))
        return Freeze(displays: [.image(frame)], windows: windows)
    }

    func testADeniedDockCaptureIsNoPermissionLikeAnyWindow() async {
        let rig = Rig(home: scratchDirectory("shots-dock-denied"))
        rig.capture.windows = [20: .denied]
        guard case .refused(let why) = await rig.session.window(20, in: dockFreeze()) else {
            return XCTFail("a withdrawn grant produced a picture")
        }
        XCTAssertEqual(rig.capture.windowCalls, 1)
        XCTAssertEqual(why, .noPermission)
    }

    func testAFailedDockCaptureIsACutAtTheBounds() async {
        let rig = Rig(home: scratchDirectory("shots-dock-failed"))
        rig.capture.windows = [20: .failed]
        guard case .image(let picture) = await rig.session.window(20, in: dockFreeze()) else {
            return XCTFail("refused")
        }
        XCTAssertEqual(rig.capture.windowCalls, 1)
        XCTAssertEqual(picture.width, 1080)
        XCTAssertEqual(picture.height, 68)
    }

    // MARK: - Optional by design: never prompts, never logs the absence

    func testTheRealPortReadsTrustWithoutPromptingAndLogsNothing() throws {
        let path = "Sources/Modules/Screenshots/Engine/SystemPorts.swift"
        let code = SwiftSource.code(try RepoSource.text(of: path))
        guard let start = code.range(of: "struct SystemDockBounds") else {
            return XCTFail("SystemDockBounds is not in \(path)")
        }
        let rest = code[start.upperBound...]
        let end = rest.range(of: "\n}")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]
        // The subject first: the non-prompting trust reading is there and is the guard.
        XCTAssertTrue(body.contains("guard AXIsProcessTrusted() else { return .notTrusted }"),
                      "the trust reading moved; re-read this check")
        XCTAssertFalse(body.contains("HelmLog"), "the Dock bounds port logs")
        XCTAssertFalse(body.contains("print("), "the Dock bounds port prints")
        // The one reading that is logged is logged where the port's answer is placed:
        // under the module's own category, as a fixed sentence that can name nothing.
        // `testADockThatDidNotAnswerIsTheStripAndIsReported` proves the callback fires
        // for `.timedOut` alone; this proves the callback the real path passes is a log.
        // Literals kept here: the subject is the sentence itself.
        let kept = SwiftSource.uncommented(try RepoSource.text(of: path))
        guard let placing = kept.range(of: "func dockPlacement(") else {
            return XCTFail("dockPlacement is not in \(path); re-read this check")
        }
        let after = kept[placing.upperBound...]
        let placingBody = after[..<(after.range(of: "\n    }\n")?.lowerBound ?? after.endIndex)]
        guard let call = placingBody.range(of: "DockStrip.placement(entries:") else {
            return XCTFail("the real path no longer places through DockStrip.placement(entries:)")
        }
        let callback = placingBody[call.upperBound...]
        XCTAssertTrue(callback.contains("HelmLog.shared.warn(ScreenshotsEngine.moduleID, \""),
                      "a Dock that did not answer is not logged under the module's category")
        XCTAssertFalse(callback.contains("\\("), "the timeout line interpolates something")
        for read in try SwiftSource.code(under: "Sources/Modules/Screenshots") {
            XCTAssertFalse(read.text.contains("AXIsProcessTrustedWithOptions"),
                           "\(read.path) calls the prompting trust reading")
        }
    }
}

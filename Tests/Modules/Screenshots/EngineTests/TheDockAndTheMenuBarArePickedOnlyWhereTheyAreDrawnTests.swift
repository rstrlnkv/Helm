import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// The list `CGWindowListCopyWindowInfo` gave on the owner's Mac, front to back:
/// the menu bar (layer 24, 1512x33) is its own rect and a target; the Dock keeps a
/// full-screen transparent sheet at layer 20 above every normal window, of which
/// only the strip (measured: `visibleFrame` gives up 74 points at the bottom) is
/// drawn. A rule of "layer 0 and above" picked the Dock at every point; a rule of
/// "never" refused what macOS offers. The ports file lists the Dock at the strip.
final class TheDockAndTheMenuBarArePickedOnlyWhereTheyAreDrawnTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    static let strip = CGRect(x: 0, y: 908, width: 1512, height: 74)
    static let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 33)

    private func owners(extra: [FrozenWindow] = [], strip: CGRect? = TheDockAndTheMenuBarArePickedOnlyWhereTheyAreDrawnTests.strip) -> [FrozenWindow] {
        extra
            + [FrozenWindow(id: 24, frame: Self.menuBar, layer: 24, ownerName: "Window Server")]
            + (strip.map { [FrozenWindow(id: 20, frame: $0, layer: 20, ownerName: "Dock")] } ?? [])
            + [
                FrozenWindow(id: 101, frame: CGRect(x: 100, y: 80, width: 700, height: 500), layer: 0, ownerName: "Просмотр"),
                FrozenWindow(id: 102, frame: CGRect(x: 500, y: 300, width: 900, height: 600), layer: 0, ownerName: "Finder"),
                FrozenWindow(id: 103, frame: CGRect(x: 50, y: 400, width: 600, height: 450), layer: 0, ownerName: "Музыка"),
            ]
    }

    func testTheLevelsAreTheSystemsAndNotLiterals() {
        XCTAssertEqual(WindowPick.menuBarLevel, 24)
        XCTAssertEqual(WindowPick.dockLevel, 20)
    }

    func testThePointerInsideTheDockStripPicksTheDock() {
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 950), in: owners())?.id, 20)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 5, y: 975), in: owners())?.id, 20)
    }

    func testThePointerInsideTheMenuBarPicksTheMenuBar() {
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 15), in: owners())?.id, 24)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 1500, y: 2), in: owners())?.id, 24)
    }

    func testJustOutsideTheStripAndTheBarThePickIsWhatLiesBelow() {
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 1450, y: 907), in: owners()), "the Dock sheet's rect leaked above the strip")
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 1450, y: 34), in: owners()))
    }

    func testAPointOverANormalWindowPicksThatWindow() {
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 200, y: 150), in: owners())?.id, 101)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 1200, y: 800), in: owners())?.id, 102)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 100, y: 700), in: owners())?.id, 103)
    }

    func testAPointOverOnlyTheDesktopPicksNothing() {
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 1450, y: 100), in: owners()))
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 1450, y: 500), in: owners()))
    }

    func testEveryPointIsPickedAsADrawnThingOrNotAtAll() {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: 1512, by: 37) {
            for y in stride(from: 0, to: 982, by: 29) {
                let point = CGPoint(x: x, y: y)
                let id = WindowPick.window(at: point, in: owners())?.id
                if id == 20 { XCTAssertTrue(Self.strip.contains(point), "the Dock at \(x),\(y)") }
                if id == 24 { XCTAssertTrue(Self.menuBar.contains(point), "the menu bar at \(x),\(y)") }
                if let id { seen.insert(id) }
            }
        }
        XCTAssertEqual(seen, [20, 24, 101, 102, 103])
    }

    func testAFloatingApplicationPanelOverTheDockStripWins() {
        let panel = FrozenWindow(id: 150, frame: CGRect(x: 600, y: 900, width: 200, height: 80),
                                 layer: Int(CGWindowLevelForKey(.floatingWindow)), ownerName: "Palette")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 650, y: 940), in: owners(extra: [panel]))?.id, 150)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 10, y: 940), in: owners(extra: [panel]))?.id, 20)
    }

    func testAnApplicationWindowBehindTheDockIsCoveredByTheStrip() {
        let low = FrozenWindow(id: 140, frame: CGRect(x: 0, y: 700, width: 1512, height: 282), layer: 0, ownerName: "Finder")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 950), in: owners() + [low])?.id, 20)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 1450, y: 800), in: owners() + [low])?.id, 140)
    }

    func testAStatusLevelItemIsNotPickable() {
        let status = FrozenWindow(id: 160, frame: CGRect(x: 120, y: 100, width: 200, height: 300),
                                  layer: Int(CGWindowLevelForKey(.statusWindow)), ownerName: "SomeMenuExtra")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [status]))?.id, 101)
    }

    func testOnlyTheWindowServerIsTheMenuBar() {
        let impostor = FrozenWindow(id: 161, frame: CGRect(x: 120, y: 100, width: 200, height: 300),
                                    layer: WindowPick.menuBarLevel, ownerName: "SomeApp")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [impostor]))?.id, 101)
    }

    func testTheDockIsRecognisedByItsLevelWhateverItsNameIsCalled() {
        let localised = FrozenWindow(id: 171, frame: Self.strip, layer: WindowPick.dockLevel, ownerName: "程序坞")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 950), in: [localised])?.id, 171)
    }

    func testADockNamedWindowAtAnOrdinaryLevelIsAnOrdinaryWindow() {
        let window = FrozenWindow(id: 170, frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, ownerName: "Dock")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 10, y: 10), in: [window])?.id, 170)
    }

    // MARK: - The raw list, reframed

    private static let sheet = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func raw(dock: Bool = true) -> [RawWindow] {
        [RawWindow(number: 24, layer: 24, ownerPID: 1, ownerName: "Window Server", frame: Self.menuBar)]
            + (dock ? [RawWindow(number: 20, layer: 20, ownerPID: 70, ownerName: "Dock", frame: Self.sheet, ownedByDock: true)] : [])
            + [RawWindow(number: 101, layer: 0, ownerPID: 300, ownerName: "Finder",
                         frame: CGRect(x: 100, y: 80, width: 700, height: 500))]
    }

    /// The sheet is in the raw list and there is no strip: the pick over the whole
    /// display must be the pick with no Dock, and the sheet must not be listed.
    func testADockThatHidesItselfIsNeverListedAndNeverPicked() {
        let listed = WindowListing.visible(raw(), excluding: 999, dockStrip: nil)
        XCTAssertEqual(listed.map(\.id), [24, 101], "the Dock's sheet was listed with no strip")
        for x in stride(from: 0, to: 1512, by: 37) {
            for y in stride(from: 0, to: 982, by: 29) {
                XCTAssertNotEqual(WindowPick.window(at: CGPoint(x: x, y: y), in: listed)?.id, 20, "the Dock at \(x),\(y)")
            }
        }
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 700, y: 950), in: listed))
    }

    func testTheDockIsListedAtTheStripAndNotAtTheSheet() {
        let dock = WindowListing.visible(raw(), excluding: 999, dockStrip: Self.strip).first { $0.id == 20 }
        XCTAssertEqual(dock?.frame, Self.strip)
        XCTAssertEqual(dock?.layer, WindowPick.dockLevel)
        XCTAssertEqual(dock?.ownerName, "Dock")
        let listed = WindowListing.visible(raw(), excluding: 999, dockStrip: Self.strip)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 1450, y: 500), in: listed), "the sheet's rect is back")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 950), in: listed)?.id, 20)
    }

    /// Several windows at the Dock's level: only the Dock's own is reframed to the
    /// strip, another process's window at that level is dropped, and a second
    /// Dock-owned window does not become a second strip.
    func testOnlyTheDocksOwnWindowAtItsLevelIsReframed() {
        let stranger = RawWindow(number: 31, layer: 20, ownerPID: 400, ownerName: "Other", frame: CGRect(x: 10, y: 10, width: 300, height: 300))
        let second = RawWindow(number: 32, layer: 20, ownerPID: 70, ownerName: "Dock", frame: Self.sheet, ownedByDock: true)
        let listed = WindowListing.visible([stranger] + raw() + [second], excluding: 999, dockStrip: Self.strip)
        XCTAssertEqual(listed.map(\.id), [24, 20, 101])
        XCTAssertEqual(listed.first { $0.id == 20 }?.frame, Self.strip)
        XCTAssertEqual(WindowListing.visible([stranger], excluding: 999, dockStrip: nil), [])
    }

    func testHelmsOwnAndTransparentWindowsAreLeftOutAndTheRestKeepTheirFrames() {
        let mine = RawWindow(number: 50, layer: 0, ownerPID: 999, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let clear = RawWindow(number: 51, layer: 0, ownerPID: 300, alpha: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let listed = WindowListing.visible([mine, clear] + raw(), excluding: 999, dockStrip: Self.strip)
        XCTAssertEqual(listed.map(\.id), [24, 20, 101])
        XCTAssertEqual(listed.last?.frame, CGRect(x: 100, y: 80, width: 700, height: 500))
    }

    func testTheStripIsReadFromTheFirstDisplayThatGivesUpRoomAndNotFromLaterOnes() {
        let first = (frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visible: CGRect(x: 0, y: 0, width: 1000, height: 770))
        let second = (frame: CGRect(x: 1000, y: 0, width: 1000, height: 800), visible: CGRect(x: 1000, y: 60, width: 1000, height: 710))
        let third = (frame: CGRect(x: 2000, y: 0, width: 1000, height: 800), visible: CGRect(x: 2000, y: 90, width: 1000, height: 680))
        XCTAssertEqual(DockStrip.rect(displays: [first, second, third]), CGRect(x: 1000, y: 740, width: 1000, height: 60))
        XCTAssertEqual(DockStrip.rect(displays: [first, third, second]), CGRect(x: 2000, y: 710, width: 1000, height: 90))
        XCTAssertNil(DockStrip.rect(displays: [first]))
        XCTAssertNil(DockStrip.rect(displays: []))
    }

    func testAWindowJustAboveTheFloatingLevelIsNotPickable() {
        let above = FrozenWindow(id: 151, frame: CGRect(x: 120, y: 100, width: 200, height: 300),
                                 layer: WindowPick.highestLevel + 1, ownerName: "Palette")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [above]))?.id, 101)
    }

    func testAWindowWithNoOwnerNameIsStillAnApplicationWindow() {
        let nameless = FrozenWindow(id: 180, frame: CGRect(x: 120, y: 100, width: 200, height: 300), layer: 0)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [nameless]))?.id, 180)
    }

    func testATinyOrOffScreenWindowInFrontIsPassedOver() {
        let sliver = FrozenWindow(id: 190, frame: CGRect(x: 148, y: 148, width: WindowPick.smallest - 1,
                                                         height: WindowPick.smallest - 1),
                                  layer: 0, ownerName: "Ghost")
        let away = FrozenWindow(id: 191, frame: CGRect(x: -5000, y: -5000, width: 800, height: 600), layer: 0, ownerName: "Away")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [sliver, away]))?.id, 101)
    }

    // MARK: - The strip itself, from the measured numbers

    func testTheStripOnTheOwnersMacIsTheBottom74Points() {
        // Measured: frame 0,0,1512,982; visibleFrame 0,74,1512,875 (AppKit, origin bottom left).
        XCTAssertEqual(DockStrip.rect(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                      visible: CGRect(x: 0, y: 74, width: 1512, height: 875), primaryHeight: 982),
                       Self.strip)
    }

    func testTheStripOnTheSideEdges() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(DockStrip.rect(frame: frame, visible: CGRect(x: 60, y: 0, width: 940, height: 770), primaryHeight: 800),
                       CGRect(x: 0, y: 0, width: 60, height: 800))
        XCTAssertEqual(DockStrip.rect(frame: frame, visible: CGRect(x: 0, y: 0, width: 940, height: 770), primaryHeight: 800),
                       CGRect(x: 940, y: 0, width: 60, height: 800))
    }

    func testADisplayThatGivesUpNothingHasNoStrip() {
        let frame = CGRect(x: 767, y: 982, width: 2560, height: 1440)
        XCTAssertNil(DockStrip.rect(frame: frame, visible: frame, primaryHeight: 982))
        // Only the menu bar's inset at the top: not the Dock's.
        XCTAssertNil(DockStrip.rect(frame: frame, visible: CGRect(x: 767, y: 982, width: 2560, height: 1410), primaryHeight: 982))
    }

    func testAStripOnASecondDisplayIsInCGGlobalPoints() {
        // A display above the primary one: AppKit y 982 up, so CG y is negative.
        let frame = CGRect(x: 0, y: 982, width: 1000, height: 600)
        let strip = DockStrip.rect(frame: frame, visible: CGRect(x: 0, y: 1052, width: 1000, height: 530), primaryHeight: 982)
        XCTAssertEqual(strip, CGRect(x: 0, y: -600 + 530, width: 1000, height: 70))
    }

    // MARK: - What is cut

    func testTheDockPictureIsTheStripAndNotTheSheetAndNeverTheWindowCapture() async throws {
        let frame = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                  scale: 2, image: makeSplitImage(width: 200, height: 100))
        let freeze = Freeze(displays: [.image(frame)],
                            windows: [FrozenWindow(id: 20, frame: CGRect(x: 0, y: 40, width: 100, height: 10),
                                                   layer: WindowPick.dockLevel, ownerName: "Dock"),
                                      FrozenWindow(id: 24, frame: CGRect(x: 0, y: 0, width: 100, height: 5),
                                                   layer: WindowPick.menuBarLevel, ownerName: "Window Server")])
        let rig = Rig(home: scratchDirectory("shots-dock-strip"))
        rig.capture.windows = [20: .image(makeImage(width: 61, height: 41, green: 255)),
                               24: .image(makeImage(width: 61, height: 41, green: 255))]

        guard case .image(let dock) = await rig.session.window(20, in: freeze) else { return XCTFail("the Dock was refused") }
        XCTAssertEqual(dock.width, 200)
        XCTAssertEqual(dock.height, 20, "the Dock's picture is the 10-point strip at 2x, not the sheet")
        guard case .image(let bar) = await rig.session.window(24, in: freeze) else { return XCTFail("the menu bar was refused") }
        XCTAssertEqual(bar.height, 10)
        XCTAssertEqual(rig.capture.windowCalls, 0, "a system surface was asked for by id")
    }
}

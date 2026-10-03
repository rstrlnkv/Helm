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

/// **«⋯ → Share…» does what Done does first, then opens the system's sheet at the thumbnail of that shot, even with
/// the floating thumbnail off; the thumbnail stands while the sheet is open and counts down after it ends.** The
/// sheet is not opened here (`presentPicker` is the seam a test passes); what is asked is whether, when and for how
/// long, and what the toast does with a sheet in the way of the next shot, a refusal, a ✕ and a delegate that calls
/// twice, late or with nothing chosen.
///
/// The ports are named at construction and are this file's own. Clocks come through the seams (`ShotToast`'s `tick`,
/// `advance(by:)`); the lifetime sleeps on none, but two checks of an absence (the Return that opened no sheet, the
/// working thumbnail while the write is held) wait a short `grace` of the wall clock, and the thumbnail setting is off in every store but the one that says otherwise,
/// because the toast is built with no panel.
///
/// Total failure of the subject prints: a Share that saves nothing or twice, one that needs the thumbnail setting,
/// a sheet under a thumbnail that is counting down to its own end, or a request that survives a refusal and opens a
/// sheet on a shot that did not happen.
@MainActor
final class TheShareHandsOffFirstAndOpensAtTheShotTests: XCTestCase {

    private final class Board: ShotPasteboard, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var outcome = PasteOutcome.accepted
        var copies: Int { lock.withLock { count } }
        func refuse() { lock.withLock { outcome = .refused } }
        func copy(png: Data) -> PasteOutcome { lock.withLock { count += 1; return outcome } }
        func copy(pngs: [Data]) -> PasteOutcome { XCTFail("this test's board was never taught a group"); return .refused }
    }
    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var refusal: WriteRefusal?
        /// While set, a write waits at it: the shot is then still being written.
        let gate = DispatchSemaphore(value: 0)
        private var holding = false
        func hold() { lock.withLock { holding = true } }
        func release() { lock.withLock { holding = false }; gate.signal() }
        var written: Int { lock.withLock { count } }
        func refuse(_ reason: WriteRefusal) { lock.withLock { refusal = reason } }
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            if lock.withLock({ holding }) { gate.wait() }
            return lock.withLock {
                if let refusal { return .refused(refusal) }
                count += 1
                // Written for real: what leaves is asked of the file system.
                let url = folder.appendingPathComponent(base + "." + pathExtension)
                try? png.write(to: url)
                return .written(WrittenShot(url: url, reading: NoFile.reading))
            }
        }
    }
    private struct Frames: ScreenCapturing {
        let freeze: Freeze
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .frozen(freeze) }
        func window(_ id: UInt32, cursor: Bool) async -> WindowShot { .gone }
    }
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private struct NoShutter: ShutterPlaying { func play() {} }

    /// What the seam was asked: the sheets, and each one's delegate held here. The toast holds its own delegate for as
    /// long as its sheet stands; this list is for a test that calls the delegate after the toast let it go (that
    /// the picker's reference to its delegate is weak is the SDK's property, not measured here).
    private final class Opened {
        var pickers: [(NSSharingServicePicker, NSView)] = []
        var delegates: [NSSharingServicePickerDelegate] = []
    }

    private struct Rig {
        let controller: CaptureController
        let toast: ShotToast
        let board: Board, disk: Disk
        let opened: Opened
        let display: FrozenDisplay
        let overlays: Count
        let overlay: () -> CaptureOverlay?
    }
    private final class Count: @unchecked Sendable { var value = 0 }
    private final class OverlayBox { var overlay: CaptureOverlay? }

    private let clock = StepClock()
    private var held: CaptureOverlay?
    private var live: [CaptureController] = []
    private var toasts: [ShotToast] = []
    private var stands: [StandInThumbnail] = []

    override func tearDown() {
        AppLanguage.override = nil
        held?.close()
        held = nil
        for controller in live { controller.teardown() }
        live = []
        for toast in toasts { toast.dismiss() }
        toasts = []
        stands = []
        clock.finish()
        super.tearDown()
    }

    private func rig(thumbnail: Bool = false, target: SaveTarget = .desktop) throws -> Rig {
        let frames = try OverlayRig.frames()
        let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
        let board = Board(), disk = Disk(), opened = Opened()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(thumbnail, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = scratchDirectory("share-handoff")
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: disk, trash: NoTrash(), pasteboard: board,
                                     preferences: NoPreferences(), shutter: NoShutter(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let toast = ShotToastRig.toast(clock)
        toast.presentPicker = { picker, view in
            opened.pickers.append((picker, view))
            if let delegate = picker.delegate { opened.delegates.append(delegate) }
        }
        toasts.append(toast)
        let overlays = Count()
        let box = OverlayBox()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in
                                               overlays.value += 1
                                               box.overlay = overlay
                                               return overlay.build()
                                           },
                                           pins: PinBoard(present: { _ in }, screens: { [] }), toast: toast)
        live.append(controller)
        return Rig(controller: controller, toast: toast, board: board, disk: disk, opened: opened,
                   display: try XCTUnwrap(frames.first), overlays: overlays, overlay: { box.overlay })
    }

    private func anchored(_ toast: ShotToast) -> StandInThumbnail {
        let stand = StandInThumbnail()
        stands.append(stand)
        toast.model.anchor = stand.view
        return stand
    }

    private func bare(opened: Opened) -> ShotToast {
        let toast = ShotToastRig.toast(clock)
        toast.presentPicker = { picker, view in
            opened.pickers.append((picker, view))
            if let delegate = picker.delegate { opened.delegates.append(delegate) }
        }
        toasts.append(toast)
        return toast
    }

    private func picture() throws -> CGImage { try ShotToastRig.picture(width: 1200, height: 700) }

    private func press(_ rig: Rig) async throws -> CaptureOverlay {
        rig.controller.begin(.area)
        await waitUntil("the area press reached the overlay") { rig.overlays.value == 1 }
        let overlay = try XCTUnwrap(rig.overlay())
        held = overlay
        let id = rig.display.id
        overlay.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        overlay.mouseUp(on: id)
        return overlay
    }

    /// What the sheet's end says, as the system says it.
    private func endSheet(_ opened: Opened, choosing service: NSSharingService? = nil, at index: Int = 0) throws {
        let (picker, _) = opened.pickers[index]
        let delegate = try XCTUnwrap(opened.delegates.count > index ? opened.delegates[index] : nil, "the sheet was given no delegate to say it ended")
        delegate.sharingServicePicker?(picker, didChoose: service)
    }

    // MARK: The item

    /// Share… is the menu's last item whatever is chosen and whether or not the Pin is offered, is always enabled, is
    /// titled in every language, carries no key and sends the one exit the controller turns into a share.
    func testTheMenusShareItemIsLastEnabledKeylessAndSendsTheShareExit() throws {
        for pinOffered in [false, true] {
            for tool in [nil] + AnnotationTool.allCases.map({ Optional($0) }) {
                let model = EditorBarModel()
                model.show(tool: tool, style: AnnotationStyle(), canUndo: false, canRedo: false)
                guard case .action(let title, let action, let enabled, let on)? = EditorMenu.items(for: model, pinOffered: pinOffered).last else {
                    return XCTFail("the menu does not end with an action")
                }
                XCTAssertEqual(title, ScStr.share)
                XCTAssertEqual(action, .exit(.share))
                XCTAssertTrue(enabled, "Share… is off for tool \(String(describing: tool))")
                XCTAssertFalse(on)
            }
        }
        var sent: [EditorAction] = []
        let model = EditorBarModel()
        model.show(tool: .arrow, style: AnnotationStyle(), canUndo: false, canRedo: false)
        model.perform = { sent.append($0) }
        let menu = EditorMenu.make(for: model)
        menu.delegate?.menuNeedsUpdate?(menu)
        let item = try XCTUnwrap(menu.items.last)
        XCTAssertEqual(item.title, ScStr.share)
        XCTAssertEqual(item.keyEquivalent, "", "Share… has a key, and the menu gives none to the items below Save")
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertEqual(sent, [.exit(.share)])
        AppLanguage.each { language in
            XCTAssertFalse(ScStr.share.isEmpty, "\(language)")
            XCTAssertNotEqual(ScStr.share, ScStr.save, "\(language)")
        }
    }

    // MARK: Done first

    /// For each target: Share delivers exactly what Done delivers, and the thumbnail is there with the setting off.
    func testShareDeliversWhatDoneDeliversAndShowsTheThumbnailWithTheSettingOff() async throws {
        for target in SaveTarget.allCases {
            let done = try rig(target: target), share = try rig(target: target)
            await done.controller.handOff(CapturedShot(image: try picture(), kind: .area))
            await share.controller.handOff(CapturedShot(image: try picture(), kind: .area), thenShare: true)
            XCTAssertEqual(share.board.copies, done.board.copies, "\(target): Share copied differently from Done")
            XCTAssertEqual(share.disk.written, done.disk.written, "\(target): Share saved differently from Done")
            XCTAssertEqual(done.board.copies, 1)
            XCTAssertNil(done.toast.model.content, "\(target): the control: Done with the thumbnail off shows none")
            guard case .picture(_, let caption?, let file)? = share.toast.model.content else {
                XCTFail("\(target): Share with the setting off showed no thumbnail with its result: \(String(describing: share.toast.model.content))")
                continue
            }
            XCTAssertFalse(caption.isEmpty)
            XCTAssertEqual(file != nil, target.savesAFile, "\(target): the thumbnail's file and the target disagree")
            XCTAssertEqual(share.toast.model.full != nil, file == nil, "\(target): the picture is held exactly when there is no file")
        }
    }

    /// With the setting on, Share does not change what the thumbnail is; and Done without Share opens no sheet.
    func testOnlyShareOpensTheSheetAndTheSettingOnChangesNothingElse() async throws {
        let plain = try rig(thumbnail: true), share = try rig(thumbnail: true)
        _ = anchored(plain.toast)
        _ = anchored(share.toast)
        await plain.controller.handOff(CapturedShot(image: try picture(), kind: .area))
        await share.controller.handOff(CapturedShot(image: try picture(), kind: .area), thenShare: true)
        XCTAssertEqual(plain.opened.pickers.count, 0, "Done opened the sheet")
        XCTAssertEqual(share.opened.pickers.count, 1, "Share did not open the sheet once")
        XCTAssertEqual(share.toast.holds, [.sheet])
        XCTAssertNotNil(plain.toast.model.content)
        XCTAssertTrue(plain.toast.holds.isEmpty)
    }

    /// The exit itself, through the overlay: `.share` and `.confirm` deliver the same, and only `.share` asks for the sheet.
    func testTheOverlaysShareExitDeliversLikeReturnAndAsksForTheSheet() async throws {
        let share = try rig()
        _ = anchored(share.toast)
        let overlay = try await press(share)
        overlay.perform(.exit(.share))
        await waitUntil("the shared area was delivered") { share.opened.pickers.count == 1 }
        XCTAssertEqual(share.board.copies, 1)
        XCTAssertEqual(share.disk.written, 1)
        guard case .picture(_, _, _?)? = share.toast.model.content else { return XCTFail("no thumbnail of the shared shot") }
        await waitUntil("the controller let go") { !share.controller.isBusy }

        let confirm = try rig()
        _ = anchored(confirm.toast)
        confirm.controller.begin(.area)
        await waitUntil("the second press reached the overlay") { confirm.overlays.value == 1 }
        let second = try XCTUnwrap(confirm.overlay())
        let id = confirm.display.id
        second.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        second.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        second.mouseUp(on: id)
        second.perform(.exit(.confirm))
        await waitUntil("the confirmed area was delivered") { confirm.disk.written == 1 }
        await grace(0.2)
        XCTAssertEqual(confirm.opened.pickers.count, 0, "Return opened the sheet")
        XCTAssertEqual(confirm.board.copies, share.board.copies)
        second.close()
    }

    /// The working thumbnail, which stands while the write is in flight, is there for a Share with the setting off and
    /// is not there for a Done with it off.
    func testTheWorkingThumbnailStandsForAShareWithTheSettingOffAndForNothingElse() async throws {
        for sharing in [true, false] {
            let rig = try rig()
            rig.disk.hold()
            let shot = CapturedShot(image: try picture(), kind: .area)
            let task = Task { await rig.controller.handOff(shot, thenShare: sharing) }
            // The delivery is blocked in the write: what is on the screen now is what the person sees while it saves.
            await grace(0.3)
            var released = false
            defer { if !released { rig.disk.release() } }
            if sharing {
                guard case .picture(_, let caption, _)? = rig.toast.model.content else {
                    rig.disk.release(); released = true; await task.value
                    return XCTFail("Share with the setting off showed no thumbnail while the shot was being written")
                }
                XCTAssertNil(caption, "the result is not in and the thumbnail already has its caption")
            } else {
                XCTAssertNil(rig.toast.model.content, "Done with the setting off showed a thumbnail")
            }
            rig.disk.release(); released = true
            await task.value
        }
    }

    /// A failed write is not shared: the refusal is what is shown, and no sheet opens, anchor or not.
    func testARefusedWriteOpensNoSheetAndShowsTheRefusal() async throws {
        let rig = try rig()
        _ = anchored(rig.toast)
        rig.disk.refuse(.diskFull)
        await rig.controller.handOff(CapturedShot(image: try picture(), kind: .area), thenShare: true)
        XCTAssertEqual(rig.opened.pickers.count, 0, "a sheet opened on a shot that was not saved")
        guard case .refusal? = rig.toast.model.content else { return XCTFail("the refusal is not on the screen: \(String(describing: rig.toast.model.content))") }
        XCTAssertTrue(rig.toast.holds.isEmpty)
    }

    // MARK: The anchor and the order

    /// The thumbnail's view arrives after the result (a panel just ordered in): the sheet opens then, once.
    func testTheSheetOpensWhenTheViewArrivesAndOnlyOnce() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        XCTAssertEqual(opened.pickers.count, 0, "a sheet opened with no view to stand at")
        XCTAssertTrue(toast.holds.isEmpty, "a sheet that is not open holds the toast")
        let stand = anchored(toast)
        XCTAssertEqual(opened.pickers.count, 1)
        XCTAssertTrue(opened.pickers.first?.1 === stand.view, "the sheet is not at the thumbnail's own view")
        toast.model.anchor = stand.view
        toast.model.anchor = StandInThumbnail().view
        XCTAssertEqual(opened.pickers.count, 1, "the view arriving again opened the sheet again")
    }

    /// A request made before the result is in has nothing to share: the thumbnail's reduced copy is not offered.
    func testShareRequestedBeforeTheWriteResultOpensNothing() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.showWorking(try picture())
        toast.requestShare()
        XCTAssertEqual(opened.pickers.count, 0, "the sheet opened on a shot that has no file and no picture yet")
        XCTAssertTrue(toast.holds.isEmpty)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        XCTAssertEqual(opened.pickers.count, 1, "the control: the same toast opens the sheet once the result is in")
    }

    /// The shot was refused while the request waited for its view: no sheet may open later on the refusal.
    func testARefusalWhileTheRequestWaitsForItsViewCancelsTheRequest() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.showRefusal(.encoding)
        _ = anchored(toast)
        XCTAssertEqual(opened.pickers.count, 0, "a sheet opened over a refusal")
    }

    /// A shot that went before its view arrived leaves no request for the one after it.
    func testAShotThatWentTakesItsRequestWithIt() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.dismiss()
        toast.showDone(try picture(), caption: "Saved", file: nil)
        _ = anchored(toast)
        XCTAssertEqual(opened.pickers.count, 0, "the dismissed shot's request opened a sheet on the next shot")
    }

    // MARK: The countdown and the sheet

    func testTheCountdownStandsWhileTheSheetIsOpenAndRunsAfterItEnds() async throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.pointerIsOver = { false }
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        XCTAssertEqual(toast.holds, [.sheet])
        XCTAssertFalse(toast.advance(by: 2))
        XCTAssertEqual(toast.remaining, 5, "time passed under the sheet")
        for _ in 0..<40 { XCTAssertFalse(toast.advance(by: 100), "the toast went from under its own sheet") }
        XCTAssertEqual(toast.remaining, 5, "time passed under the sheet")
        try endSheet(opened)
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertEqual(toast.remaining, 0.5, "the countdown did not go on from where it stood")
        XCTAssertTrue(toast.advance(by: 0.5))
    }

    /// The same through the loop that really runs.
    func testTheLoopStandsUnderTheSheetAndEndsAfterIt() async throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.pointerIsOver = { false }
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        await waitUntil("the loop's first step") { self.clock.isWaiting }
        for _ in 0..<120 { await clock.step(self) }
        XCTAssertTrue(toast.model.shown, "the loop closed the panel under the open sheet")
        try endSheet(opened)
        var steps = 0
        while toast.model.shown, steps < 80 { await clock.step(self); steps += 1 }
        XCTAssertFalse(toast.model.shown, "the loop did not run after the sheet ended")
        XCTAssertEqual(steps, 50, "five seconds in tenths end on the fiftieth step, not the fifty-first")
    }

    /// Cancel is the delegate with nothing chosen; a service chosen is the same end.
    func testCancelAndAChoiceBothEndTheSheet() throws {
        let service = [NSSharingService.Name.sendViaAirDrop, .composeEmail, .addToSafariReadingList]
            .lazy.compactMap { NSSharingService(named: $0) }.first
        for choice in [Optional<NSSharingService>.none, service] {
            let opened = Opened()
            let toast = bare(opened: opened)
            _ = anchored(toast)
            toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
            XCTAssertEqual(toast.holds, [.sheet])
            try endSheet(opened, choosing: choice)
            XCTAssertTrue(toast.holds.isEmpty, "\(choice == nil ? "cancel" : "a choice") did not end the sheet")
        }
        XCTAssertNotNil(service, "no sharing service on this Mac to try the chosen path with")
    }

    /// The delegate speaks twice, or after the toast is gone: nothing breaks and nothing is held.
    func testTheDelegateSpeakingTwiceOrLateHoldsNothing() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        try endSheet(opened)
        try endSheet(opened)
        toast.showDone(try picture(), caption: "Next", file: nil)
        try endSheet(opened)
        XCTAssertTrue(toast.holds.isEmpty)
        toast.sheetEnded()
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertEqual(opened.pickers.count, 1)
    }

    // MARK: Inputs nobody fed

    /// ✕ while the sheet is open: the toast and its hold go; the sheet's late end does not hold the next shot.
    func testDismissWhileTheSheetIsOpenTakesTheHoldAndTheLateEndHoldsNothing() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.dismiss()
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertNil(toast.model.content)
        try endSheet(opened)
        toast.showDone(try picture(), caption: "Next", file: nil)
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertTrue(toast.advance(by: 5), "the dismissed shot's sheet holds the next one")
    }

    /// A new shot arrives while the sheet is open: the sheet is still on the screen, standing at this very view, and
    /// the new thumbnail must not count down under it.
    func testANewShotWhileTheSheetIsOpenIsHeldByTheSheet() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.pointerIsOver = { false }
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        XCTAssertEqual(toast.holds, [.sheet])
        toast.showWorking(try picture())
        XCTAssertTrue(toast.holds.contains(.sheet), "the new shot dropped the hold of the sheet that is still open")
        toast.showDone(try picture(), caption: "Next", file: nil)
        XCTAssertFalse(toast.advance(by: 100), "the next shot's thumbnail went from under the open sheet")
    }

    /// A refusal arrives while the sheet is open: it is shown, and does not count down under the sheet either.
    func testARefusalWhileTheSheetIsOpenIsHeldByTheSheet() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.pointerIsOver = { false }
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.showRefusal(.encoding)
        XCTAssertTrue(toast.holds.contains(.sheet), "a refusal dropped the hold of the sheet that is still open")
    }

    /// A second Share while the first sheet is open does not stack a second sheet on it.
    func testASecondShareWhileASheetIsOpenOpensNoSecondSheet() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.showDone(try picture(), caption: "Saved again", file: nil, share: true)
        XCTAssertEqual(opened.pickers.count, 1, "two sheets are open at one thumbnail")
        try endSheet(opened, at: 0)
        XCTAssertTrue(toast.holds.isEmpty, "the first sheet's end is the end of the only sheet")
    }

    /// A sheet whose end the system reports for the sheet that was taken away (✕ closed the toast under it) must not
    /// release the hold of the sheet that stands now. A second request while a sheet is open opens none, so the one
    /// replaced sheet there can be is the dismissed one; the second sheet is asked to exist, not assumed.
    func testTheEndOfAReplacedSheetDoesNotReleaseTheNewOne() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.dismiss()
        toast.showDone(try picture(), caption: "Saved again", file: nil, share: true)
        XCTAssertEqual(opened.pickers.count, 2, "the control: the shot after the dismissed one opens its own sheet")
        XCTAssertEqual(toast.holds, [.sheet])
        try endSheet(opened, at: 0)
        XCTAssertEqual(toast.holds, [.sheet], "the first sheet's end released the second's hold")
        try endSheet(opened, at: 1)
        XCTAssertTrue(toast.holds.isEmpty, "the control: the second sheet's own end releases it")
    }

    /// The file was removed before the sheet re-read it: a sheet over a path that is not there is not offered.
    func testAFileThatWentBeforeShareOpensNoSheet() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        let folder = scratchDirectory("share-gone")
        let image = try picture()
        let file = try ShotToastRig.writePNG(image, in: folder)
        try FileManager.default.removeItem(at: file)
        toast.showDone(image, caption: "Saved", file: file, share: true)
        XCTAssertEqual(opened.pickers.count, 0, "a sheet opened over a file that is gone")
        XCTAssertTrue(toast.holds.isEmpty)
    }

    // MARK: What the sheet is given

    /// A shot that was written is shared as its file: the one URL, not a picture of it.
    func testTheSheetIsGivenTheFileWhenOneWasWritten() throws {
        let toast = bare(opened: Opened())
        let image = try picture()
        let file = try ShotToastRig.writePNG(image, in: scratchDirectory("share-items-file"))
        toast.showDone(image, caption: "Saved", file: file)
        let items = try XCTUnwrap(toast.shareItems(), "a saved shot offers nothing to the sheet")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first as? URL, file)
        XCTAssertTrue(toast.model.full == nil, "a saved shot holds a picture besides its file")
    }

    /// A clipboard-only shot is shared as its full picture, not the thumbnail's 520-pixel copy.
    func testTheSheetIsGivenTheFullPictureWhenTheShotIsOnlyOnTheClipboard() throws {
        let toast = bare(opened: Opened())
        toast.showDone(try picture(), caption: "Copied", file: nil)
        let items = try XCTUnwrap(toast.shareItems(), "a clipboard-only shot offers nothing to the sheet")
        XCTAssertEqual(items.count, 1)
        let shared = try XCTUnwrap(items.first as? NSImage, "the sheet is not given a picture: \(items)")
        XCTAssertEqual(shared.size.width, 1200, "the sheet is given the thumbnail's reduced copy")
        XCTAssertEqual(shared.size.height, 700)
    }

    /// Nothing to share while the result is not in, after a refusal, and after the shot went.
    func testTheSheetIsGivenNothingWhenThereIsNothingToShare() throws {
        let toast = bare(opened: Opened())
        XCTAssertNil(toast.shareItems(), "an empty toast offers something")
        toast.showWorking(try picture())
        XCTAssertNil(toast.shareItems(), "the working thumbnail's reduced copy is offered")
        toast.showRefusal(.encoding)
        XCTAssertNil(toast.shareItems(), "a refusal offers something")
        toast.showDone(try picture(), caption: "Copied", file: nil)
        toast.dismiss()
        XCTAssertNil(toast.shareItems(), "a dismissed toast still offers its shot")
    }

    /// A sheet that really opens, for a written shot: one sheet, and the items it stands for are the file.
    func testTheOpenedSheetStandsForTheFileOfTheShot() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        let image = try picture()
        let file = try ShotToastRig.writePNG(image, in: scratchDirectory("share-items-sheet"))
        toast.showDone(image, caption: "Saved", file: file, share: true)
        XCTAssertEqual(opened.pickers.count, 1)
        XCTAssertEqual(toast.shareItems()?.first as? URL, file)
    }

    /// A sheet while the pointer's hold is also there: ending the sheet leaves the pointer's hold, and the other way.
    func testTheSheetAndThePointerHoldIndependently() throws {
        var over = true
        let opened = Opened()
        let toast = bare(opened: opened)
        _ = anchored(toast)
        toast.pointerIsOver = { over }
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.setHover(true)
        XCTAssertEqual(toast.holds, [.pointer, .sheet])
        try endSheet(opened)
        XCTAssertEqual(toast.holds, [.pointer])
        XCTAssertFalse(toast.advance(by: 100))
        over = false
        XCTAssertFalse(toast.advance(by: 1))
        XCTAssertTrue(toast.advance(by: 4))
    }

    // MARK: The sheet goes with the toast

    /// What `closePicker` was asked, in order; the seam is the toast's, so no system sheet is touched.
    private func closes(of toast: ShotToast) -> ClosedSheets {
        let closed = ClosedSheets()
        toast.closePicker = { closed.pickers.append($0) }
        return closed
    }

    private final class ClosedSheets { var pickers: [NSSharingServicePicker] = [] }

    /// ✕ under an open sheet closes that sheet, once, whatever is asked after it.
    func testDismissUnderAnOpenSheetClosesThatSheetOnce() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        let closed = closes(of: toast)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        XCTAssertEqual(opened.pickers.count, 1, "the control: a sheet is open")
        toast.dismiss()
        XCTAssertEqual(closed.pickers.count, 1, "the sheet was left open under a toast that is gone, or closed twice")
        XCTAssertTrue(closed.pickers.first === opened.pickers.first?.0, "another sheet was closed")
        toast.dismiss()
        XCTAssertEqual(closed.pickers.count, 1, "a second ✕ closed a sheet that was already closed")
    }

    /// No sheet open: the ✕ closes none, before a Share, and after one that ended.
    func testDismissWithNoSheetClosesNone() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        let closed = closes(of: toast)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil)
        toast.dismiss()
        XCTAssertEqual(closed.pickers.count, 0, "a sheet was closed that nobody opened")
        toast.showDone(try picture(), caption: "Shared", file: nil, share: true)
        XCTAssertEqual(opened.pickers.count, 1, "the control: a sheet opened")
        try endSheet(opened)
        toast.dismiss()
        XCTAssertEqual(closed.pickers.count, 0, "a sheet that ended was closed again")
    }

    /// A refusal over an open sheet leaves it open (it stands at this very view); the ✕ then closes it.
    func testDismissAfterARefusalOverAnOpenSheetClosesIt() throws {
        let opened = Opened()
        let toast = bare(opened: opened)
        let closed = closes(of: toast)
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        toast.showRefusal(.encoding)
        XCTAssertEqual(closed.pickers.count, 0, "the refusal closed the sheet that is still on the screen")
        toast.dismiss()
        XCTAssertEqual(closed.pickers.count, 1, "the sheet outlived the toast that was holding it")
    }

    /// With no seam passed, ✕ under a sheet asks the picker itself; one that was never shown takes the close
    /// without harm, and the toast's holds are gone after it.
    func testTheDefaultSeamAsksThePickerAndAnUnshownOneTakesIt() throws {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        toast.presentPicker = { _, _ in }
        _ = anchored(toast)
        toast.showDone(try picture(), caption: "Saved", file: nil, share: true)
        XCTAssertEqual(toast.holds, [.sheet])
        toast.dismiss()
        XCTAssertTrue(toast.holds.isEmpty)
    }
}

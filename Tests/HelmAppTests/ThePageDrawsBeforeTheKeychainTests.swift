import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp

/// **A sealed setting must not be read on the path that builds a window.**
///
/// The path is `AppSettings.disabledScans.getter` → `SettingGuard.establishKey()`
/// → `KeychainSealKey.read()`. An ad-hoc signed build has a new cdhash that no
/// earlier keychain ACL matches, so the keychain answers with a modal
/// authorization dialog, in front of a window that has drawn nothing
/// (Architecture/StoredSettings.md § Sealed settings). A `@State` initializer
/// on the settings page is a read at construction.
///
/// **The subject is the hosting view, not the struct.** `MenuBarSettingsView()`
/// on its own reads nothing: SwiftUI evaluates a `@State` initial value when
/// the state is installed into the view graph, at `NSHostingView(rootView:)`.
/// A test that constructed the struct and asserted zero would pass with the
/// defect in place.
///
/// **And the question is which thread, not which line.** A read moved into the
/// page's `.task` is drained by the same `layoutSubtreeIfNeeded()` that draws
/// the page, so it still stands between the window and its first frame. What
/// these hold is that the keychain is never asked on the thread that draws,
/// and that the page draws while it is still being asked.
@MainActor
final class ThePageDrawsBeforeTheKeychainTests: DisabledScansTestCase {

    /// A drawn page: the frame it produced, and the two objects that have to
    /// outlive the measurement for it to mean anything.
    private struct Drawn {
        let host: NSView
        let window: NSWindow
        let frame: NSBitmapImageRep
    }

    /// The page in a window, laid out and drawn into a bitmap — the whole of
    /// what the app does before a person sees anything, and none of what it does
    /// afterwards. `cacheDisplay` needs no screen and no permission.
    private func drawThePage() -> Drawn {
        let host = NSHostingView(rootView: MenuBarSettingsView().frame(width: Self.width))
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return Drawn(host: host, window: window, frame: rep)
    }

    /// Day one, which is the worst case: nothing is stored, so the getter's
    /// answer is the default — and it establishes the key on the way past.
    func testDrawingThePageNeverAsksTheKeychainOnTheDrawingThread() {
        let keychain = freshMac(cached: true)
        let drawn = drawThePage()
        XCTAssertGreaterThan(drawn.frame.pixelsWide, 0,
                             "nothing was drawn, so nothing was measured")
        XCTAssertFalse(keychain.wasAskedOnTheMainThread,
                       "the settings page reached the keychain on the thread that draws it, "
                       + "which on an ad-hoc build is an authorization dialog in front of a "
                       + "window with nothing in it")
    }

    /// And the ordinary case: a value this installation sealed itself, which
    /// still costs a key to verify.
    func testDrawingThePageWithASealedValueStoredAsksNothingOnThatThread() {
        let keychain = freshMac(cached: true)
        AppSettings.disabledScans = ["disk"]
        // Assert the subject happened, or an absence proves nothing: the write
        // really did seal, and the value really does read back as Helm's own.
        XCTAssertGreaterThan(keychain.reads, 0, "the write did not seal anything")
        XCTAssertEqual(AppSettings.disabledScans, ["disk"])

        // The writer and the reader above are the test's own, on the main
        // thread. What the page does is the question, so the record starts here.
        let fresh = SealKeyProbe()
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(fresh))
        let drawn = drawThePage()
        XCTAssertGreaterThan(drawn.frame.pixelsWide, 0)
        XCTAssertFalse(fresh.wasAskedOnTheMainThread,
                       "verifying the seal reached the keychain from the drawing thread")
    }

    /// **The harm itself, and the shape that catches an inert fix.** The
    /// keychain is held shut for the whole of the draw, standing in for the
    /// authorization dialog: a page that waits for it anywhere on the drawing
    /// thread cannot reach the assertion below with nothing read, and a page
    /// that does not draws a full frame with the dialog still up — which is what
    /// the person in front of the Mac needs to be true.
    ///
    /// The watchdog is the difference between a red test and a hung suite: a
    /// gate opened only in the `defer` leaves a waiting page deadlocked on the
    /// main thread. Five seconds is no threshold for the passing path, which
    /// draws and asserts at once; only a page that *waits* is still there when
    /// it fires.
    func testThePageDrawsWhileTheKeychainIsStillAnswering() {
        let gate = DispatchSemaphore(value: 0)
        let keychain = freshMac(cached: true, gate: gate)
        defer { gate.signal() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { gate.signal() }
        let drawn = drawThePage()
        XCTAssertGreaterThan(drawn.frame.pixelsWide, 0)
        XCTAssertEqual(keychain.reads, 0,
                       "the page drew only after the keychain had answered, so on a Mac where "
                       + "answering means a dialog it would not have drawn at all")
    }

    /// The reason none of the above is satisfied by deleting the setting: once
    /// the keychain answers, the page does read the off-list. An absence that is
    /// permanent is a section that never appears.
    func testThePageReadsTheOffListOnceTheKeychainAnswers() async {
        let keychain = freshMac(cached: true)
        let drawn = drawThePage()
        await waitUntil("the page reads the off-list") {
            drawn.host.layoutSubtreeIfNeeded()
            return keychain.reads > 0
        }
        XCTAssertGreaterThan(keychain.reads, 0,
                             "the page never reads the off-list at all, so the switches it "
                             + "exists to draw would never appear")
    }

    /// A page that has not read the off-list yet must not draw switches: the
    /// only set it could draw them from is the empty one, and «no scan is
    /// disabled» is «every scan is on», wrong in the dangerous direction.
    func testThePageSaysNothingAboutScansItHasNotReadYet() throws {
        let everyModule = Set(ModuleRegistry.all.map(\.idRaw))
        XCTAssertNil(MenuBarSettingsView.scanRows(enabled: everyModule, disabledScans: nil,
                                                  lastRun: [:]),
                     "an unread off-list must be no rows at all, not rows saying every scan is on")
        let read = try XCTUnwrap(MenuBarSettingsView.scanRows(enabled: everyModule,
                                                             disabledScans: [], lastRun: [:]))
        XCTAssertFalse(read.isEmpty, "or the two states are the same state and the test is empty")
        XCTAssertTrue(read.allSatisfy(\.isOn))
    }

    private static let width: CGFloat = 900
    private static let height: CGFloat = 700
}

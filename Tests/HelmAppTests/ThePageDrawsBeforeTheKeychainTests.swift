import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp

/// **A sealed setting must not be read on the path that builds a window.**
///
/// Measured 2026-08-15: `SettingsWindow.init` → SwiftUI layout →
/// `AppSettings.disabledScans.getter` → `SettingGuard.establishKey()` →
/// `KeychainSealKey.read()`. The bundle is ad-hoc signed, so every build has a
/// new cdhash and no keychain ACL written by an earlier one matches it: the
/// keychain answers with a modal authorization dialog, and it stood in front of
/// the settings window *before the window had drawn anything*, twice blocking
/// the screenshot harness.
///
/// This is ARCHITECTURE.md § A seal needs a signature arriving through the
/// second door. `clamshellEnabled` is unsealed because `init` reads it;
/// `disabledScans` is sealed because it is read rarely and never at launch —
/// and a `@State` initializer on the settings page is a read at construction,
/// whatever else is true of it.
///
/// **The subject is the hosting view, not the struct.** `MenuBarSettingsView()`
/// on its own reads nothing: SwiftUI takes a `@State` initial value as an
/// autoclosure and evaluates it when the state is installed into the view graph.
/// Measured on this page — the count goes 0 → 1 at `NSHostingView(rootView:)`
/// and does not move again at `layoutSubtreeIfNeeded()`. A test that constructed
/// the struct and asserted zero was green with the defect fully in place.
///
/// **And the question is which thread, not which line.** Moving the read into
/// the page's `.task` was measured *not* fixing this: the continuation is
/// drained by the same `layoutSubtreeIfNeeded()` that draws the page, so a
/// blocking read inside it still stood between the window and its first frame —
/// an inert fix, and green under any test that only asked where the call was
/// written. What these hold is that the keychain is never asked on the thread
/// that draws, and that the page draws while it is still being asked.
@MainActor
final class ThePageDrawsBeforeTheKeychainTests: XCTestCase {

    private let key = "disabledScans"
    private var macKey: String { SettingGuard.macKey(for: key) }
    private var savedValue: Any?
    private var savedMac: Any?
    private var savedGuard: SettingGuard!

    override func setUp() async throws {
        savedValue = AppSettings.store.object(key)
        savedMac = AppSettings.store.object(macKey)
        savedGuard = AppSettings.scanGuard
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedValue, for: key)
        AppSettings.store.set(savedMac, for: macKey)
        AppSettings.scanGuard = savedGuard
    }

    /// A Mac nobody has configured: no stored value, no MAC, no keychain item.
    private func freshMac(gate: DispatchSemaphore? = nil) -> SealKeyProbe {
        AppSettings.store.set(nil, for: key)
        AppSettings.store.set(nil, for: macKey)
        let keychain = SealKeyProbe(gate: gate)
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(keychain))
        return keychain
    }

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
        let keychain = freshMac()
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
        let keychain = freshMac()
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
    /// The watchdog is the difference between a red test and a hung suite. A
    /// gate that only ever opens in the `defer` leaves the mutant deadlocked on
    /// the main thread and the run never ends; opening it from another thread
    /// after five seconds lets the mutant get to the assertion and fail it. Five
    /// seconds is not a threshold the passing path is measured against — it
    /// draws and asserts immediately, and only a page that *waits* can still be
    /// there when the watchdog fires.
    func testThePageDrawsWhileTheKeychainIsStillAnswering() {
        let gate = DispatchSemaphore(value: 0)
        let keychain = freshMac(gate: gate)
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
    func testThePageReadsTheOffListOnceTheKeychainAnswers() {
        let keychain = freshMac()
        let drawn = drawThePage()
        for _ in 0..<200 where keychain.reads == 0 {
            drawn.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertGreaterThan(keychain.reads, 0,
                             "the page never reads the off-list at all, so the switches it "
                             + "exists to draw would never appear")
    }

    /// The honest half of the same fix. A page that has not read the off-list
    /// yet must not draw switches, because the only set it could draw them from
    /// is the empty one — and «no scan is disabled» is «every scan is on», which
    /// is the wrong answer in the dangerous direction.
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

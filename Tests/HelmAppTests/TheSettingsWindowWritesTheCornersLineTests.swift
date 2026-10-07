import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **A Settings window made by `SettingsWindow`'s own initialiser with the macOS
/// 27 band and laid out, never ordered in, made key or activated, writes the
/// corner's line under `[window]`; a zero from the probe of a window that is not
/// shown is not taken as its corner; and the shell asks for a layout when its
/// window's occlusion notification is posted.** The lines are read back from
/// `HelmLog`'s tail.
///
/// The two tests of `WindowCorner.publicAnswer` build no window. In the others
/// total failure of the subject prints the first assertion's message: the shell
/// is in no window, or has no card, so what follows it proves nothing. In
/// `testTheWindowTheAppBuildsWritesALineUnderWindow` a log that is off prints
/// the control's message.
@MainActor
final class TheSettingsWindowWritesTheCornersLineTests: XCTestCase {

    private func withTheLogOn(_ body: @MainActor () throws -> Void) rethrows {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
        defer {
            HelmLog.shared.clearTail()
            HelmLog.shared.setEnabled(false)
        }
        try body()
    }

    func testTheWindowTheAppBuildsWritesALineUnderWindow() throws {
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let found = UserDefaults.standard.string(forKey: frameKey)
        UserDefaults.standard.removeObject(forKey: frameKey)
        addTeardownBlock { UserDefaults.standard.set(found, forKey: frameKey) }

        try withTheLogOn {
            let owner = SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27))
            let window = try XCTUnwrap(
                Mirror(reflecting: owner).children.first { $0.label == "window" }?.value as? NSWindow)
            let shell = try XCTUnwrap(window.contentViewController as? SettingsShellViewController)
            let view = shell.shell
            view.layoutSubtreeIfNeeded()

            XCTAssertTrue(view.window === window, "the shell's view is in no window: the silence below proves nothing")
            XCTAssertGreaterThan(view.card.frame.width, 0, "the card was never laid out: the silence below proves nothing")
            XCTAssertFalse(window.isVisible, "the window was ordered in: this test is meant to be window-free")

            let lines = HelmLog.shared.recentEntries().filter { $0.category == WindowCorner.logCategory }
            XCTAssertGreaterThanOrEqual(lines.count, 1,
                           "a Settings window built and laid out wrote no line under [window]")
            // What was written is what the card was cut from.
            let last = try XCTUnwrap(lines.last?.message)
            let radius = ShellGeometry.cardRadius(windowRadius: try XCTUnwrap(
                Double(last.split(separator: " ").dropFirst().first ?? "").map { CGFloat($0) }))
            XCTAssertEqual(view.card.layer?.cornerRadius ?? -1, radius, accuracy: 0.001,
                           "the newest line says one corner and the card was cut from another: \(last)")

            HelmLog.shared.info(WindowCorner.logCategory, "control")
            XCTAssertEqual(HelmLog.shared.recentEntries().filter { $0.category == WindowCorner.logCategory }.last?.message,
                           "control", "the log did not show a line written under [window]: the count above proves nothing")
        }
    }

    /// A zero from the probe of a window that is not shown is not its corner: no
    /// line may report one as read by the public rung while the window is being
    /// built. Reads the lines the build wrote.
    func testNoLineReportsAZeroPublicReadingAsTheCorner() throws {
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let found = UserDefaults.standard.string(forKey: frameKey)
        UserDefaults.standard.removeObject(forKey: frameKey)
        addTeardownBlock { UserDefaults.standard.set(found, forKey: frameKey) }

        try withTheLogOn {
            let owner = SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27))
            let window = try XCTUnwrap(
                Mirror(reflecting: owner).children.first { $0.label == "window" }?.value as? NSWindow)
            let shell = try XCTUnwrap(window.contentViewController as? SettingsShellViewController)
            shell.shell.layoutSubtreeIfNeeded()
            XCTAssertTrue(shell.shell.window === window, "the shell's view is in no window: the check below proves nothing")

            let lines = HelmLog.shared.recentEntries().filter { $0.category == WindowCorner.logCategory }.map(\.message)
            XCTAssertFalse(lines.isEmpty, "no line was written: the check below proves nothing")
            let zero = lines.filter { $0.hasPrefix("corner 0.0 by public") }
            XCTAssertTrue(zero.isEmpty, "a window being built was told its corner is 0.0 by the public reading: \(zero)")
        }
    }

    // MARK: - the public reading's zero

    /// A window object that answers its own corner key with 26, so that the rung
    /// the ladder lands on can be told from a guess of 16.
    private final class TwentySixWindow: NSObject {
        @objc(_cornerRadius) var radius: CGFloat = 26
    }

    private static let sixteenGuess = WindowCorner.Chrome(hasToolbar: false, systemMajor: 26)

    /// Both sides of the rule, then its edges: a negative reading, one above the
    /// ceiling, not-a-number and infinity. Control: the non-zero reading comes
    /// back as itself, so a rule that answers nil to everything, or returns
    /// everything, prints which row it broke.
    func testAZeroIsAnAnswerOnlyFromAShownWindow() {
        XCTAssertNil(WindowCorner.publicAnswer(0, windowIsShown: false), "an unshown window's zero was taken as a corner")
        XCTAssertEqual(WindowCorner.publicAnswer(0, windowIsShown: true), 0, "a shown window's zero (a borderless one) was dropped")
        XCTAssertEqual(WindowCorner.publicAnswer(16, windowIsShown: false), 16, "a non-zero reading was dropped before the window was shown")
        XCTAssertEqual(WindowCorner.publicAnswer(16, windowIsShown: true), 16, "a non-zero reading was dropped in a shown window")
        XCTAssertNil(WindowCorner.publicAnswer(nil, windowIsShown: true), "no reading became one")
        XCTAssertNil(WindowCorner.publicAnswer(nil, windowIsShown: false), "no reading became one")

        // A negative reading is held to 0 by `believable`, so it counts as a
        // zero: dropped unshown, handed on as it came when shown (and `read`
        // holds it to 0 there).
        XCTAssertNil(WindowCorner.publicAnswer(-3, windowIsShown: false), "an unshown window's negative reading was taken as a corner")
        XCTAssertNil(WindowCorner.publicAnswer(-0.0, windowIsShown: false), "an unshown window's negative zero was taken as a corner")
        XCTAssertEqual(WindowCorner.publicAnswer(-3, windowIsShown: true), -3)
        // Above the ceiling is a non-zero reading, handed on for `read` to hold.
        XCTAssertEqual(WindowCorner.publicAnswer(500, windowIsShown: false), 500)
        // Not-a-number and infinity are not zeros and not answers: they pass
        // through unchanged and `read` goes down a rung for them.
        for shown in [false, true] {
            XCTAssertEqual(WindowCorner.publicAnswer(.nan, windowIsShown: shown)?.isNaN, true, "not-a-number was changed (shown \(shown))")
            XCTAssertEqual(WindowCorner.publicAnswer(.infinity, windowIsShown: shown), .infinity, "infinity was changed (shown \(shown))")
        }
    }

    /// The ladder with a window object that answers 26 and a guess of 16: a shown
    /// zero lands on the public rung as 0; an unshown one is dropped and the
    /// window's own key answers. Control: a 16 from the probe lands on the public
    /// rung in both states, and the window's own key is 26, not the guess.
    func testAShownZeroCutsASquareCardAndAnUnshownOneGoesOnToTheNextRung() {
        let window = TwentySixWindow()
        XCTAssertEqual(WindowCorner.read(publicReading: nil, from: window, chrome: Self.sixteenGuess),
                       WindowCorner(radius: 26, rung: .windowSelector),
                       "the fake window did not answer its own key: the rows below prove nothing")

        let shown = WindowCorner.read(publicReading: WindowCorner.publicAnswer(0, windowIsShown: true),
                                      from: window, chrome: Self.sixteenGuess)
        XCTAssertEqual(shown, WindowCorner(radius: 0, rung: .publicAPI), "a shown window's zero did not stay the corner")
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: shown.radius), ShellGeometry.cardRadius(windowRadius: 0),
                       "the card radius of a shown window's zero is not the card radius of a zero")

        let unshown = WindowCorner.read(publicReading: WindowCorner.publicAnswer(0, windowIsShown: false),
                                        from: window, chrome: Self.sixteenGuess)
        XCTAssertEqual(unshown, WindowCorner(radius: 26, rung: .windowSelector), "an unshown window's zero was taken as the corner")

        for isShown in [false, true] {
            XCTAssertEqual(WindowCorner.read(publicReading: WindowCorner.publicAnswer(16, windowIsShown: isShown),
                                             from: window, chrome: Self.sixteenGuess),
                           WindowCorner(radius: 16, rung: .publicAPI), "a 16 from the probe was not the corner (shown \(isShown))")
        }
    }

    // MARK: - the window as built

    /// Builds the Settings window through `SettingsWindow`'s own initialiser with
    /// the macOS 27 band and lays it out, never ordering it in; returns the owner
    /// too, which holds the window.
    private func builtWindow() throws -> (owner: SettingsWindow, window: NSWindow, shell: SettingsShellViewController) {
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let found = UserDefaults.standard.string(forKey: frameKey)
        UserDefaults.standard.removeObject(forKey: frameKey)
        addTeardownBlock { UserDefaults.standard.set(found, forKey: frameKey) }
        let owner = SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27))
        let window = try XCTUnwrap(
            Mirror(reflecting: owner).children.first { $0.label == "window" }?.value as? NSWindow)
        let shell = try XCTUnwrap(window.contentViewController as? SettingsShellViewController)
        shell.shell.layoutSubtreeIfNeeded()
        XCTAssertTrue(shell.shell.window === window, "the shell's view is in no window: what follows proves nothing")
        XCTAssertFalse(window.isVisible, "the window was ordered in: this test is meant to be window-free")
        return (owner, window, shell)
    }

    /// What the card was drawn from, not what the log says: once the layout of a
    /// window that has not been shown has settled, the card has a corner. With a
    /// not-shown window's zero taken as its corner again this test still passed,
    /// so it does not guard that rule: it guards a card left square at the end,
    /// not one cut square on the way.
    func testTheCardOfABuiltWindowIsNotLeftSquareOnceLayoutHasSettled() throws {
        let (owner, _, shell) = try builtWindow()
        withExtendedLifetime(owner) {
            XCTAssertGreaterThan(shell.shell.card.frame.width, 0, "the card was never laid out: the radius below proves nothing")
            XCTAssertGreaterThan(shell.shell.card.layer?.cornerRadius ?? -1, 0, "the card of a built window was cut square")
            XCTAssertEqual(shell.shell.clip.layer?.cornerRadius, shell.shell.card.layer?.cornerRadius,
                           "the clip and the card were cut from different corners")
        }
    }

    /// The occlusion notification of the window asks the shell for a layout while
    /// the view is in the window, and does not once it has left. Window-free: the
    /// notification is posted by hand; that ordering a window in posts it is not
    /// shown here.
    func testTheWindowsOcclusionNotificationAsksForALayoutOnlyWhileTheViewIsInIt() async throws {
        let (owner, window, shell) = try builtWindow()
        let view = shell.shell

        XCTAssertFalse(view.needsLayout, "layout had not settled: a true below proves nothing")
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        await waitUntil("the shell asked for a layout when its window's occlusion state changed") { view.needsLayout }

        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.needsLayout, "layout had not settled after the first post: the absence below proves nothing")

        window.contentViewController = nil
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.window, "the view is still in the window: the absence below proves nothing")
        XCTAssertFalse(view.needsLayout, "layout had not settled outside the window: the absence below proves nothing")

        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        await grace()
        XCTAssertFalse(view.needsLayout, "a view that left its window still asked for a layout when the window's occlusion state changed")
        withExtendedLifetime(owner) {}
    }
}

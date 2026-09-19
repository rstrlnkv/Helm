import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The switcher is laid out once, in the metric the toolbar promotes it to —
/// and a style chosen later still produces a new width.**
///
/// # What was measured, and how
///
/// Probed 2026-09-19 with temporary instrumentation on `HelmToolbarSwitcher`
/// itself — a print at `makeNSView`, at every `updateNSView` and at every
/// `sizeThatFits`, carrying `controlSize.rawValue` and the size answered —
/// mounted through this file's own harness and run three times singly as
/// `bash Scripts/test.sh --filter …`. The instrumentation is gone; what it read
/// is this:
///
/// - The order never varied across the three runs: `makeNSView`, then one
///   `updateNSView` with `firstFill` true, then every `sizeThatFits`. The first
///   fill therefore happens **before** SwiftUI ever asks the control for a
///   size, which is what makes `updateNSView` a place a metric can be set from.
/// - Unpinned, the first `sizeThatFits` is answered at `controlSize == .regular`
///   and every later one at `.extraLarge`: AppKit promotes the control as the
///   toolbar inserts it in its item viewer, and nothing in that promotion asks
///   SwiftUI again. The control's frame is then set twice — once at the loose
///   size SwiftUI committed, once at the promoted one a later layout carries.
/// - With `controlSize` pinned in the first fill, all three runs logged one
///   frame and one size: the first measurement is already the bar's.
///
/// # Why there is not a single size literal below
///
/// The file this replaces carried four — a pre-insertion and a settled size —
/// and none of the four reproduced on this machine in the probe above. Two of
/// the reasons are ordinary (another Mac, another SDK, another language), and
/// the third is decisive: `SettingsWindow.swift:47` sets
/// `setFrameAutosaveName("HelmSettingsWindow.v4")`, so the production window's
/// width is whatever the person last left it at, and a switcher's width is read
/// from the words in it. Those numbers were one session's property. Every
/// assertion here is a relation between two readings taken in the same run.
///
/// # What this cannot answer
///
/// Whether anything visibly redraws on a real first open. The control mounted
/// here reads `layer == nil`, so no Core Animation animation can be observed on
/// it at all — the same limit as the offscreen reading written up in
/// `Tests/HelmUITests/TheSwitcherFillsItsFirstFrameWithoutAnimationTests.swift`.
/// A green run here says the frame is set once; it does not say the window
/// looked right.
@MainActor
final class TheToolbarSwitcherIsLaidOutOnceInTheBarsMetricTests: XCTestCase {

    /// Four segments, as Homebrew's page declares them. The words are counted,
    /// never asserted, so no language is named: what is read here is geometry,
    /// and `AppLanguage` would change the numbers without changing the shape.
    private static let words = ["Installed", "Updates", "Search", "Health"]

    // MARK: - One layout, in the bar's own metric

    /// Three readings of one run: the canary the bar still promotes, the
    /// switcher that no longer moves, and the height the two have to agree on.
    ///
    /// The canary is first and carries the total-failure message. If AppKit
    /// stops promoting a control it was given no metric for, that assertion is
    /// the one that goes red, and it says Apple removed the promotion rather
    /// than that Helm broke — without it the other two would hold for free on
    /// such a machine, the way an equality between two unchanging numbers does.
    /// Watched red 2026-09-19 by giving the canary the same pin and
    /// `sizeThatFits` production has, which is the only way to reach that state
    /// from here.
    ///
    /// **The third assertion has not been watched fail.** Pinning the wrong
    /// metric — `.large` for `.extraLarge` — was measured on the same day and
    /// went red at the *second* assertion instead: the bar promoted the control
    /// again from `.large`, so the settled heights still agreed and what showed
    /// was the frame being set twice. It stays because it is the sentence that
    /// names the bar's metric without naming a number, and on a machine where
    /// the frame does not get revised it is the only one that would speak.
    func testTheSwitcherTakesTheBarsMetricBeforeItsFirstMeasurement() throws {
        let log = FrameLog()
        defer { log.stop() }

        let switcher = try mount(SwitcherPage(words: Self.words, choice: Choice(.text)), log: log)
        defer { switcher.window.orderOut(nil) }
        let canary = try mount(BarePage(words: Self.words), log: log)
        defer { canary.window.orderOut(nil) }

        let canaryFrames = try frames(of: canary, log: log)
        XCTAssertNotEqual(canaryFrames.first!.height, canaryFrames.last!.height, accuracy: 0.01, """
            a segmented control the bar was given no metric for was laid out at \
            \(canaryFrames.first!.height) pt and settled at \(canaryFrames.last!.height): the \
            toolbar no longer promotes a control on insertion. Apple removed the promotion, and \
            with it the reason this file exists — the two readings below then agree for free and \
            guard nothing.
            """)

        let switcherFrames = try frames(of: switcher, log: log)
        XCTAssertEqual(switcherFrames.first!, switcherFrames.last!, """
            the switcher was laid out at \(switcherFrames.first!) and settled at \
            \(switcherFrames.last!), over \(switcherFrames.count) frame(s): SwiftUI committed a \
            size measured in the metric the control had before the toolbar took it, and the box \
            was revised under the drawn control afterwards.
            """)

        XCTAssertEqual(switcherFrames.last!.height, canaryFrames.last!.height, accuracy: 0.01, """
            the switcher settles \(switcherFrames.last!.height) pt tall where a control the bar \
            sized itself settles \(canaryFrames.last!.height): the metric pinned in updateNSView \
            is not the one the toolbar promotes to, so the switcher draws at its own height beside \
            every other control on the same glass.
            """)
    }

    // MARK: - The style change still hands SwiftUI a new size

    /// The contract the earlier repairs of this defect kept breaking: a style
    /// chosen by right-click has to change the item's width.
    ///
    /// It is a live change on **one** control, not two mounts compared — the
    /// pin runs in the first fill only, `hasFilled` is true here, and the same
    /// `NSView` survives the change (`AStyleChosenInTheBarReachesTheBarTests`
    /// holds the tracker to that). So this reads the one path where
    /// `sizeThatFits` still has to answer live, and it goes red for a
    /// `sizeThatFits` that remembers what it said the first time.
    func testAStyleChosenLaterStillGivesSwiftUIANewWidth() throws {
        let log = FrameLog()
        defer { log.stop() }
        let choice = Choice(.text)
        let mounted = try mount(SwitcherPage(words: Self.words, choice: choice), log: log)
        defer { mounted.window.orderOut(nil) }
        let withWords = try frames(of: mounted, log: log).last!

        choice.style = .icons
        settle(mounted, log: log)
        let withGlyphs = try frames(of: mounted, log: log).last!

        XCTAssertNotEqual(withWords.width, withGlyphs.width, accuracy: 0.01, """
            the switcher is \(withGlyphs.width) pt wide showing glyphs alone, exactly as it was \
            showing four words: SwiftUI was handed one size and never asked again, so the style a \
            person picks in the bar redraws the segments inside a box that is still the old one's.
            """)
    }

    // MARK: - Mounting

    /// A window built as `SettingsWindow` builds its own: the content size is
    /// set after the hosting controller is in place, which is the second layout
    /// of the toolbar.
    private struct Mounted {
        let window: NSWindow
        let control: NSSegmentedControl
    }

    /// Mounts `page` in a window of that construction and waits for the toolbar
    /// to stop moving the control.
    ///
    /// The run loop is turned rather than yielded: the bridge publishes its
    /// items, and AppKit lays the toolbar out, on later turns of the main run
    /// loop, and a cooperative yield buys none of them.
    private func mount(_ page: some View, log: FrameLog,
                       file: StaticString = #filePath, line: UInt = #line) throws -> Mounted {
        _ = NSApplication.shared
        let controller = NSHostingController(rootView: page)
        controller.sceneBridgingOptions = [.toolbars]
        controller.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        // The test holds this window; closing a window AppKit still believes
        // it owns releases it under ARC, which is a crash in teardown and not
        // a failure anybody can read.
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1060, height: 700))
        window.orderBack(nil)
        window.layoutIfNeeded()

        var control: NSSegmentedControl?
        let deadline = Date().addingTimeInterval(Self.deadline)
        while Date() < deadline, control == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(Self.turn))
            // The toolbar lives above the content view, so the walk starts at
            // the frame view. A control the walk cannot reach is taken off the
            // frame observer instead, and only one in this window: the log is
            // shared by every mount a case makes.
            control = window.contentView?.superview?.everyView(ofType: NSSegmentedControl.self).first
                ?? log.caught().first { $0.window === window }
        }
        let found = try XCTUnwrap(control, """
            no NSSegmentedControl was mounted within \(Self.deadline) s, so every reading below \
            would be a reading of nothing.
            """, file: file, line: line)
        XCTAssertEqual(found.segmentCount, Self.words.count, """
            the mounted control holds \(found.segmentCount) segments, not \(Self.words.count): it \
            was never filled, so its frame is not a measurement of anything.
            """, file: file, line: line)
        let mounted = Mounted(window: window, control: found)
        settle(mounted, log: log)
        return mounted
    }

    /// Turns the run loop until the control's frame has been quiet for
    /// `quiet`, or until the deadline — so a reading taken afterwards is the
    /// settled one and not whichever turn the loop happened to stop on.
    private func settle(_ mounted: Mounted, log: FrameLog) {
        var seen = log.frames(of: mounted.control).count
        var quietSince = Date()
        let deadline = Date().addingTimeInterval(Self.deadline)
        while Date() < deadline, Date().timeIntervalSince(quietSince) < Self.quiet {
            RunLoop.current.run(until: Date().addingTimeInterval(Self.turn))
            let now = log.frames(of: mounted.control).count
            if now != seen {
                seen = now
                quietSince = Date()
            }
        }
    }

    /// Every frame AppKit has set on this control, newest last — unwrapped
    /// here once, so each case reads `.first!` and `.last!` off a sequence
    /// something has already vouched for.
    private func frames(of mounted: Mounted, log: FrameLog,
                        file: StaticString = #filePath, line: UInt = #line) throws -> [CGSize] {
        let frames = log.frames(of: mounted.control)
        _ = try XCTUnwrap(frames.first, """
            the control's frame was never set, so there is nothing here to compare and this case \
            read nothing.
            """, file: file, line: line)
        return frames
    }

    private static let turn: TimeInterval = 0.02
    private static let quiet: TimeInterval = 0.5
    private static let deadline: TimeInterval = 3

    // MARK: - The two pages

    /// The style the page hands down, changeable from the test while one
    /// control stays mounted.
    @MainActor private final class Choice: ObservableObject {
        @Published var style: ToolbarSwitcherStyle
        init(_ style: ToolbarSwitcherStyle) { self.style = style }
    }

    /// A page as Homebrew and Hosts declare theirs: the switcher as the
    /// principal toolbar item, under the same fixed navigation spacer
    /// `SettingsWindow` puts on the detail pane. The environment is applied
    /// outermost, so the toolbar's own content is inside it.
    private struct SwitcherPage: View {
        let words: [String]
        @ObservedObject var choice: Choice
        @State private var selection = 0

        var body: some View {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HelmToolbarSwitcher("Probe", selection: $selection,
                                            segments: words.enumerated().map { index, word in
                                                HelmSwitcherSegment(index, word, symbol: "circle")
                                            })
                    }
                }
                .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
                .environment(\.helmSwitcherStyle, choice.style)
        }
    }

    /// The canary: the same control in the same slot of the same window, with
    /// no `sizeThatFits` of its own and no metric written on it, so what
    /// happens to it is the toolbar's doing and nothing of Helm's.
    private struct BarePage: View {
        let words: [String]

        var body: some View {
            Color.clear
                .toolbar { ToolbarItem(placement: .principal) { BareSegments(words: words) } }
                .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }
    }

    private struct BareSegments: NSViewRepresentable {
        let words: [String]

        func makeNSView(context: Context) -> NSSegmentedControl {
            let control = NSSegmentedControl()
            control.segmentStyle = .automatic
            control.segmentDistribution = .fit
            control.segmentCount = words.count
            for (index, word) in words.enumerated() {
                control.setLabel(word, forSegment: index)
                control.setWidth(0, forSegment: index)
            }
            return control
        }

        func updateNSView(_ control: NSSegmentedControl, context: Context) {}
    }
}

/// Every frame AppKit sets on any segmented control, kept per control.
///
/// One observer for a whole case, rather than one per mount: a case here mounts
/// two windows and has to keep their controls apart, which identity does and a
/// per-window notification object would not — the control does not exist yet
/// when the observer has to be registered.
@MainActor private final class FrameLog {
    private var log: [(ObjectIdentifier, CGSize)] = []
    private var controls: [NSSegmentedControl] = []
    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: nil, queue: nil) { [weak self] note in
            guard let seen = note.object as? NSSegmentedControl else { return }
            MainActor.assumeIsolated {
                self?.took(seen)
            }
        }
    }

    private func took(_ control: NSSegmentedControl) {
        log.append((ObjectIdentifier(control), control.frame.size))
        if !controls.contains(where: { $0 === control }) { controls.append(control) }
    }

    func frames(of control: NSSegmentedControl) -> [CGSize] {
        log.filter { $0.0 == ObjectIdentifier(control) }.map(\.1)
    }

    func caught() -> [NSSegmentedControl] { controls }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}

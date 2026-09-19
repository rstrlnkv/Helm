import AppKit
import HelmTestSupport
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmUI

/// **A fill of the toolbar switcher opens an animation group only where there
/// is a layer for the animation to run on.**
///
/// # The defect this stands over
///
/// Designer measured the built dev app on 2026-09-19: five `updateNSView` calls
/// land within 52.2 ms of a module opening and the control has **no layer in
/// any of them**. `hasFilled` is true after the first, so calls two to five
/// took the animated branch, `NSAnimationContext.runAnimationGroup` put 0.22 s
/// on the `CATransaction` — and the layer was born *inside* that transaction,
/// which carried the 0.22 s onto its first `bounds` animation, `{{0,0},{0,0}}`
/// to 370.5 × 36.0. One animation key in the whole subtree, `bounds`, duration
/// 0.22 where Core Animation's own default is 0.25.
///
/// Both earlier rounds looked at the *first* fill. The damage was in the branch
/// that runs when the fill is **not** first, on a control that has not been
/// drawn yet — so the guard has to be on a later fill of a layerless control,
/// and that is exactly the one state an offscreen mount can hold.
///
/// # Why this can be measured offscreen when the displacement cannot
///
/// The neighbouring file
/// (`TheSwitcherFillsItsFirstFrameWithoutAnimationTests.swift`) says no
/// offscreen check can watch the segments *move*, and that stands: an implicit
/// animation is a Core Animation animation on a layer, and in an
/// `NSHostingView` the control has none. That same fact is what makes **this**
/// question answerable. The layerless control is not a limitation here, it is
/// the subject: the check is on whether production *asks* AppKit to animate
/// while there is nothing to animate on, and the ask is observable wherever the
/// call is made.
///
/// So the reading is taken on the call itself. `NSAnimationContext`'s
/// `runAnimationGroup:` is exchanged with a stand-in for the length of one
/// case, and every group opened while it is installed is recorded with the
/// flags its caller set. That is the one observation point production passes
/// through — a hook on the selection type's `==` cannot see this branch at all,
/// because `updateNSView` computes `selected` *before* the `if` and the
/// comparison therefore always reads the ambient context.
///
/// # What a total failure prints, and what tells it apart from a probe that
/// saw nothing
///
/// Three ways for this file to be worthless, and each one prints:
///
/// - **The probe is not installed, or the exchange stopped working.** The
///   canary in `testALaterFillOfALayerlessControlAsksForNoImplicitAnimation`
///   opens a group by hand, with `allowsImplicitAnimation = true`, and fails
///   with "the probe recorded nothing while a group was genuinely open" —
///   before the absence below is asserted at all. An absence recorded by a dead
///   instrument would otherwise read exactly like a pass.
/// - **The later update never happened.** The style moves `text` → `icons`, so
///   the segments must come back with their words cleared and a glyph set, on
///   the *same* control object; all three are asserted before any reading is
///   believed.
/// - **AppKit began giving an offscreen control a layer.** `control.layer` is
///   asserted nil with that reason. The case would then be measuring the
///   animated branch and calling it the unanimated one.
///
/// # What was seen red
///
/// Three mutations were put back into `HelmToolbarSwitcher.swift`, each read
/// off disk before the run and restored from a copy afterwards, all against the
/// same eleven selected cases — this file's three, the six in
/// `TheSwitcherFillsItsFirstFrameWithoutAnimationTests.swift` and the two in
/// `TheToolbarSwitcherIsNotStrandedAtItsMeasuredSizeTests.swift`:
///
/// - `fillAnimates` → `!firstFill`, the defect as it shipped: two failures,
///   both here — the `firstFill: false, hasLayer: false` row, and the later
///   fill below, which recorded the field's own signature offscreen,
///   `allowsImplicitAnimation: true, duration: 0.22 s`, 4 groups seen in total.
/// - `if !firstFill` restored at the call site, the same defect spelled where
///   the decision is consulted rather than where it is made: one failure, the
///   later fill below. The rows pass — `fillAnimates` is correct and unasked —
///   so the runtime case is the only thing standing over the call site.
/// - `fillAnimates` → `true`, every fill animated including the first: four
///   failures, all four here.
///
/// **All six cases in the neighbouring file stayed green under all three**,
/// the third included — and that third is the defect that file is named for.
/// Its runtime reading is taken from the selection type's `==`, which
/// `updateNSView` runs where it computes `selected`, above the `if`; the
/// ambient context is therefore what it reads whichever branch is taken.
///
/// And `testAFillOfAControlThatHasALayerStillOpensOneAnimationGroup` is the
/// negative control: the *same* later update, on the same control, with the
/// only difference being a layer — it must open exactly one implicit group at
/// 0.22 s. Without it, the case above would pass for a switcher that never
/// animates anything at all.
///
/// No visible string is asserted anywhere here — what is read is a call and its
/// arguments — so no language is named.
@MainActor
final class TheSwitcherOpensNoAnimationGroupWithoutALayerTests: XCTestCase {

    /// Four segments, as Homebrew's page declares them. Counted, never read.
    private static let words = ["Installed", "Updates", "Search", "Health"]

    /// The duration the later fill is given, pinned in
    /// `fillDuration(firstFill:reduceMotion:)` and asserted here off the group
    /// production actually opened.
    private static let animated: TimeInterval = 0.22

    // MARK: - 1. The decision, over both terms

    /// Every combination of the two arguments. Three of the four must not
    /// animate and only the fourth may, so a function that dropped either term
    /// still reads as correct against any single row.
    ///
    /// **What a total failure prints.** The defect's own spelling, `!firstFill`
    /// — the one this pass put back to watch it go red — fails the
    /// `firstFill: false, hasLayer: false` row with "a fill of a control with no
    /// layer asked to be animated". A `fillAnimates` that answered `hasLayer`
    /// alone fails the `firstFill: true, hasLayer: true` row. One that returned
    /// `false` for everything fails the last row. One that returned `true` for
    /// everything fails three rows at once. None of the four can print what a
    /// pass prints, which is nothing.
    func testFillAnimatesOnlyWithSomethingToAnimateFromAndSomethingToAnimateOn() {
        for firstFill in [true, false] {
            for hasLayer in [true, false] {
                let animates = HelmToolbarSwitcher<Int>.fillAnimates(firstFill: firstFill,
                                                                     hasLayer: hasLayer)
                let arguments = "firstFill: \(firstFill), hasLayer: \(hasLayer)"
                if firstFill {
                    XCTAssertFalse(animates, """
                        fillAnimates(\(arguments)) asked for an animation. A first fill has \
                        nothing to animate from — the control is empty — so the animation would \
                        run from the unmeasured layout, however long the control has had a layer.
                        """)
                } else if !hasLayer {
                    XCTAssertFalse(animates, """
                        fillAnimates(\(arguments)) asked for an animation on a control with no \
                        layer. That is the defect measured on the dev build on 2026-09-19: the \
                        group's 0.22 s goes on the CATransaction, the layer is born inside it, \
                        and its first bounds animation — {{0,0},{0,0}} to 370.5 × 36.0 — carries \
                        that duration. The capsule grows over the words on a first open.
                        """)
                } else {
                    XCTAssertTrue(animates, """
                        fillAnimates(\(arguments)) refused to animate a later fill of a control \
                        that has a layer. That is the one fill that must animate: a style chosen \
                        by right-click rewrites the segments of a control already on screen, and \
                        the word should arrive with the width rather than snap into it.
                        """)
                }
            }
        }
    }

    // MARK: - 2. A later fill of a layerless control, as production runs it

    /// SwiftUI drives the real `updateNSView` twice against one control that
    /// never gets a layer — which is calls two to five of designer's trace —
    /// and no group with `allowsImplicitAnimation` is opened by either.
    func testALaterFillOfALayerlessControlAsksForNoImplicitAnimation() throws {
        AnimationGroupProbe.install()
        defer { AnimationGroupProbe.remove() }

        let host = NSHostingView(rootView: Mounted(style: .text))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()

        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        XCTAssertEqual(control.segmentCount, Self.words.count, """
            the mounted control holds \(control.segmentCount) segments, not \(Self.words.count): \
            production never filled it, so nothing below is a reading of a fill.
            """)
        let coordinator = try XCTUnwrap(control.target as? HelmToolbarSwitcher<Int>.Coordinator,
                                        "the control's target is not the switcher's coordinator")
        XCTAssertTrue(coordinator.hasFilled, """
            the coordinator reports no fill after SwiftUI filled the control, so the update below \
            would be a first fill again and not the later one this case is about.
            """)

        AnimationGroupProbe.clear()
        host.rootView = Mounted(style: .icons)
        host.layoutSubtreeIfNeeded()
        let opened = AnimationGroupProbe.seen

        // Assert the subject happened before asserting the absence. The style
        // moved text -> icons, so a control production really refilled has its
        // words cleared and a glyph on every segment.
        let again = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                  "the switcher left no NSSegmentedControl in the tree")
        XCTAssertTrue(again === control, """
            the later update replaced the NSSegmentedControl instead of refilling it, so what was \
            measured is another first fill and not a later one.
            """)
        XCTAssertEqual(control.label(forSegment: 0), "", """
            segment 0 still reads \(control.label(forSegment: 0) ?? "nil") after the style moved \
            to icons: production never refilled the control, so the absence below is an absence \
            of any fill at all rather than of an animation.
            """)
        XCTAssertNotNil(control.image(forSegment: 0), """
            segment 0 carries no glyph after the style moved to icons: production never refilled \
            the control, so nothing below is a reading of a later fill.
            """)
        XCTAssertNil(control.layer, """
            the offscreen control now has a layer (\(String(describing: control.layer))). This \
            case exists to hold the one state the defect lived in — a fill of a control that has \
            not been drawn yet — and it no longer holds it, so it is measuring the animated \
            branch and calling it the quiet one. Re-measure both cases in this file.
            """)

        // The instrument, before the absence: a group opened by hand must be
        // recorded, or "nothing was seen" says nothing about production.
        AnimationGroupProbe.clear()
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            context.duration = Self.animated
        }
        XCTAssertEqual(AnimationGroupProbe.seen.filter(\.implicit).count, 1, """
            the probe recorded \(AnimationGroupProbe.seen.count) group(s) while one was genuinely \
            open with allowsImplicitAnimation set. The exchange on \
            NSAnimationContext.runAnimationGroup is not in place, so the reading below is a \
            reading of a dead instrument and an absence it records means nothing.
            """)

        XCTAssertEqual(opened.filter(\.implicit), [], """
            a later fill of a control with no layer opened \(opened.filter(\.implicit).count) \
            animation group(s) allowing implicit animation \
            (\(opened.filter(\.implicit).map(\.description).joined(separator: "; "))). There is \
            nothing to animate on: AppKit puts that duration on the CATransaction, the control's \
            layer is born inside it, and the layer's first bounds animation runs from \
            {{0,0},{0,0}} over that duration — the capsule growing over the words on a first \
            open, which is what the owner reported. \(opened.count) group(s) were seen in total.
            """)
    }

    // MARK: - 3. The control that makes case 2 mean something

    /// The same later update on the same control, with a layer given to it
    /// first — and it must open exactly one implicit group, at the duration
    /// `fillDuration` decides.
    ///
    /// This is the negative control for the case above: without it, a switcher
    /// that had stopped animating altogether would pass there. If this one goes
    /// red, the difference the two cases rest on — the layer — has stopped
    /// existing, and case 2 no longer distinguishes anything.
    func testAFillOfAControlThatHasALayerStillOpensOneAnimationGroup() throws {
        AnimationGroupProbe.install()
        defer { AnimationGroupProbe.remove() }

        let host = NSHostingView(rootView: Mounted(style: .text))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        XCTAssertEqual(control.segmentCount, Self.words.count,
                       "production never filled the mounted control")

        // The one ingredient that is different from the case above. An
        // NSSegmentedControl asked for a layer gets a real NSViewBackingLayer
        // even offscreen — measured 2026-09-19 — which is the state the toolbar
        // puts it in once the bar has inserted it.
        control.wantsLayer = true
        XCTAssertNotNil(control.layer, """
            asking the control for a layer offscreen no longer gives it one, so this case cannot \
            hold the animated state and the case above has lost the control that makes it a \
            reading of a real difference.
            """)

        AnimationGroupProbe.clear()
        host.rootView = Mounted(style: .iconsAndText)
        host.layoutSubtreeIfNeeded()
        let opened = AnimationGroupProbe.seen

        XCTAssertEqual(control.label(forSegment: 0), Self.words[0], """
            segment 0 reads \(control.label(forSegment: 0) ?? "nil") after the style moved to \
            icons and text: production never refilled the control, so nothing below is a reading.
            """)
        let implicit = opened.filter(\.implicit)
        XCTAssertEqual(implicit.count, 1, """
            a later fill of a control that has a layer opened \(implicit.count) group(s) allowing \
            implicit animation, not 1 (\(opened.map(\.description).joined(separator: "; "))). \
            None means a style chosen by right-click now snaps the segments instead of growing \
            them — and it means the layerless case above passes for a switcher that animates \
            nothing at all, which is not what it is asserting.
            """)
        XCTAssertEqual(implicit.first?.duration ?? -1, Self.animated, accuracy: 0.0001, """
            the animated fill ran for \(implicit.first?.duration ?? -1) s, not \(Self.animated): \
            the group production opens is no longer timed by \
            fillDuration(firstFill:reduceMotion:), so Reduce Motion is honoured nowhere in this \
            path.
            """)
    }

    // MARK: - The mounted switcher

    /// The switcher as a page mounts it. `style` is a stored property rather
    /// than `@State`, so replacing the host's root view is a genuine later
    /// update against the same coordinator and the same control.
    private struct Mounted: View {
        let style: ToolbarSwitcherStyle
        @State private var selection = 0

        var body: some View {
            ZStack {
                Color.clear
                HelmToolbarSwitcher("Probe", selection: $selection,
                                    segments: words.enumerated().map { index, word in
                                        HelmSwitcherSegment(index, word, symbol: "circle")
                                    })
                    .environment(\.helmSwitcherStyle, style)
            }
        }

        private var words: [String] {
            TheSwitcherOpensNoAnimationGroupWithoutALayerTests.words
        }
    }
}

/// **Every `NSAnimationContext` group opened while this is installed, with the
/// flags its caller set on the context.**
///
/// AppKit's `runAnimationGroup:` is exchanged with the stand-in below for the
/// length of one case and exchanged straight back, so nothing outside that case
/// is watched — the test target runs its cases one at a time, and the swap is
/// undone from a `defer`, which runs on a thrown `XCTUnwrap` too.
///
/// **The flags are read after the caller's own block has run**, because that is
/// where the caller sets them: `allowsImplicitAnimation` and `duration` are
/// assigned *inside* the group's body, so a reading taken before it would find
/// AppKit's defaults — `false` at 0.25 s — for every group ever opened, and the
/// check would be green against any defect at all.
///
/// The recording is not filtered here. SwiftUI and AppKit open groups of their
/// own during a mount — measured on 2026-09-19 as three per update, each
/// `allowsImplicitAnimation == false` at 0.25 s — so the cases above ask about
/// the implicit ones and report the total beside them.
private enum AnimationGroupProbe {
    struct Group: Equatable, CustomStringConvertible {
        let implicit: Bool
        let duration: TimeInterval
        var description: String {
            "allowsImplicitAnimation: \(implicit), duration: \(duration) s"
        }
    }

    /// The recording is taken under a lock and handed back as a value rather
    /// than held across anything. `NSAnimationContext` is a main-thread API and
    /// every group measured here was opened on the main thread — but while the
    /// exchange is in place this records *every* caller in the process, and an
    /// unsynchronised append from one that is not would be a crash in the suite
    /// rather than a failure anybody can read.
    nonisolated(unsafe) private static var opened: [Group] = []
    nonisolated(unsafe) private static var installed = false
    private static let lock = NSLock()

    static var seen: [Group] {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        opened = []
    }

    static func record(_ context: NSAnimationContext) {
        let group = Group(implicit: context.allowsImplicitAnimation, duration: context.duration)
        lock.lock()
        defer { lock.unlock() }
        opened.append(group)
    }

    /// AppKit's own method and the stand-in, both as class methods.
    private static var pair: (Method, Method)? {
        guard let real = class_getClassMethod(NSAnimationContext.self,
                                              NSSelectorFromString("runAnimationGroup:")),
              let stand = class_getClassMethod(NSAnimationContext.self,
                                               NSSelectorFromString("helmProbeRunAnimationGroup:"))
        else { return nil }
        return (real, stand)
    }

    static func install() {
        clear()
        guard !installed, let (real, stand) = pair else { return }
        method_exchangeImplementations(real, stand)
        installed = true
    }

    static func remove() {
        guard installed, let (real, stand) = pair else { return }
        method_exchangeImplementations(real, stand)
        installed = false
        clear()
    }
}

extension NSAnimationContext {
    /// The stand-in. While the probe is installed this selector carries
    /// AppKit's own implementation and `runAnimationGroup:` carries this body,
    /// so the call below runs the real thing — `dynamic`, because a statically
    /// dispatched call would re-enter this body instead of the implementation
    /// now behind the selector.
    @objc dynamic class func helmProbeRunAnimationGroup(
        _ changes: @escaping @convention(block) (NSAnimationContext) -> Void) {
        NSAnimationContext.helmProbeRunAnimationGroup { context in
            changes(context)
            AnimationGroupProbe.record(context)
        }
    }
}

import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The toolbar switcher's first fill is not an animation, and every later one
/// still is.**
///
/// # What this change is, and what it is not
///
/// `makeNSView` hands back an empty `NSSegmentedControl` and the first
/// `updateNSView` is what puts four segments in it. That first fill ran inside
/// `NSAnimationContext.runAnimationGroup` with `allowsImplicitAnimation = true`,
/// so AppKit was asked to animate the control from *nothing* to its measured
/// size — animating the first measurement, the thing CLAUDE.md forbids in its
/// own words. Not asking for that any more is the whole of what this change
/// does.
///
/// **It was not the cause of the jump the owner reported, and that cause is
/// still not established.** Designer measured the built dev app before and
/// after, at 60 fps, and the label band's displacement is unchanged either way.
/// A first open in Dark, three fresh launches: displaced in 15/16/15 frames of
/// 79/79/54 for 242/267/258 ms after, against 15/16/16 of 67/67/65 for
/// 242/250/250 ms before. A window closed and reopened, six readings:
/// 15,16,16,16,15,15 frames for 258,275,267,258,267,250 ms after, against
/// 17,16,16,16,17,16 for 283,258,267,258,275,258 ms before. A sidebar return,
/// where the control already exists, stayed clean — 0 displaced of 631 frames
/// in Dark and 0 of 804 in Light. Light is worse than Dark and designer
/// measured it too, through the app's own appearance setting in the dev domain.
/// An earlier round of "before" numbers, which this file used to quote, is
/// withdrawn: the tool that produced them indexed its X axis wrongly.
///
/// A *mechanism* was found on 2026-09-19, by recording the layer's own
/// animation keys on the built dev app, and it is worth keeping written down
/// because it is hard-won — but it is not the jump. Five `updateNSView` calls
/// land within 52.2 ms of a module opening and the control has no layer in any
/// of them, so `hasFilled`, true after the first, sent calls two to five into
/// the animation group below and the layer was born *inside* that 0.22 s
/// transaction, which put its duration on the layer's first `bounds`
/// animation, `{{0,0},{0,0}}` to `370.5 × 36.0`. Designer confirmed that
/// in-process with a probe carrying a switch: the animation key is there with
/// the branch as it stands and gone with it silenced, reproducibly.
///
/// **And the screen does not show it.** Designer filmed the built dev app
/// A/B/A on 2026-09-19 — build 1511, then build 1514 with that branch
/// silenced, then 1511 rebuilt from a clone of commit 4c15aa1c and
/// reinstalled, the build number read out of `Info.plist` on every run. The
/// switcher's track measures 370.0 pt in the very first composited frame of
/// 1511 *and* of 1514, so a capsule growing from zero is on film in neither.
/// Silencing the branch also cost the sidebar return, clean in every reading
/// before it, 14/16/15/14 displaced frames in Dark and 15/14/13/15 in Light
/// against 0 throughout in 1511, and it was reverted. So: the mechanism is
/// real and in-process, it is not what a person sees, and what the owner sees
/// is still unexplained. Anything that claims to fix it has to be measured on
/// film, on the gestures above, before it is believed.
///
/// So no case here may be read as a guard on what the owner saw. What they
/// guard is narrower and worth keeping on its own — the first fill asks AppKit
/// for no animation, and every later fill still asks for one.
///
/// # What can be measured here and what cannot
///
/// **The displacement itself cannot.** Probed 2026-09-19 offscreen: an
/// `NSSegmentedControl` mounted in an `NSHostingView` has `layer == nil` even
/// with `wantsLayer` set on the host, the bridged
/// `_NSCoreHostingView<AppKitSegmentedControl>` under it carries no animation on
/// any layer or sublayer, and `allowsImplicitAnimation` needs a layer to do
/// anything at all. **That is a fact about an `NSHostingView` and not about the
/// control**, and it was read as one for a while: in the window's own toolbar
/// the same control reads `layer != nil` with one sublayer once the bar has
/// inserted it, which is why a right-click style change animates on screen and
/// nothing here can see it. So no offscreen check can watch the segments move —
/// including the fill this file's own subject is about. The
/// frames designer counted were taken on a window and are the only evidence
/// there is about the band — and they show it moving with this change and
/// without it alike.
///
/// What is left is three things that can each be made to fail:
///
/// 1. the decision, `fillDuration(firstFill:reduceMotion:)`, over all four
///    arguments;
/// 2. that SwiftUI really drives `updateNSView` over a live control, and that
///    the first update leaves the coordinator's flag set behind it — read off a
///    mounted control rather than off the function. **Which of the two branches
///    that first fill took is not visible from here**: the `Witness` comparison
///    production makes with `segments.firstIndex` sits above both of them, so
///    the context it reads is the ambient one whichever side ran. Only the
///    source reading below pins where each `Self.fill` sits;
/// 3. that a later fill still opens the animation context, so a repair that
///    deleted the animation outright is caught. This one is read off the source,
///    because the animation it asks for is not observable without a window; the
///    check is on what the code asks AppKit for, and it says so where it fails.
@MainActor
final class TheSwitcherFillsItsFirstFrameWithoutAnimationTests: XCTestCase {

    private static let file = "Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift"

    /// The duration a later fill is given. `HelmMotion.interface` carries the
    /// same number as a SwiftUI curve; this is an AppKit `NSAnimationContext`
    /// duration and cannot be read out of an `Animation`, so it is pinned here
    /// and pinned again below as the one literal in the file.
    private static let animated: TimeInterval = 0.22

    // MARK: - 1. The decision, over all four arguments

    /// Every combination of the two arguments, because three of the four give 0
    /// and only the fourth animates — a function that dropped either term reads
    /// as correct against any single row.
    ///
    /// **What a total failure prints.** A `fillDuration` that ignored
    /// `firstFill` — the defect's own spelling, `reduceMotion ? 0 : 0.22` —
    /// fails the `firstFill: true, reduceMotion: false` row with "the first fill
    /// asked for 0.22 s". One that ignored `reduceMotion` fails the
    /// `firstFill: false, reduceMotion: true` row the same way. One that
    /// returned 0 for everything fails the last row with "a later fill asked for
    /// 0 s of animation". None of the three can print what a pass prints, which
    /// is nothing.
    func testFillDurationIsZeroOnAFirstFillAndUnderReduceMotionAndAnimatesOnlyOtherwise() {
        for firstFill in [true, false] {
            for reduceMotion in [true, false] {
                let duration = HelmToolbarSwitcher<Int>.fillDuration(firstFill: firstFill,
                                                                    reduceMotion: reduceMotion)
                let arguments = "firstFill: \(firstFill), reduceMotion: \(reduceMotion)"
                if firstFill || reduceMotion {
                    XCTAssertEqual(duration, 0, """
                        fillDuration(\(arguments)) asked for \(duration) s. \
                        A first fill has nothing to animate from — the control is empty, so the \
                        animation would run from the unmeasured layout, which CLAUDE.md forbids \
                        — and Reduce Motion is a medical setting, not a preference.
                        """)
                } else {
                    XCTAssertEqual(duration, Self.animated, accuracy: 0.0001, """
                        fillDuration(\(arguments)) asked for \(duration) s, not \(Self.animated). \
                        A later fill rewrites the segments of a control that is already on screen \
                        — a style chosen by right-click — and that is a change the word should \
                        arrive with rather than snap into.
                        """)
                    XCTAssertGreaterThan(duration, 0, """
                        fillDuration(\(arguments)) is 0: every fill is now unanimated, so a style \
                        change snaps. The first fill is the only one that must not animate.
                        """)
                }
            }
        }
    }

    /// The one spelling of the duration, and it is inside the decision.
    ///
    /// Architect's ask, and it is what stops the pure function above from being
    /// a tautology on its own: a second `0.22` in the file is a second place
    /// that decides how long a fill takes, which is how the defect was written
    /// in the first place — `updateNSView` carried its own
    /// `HelmMotion.reduceMotion ? 0 : 0.22` and no caller could tell it apart
    /// from a decision made once.
    func testTheDurationIsWrittenOnceAndInsideTheDecision() throws {
        let code = SwiftSource.code(try RepoSource.text(of: Self.file))
        let literal = "\(Self.animated)"
        XCTAssertEqual(Self.count(of: literal, in: code), 1, """
            \(literal) is written \(Self.count(of: literal, in: code)) times in \(Self.file). \
            The duration of a fill is decided in fillDuration(firstFill:reduceMotion:) and \
            nowhere else — a second spelling is a second decision.
            """)
        let decision = try XCTUnwrap(SwiftSource.body(of: "fillDuration", in: code),
                                     "\(Self.file) no longer declares fillDuration")
        XCTAssertEqual(Self.count(of: literal, in: decision), 1, """
            the one \(literal) in \(Self.file) is not inside fillDuration's body, so the function \
            the tests call is not the one production's duration comes from.
            """)
    }

    // MARK: - 2. Production takes the unanimated path

    /// A fresh coordinator has not filled anything — so the flag is per mounted
    /// control, and a second window's switcher gets its own unanimated first
    /// frame rather than inheriting another window's. This says nothing about
    /// what the owner sees; it says the flag sits where the change needs it.
    func testAFreshCoordinatorHasNotFilledYet() {
        let switcher = HelmToolbarSwitcher("Probe", selection: .constant(0),
                                           segments: [HelmSwitcherSegment(0, "One", symbol: "circle")])
        XCTAssertFalse(switcher.makeCoordinator().hasFilled, """
            a switcher's coordinator starts out believing its control is already filled, so the \
            very first fill — the empty control — takes the animated path.
            """)
    }

    /// SwiftUI drives the real `updateNSView` against a real control, and the
    /// first fill happens outside any implicit-animation context.
    ///
    /// **Where the reading is taken.** `updateNSView` finds the selected segment
    /// with `segments.firstIndex { $0.value == selection }`, so the selection
    /// type's own `==` runs once per update, inside whatever animation context
    /// the update body is in. In the defect that comparison sat *inside* the
    /// animation group and reads back `allowsImplicitAnimation == true`,
    /// `duration == 0.22`; with the fix it reads the ambient context, which is
    /// `false` at AppKit's default 0.25 s. That is a hook and not the subject —
    /// so the source check below is what pins where `Self.fill` sits, and this
    /// one is what proves the path is actually walked by SwiftUI rather than by
    /// a test calling a static function.
    func testTheFirstUpdateOfALiveControlRunsOutsideAnyImplicitAnimation() throws {
        Witness.readings.clear()
        let host = NSHostingView(rootView: Mounted(style: .text))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()

        // Assert the subject happened before asserting an absence: an empty
        // reading list is what a control nobody filled would also produce.
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        XCTAssertEqual(control.segmentCount, Mounted.words.count, """
            the mounted control holds \(control.segmentCount) segments, not \(Mounted.words.count): \
            production never filled it, so nothing below is a reading of the first fill.
            """)
        let coordinator = try XCTUnwrap(control.target as? HelmToolbarSwitcher<Witness>.Coordinator,
                                        "the control's target is not the switcher's coordinator")
        XCTAssertTrue(coordinator.hasFilled, """
            the coordinator still reports no fill after SwiftUI filled the control, so the flag \
            production branches on is not the one the fill sets — every later fill will take the \
            first-fill path and a style change will snap.
            """)

        let readings = Witness.readings.taken
        XCTAssertFalse(readings.isEmpty, """
            the update body compared no selection value, so this check read nothing. The hook is \
            gone — find the update's new observation point rather than trusting this pass.
            """)
        XCTAssertEqual(readings.filter(\.implicit), [], """
            the first update ran inside an implicit-animation context \
            (\(readings.map { "\($0.duration) s" }.joined(separator: ", "))): AppKit is being asked \
            to animate a control from zero segments to its measured size, which is animating the \
            first measurement.
            """)
    }

    /// **A window closed and reopened**, which is the gesture a sidebar return
    /// does not cover — designer measured it displaced in 15,16,16,16,15,15
    /// frames over six readings, and in 17,16,16,16,17,16 before this change, so
    /// what is guarded here is the unanimated fill and not that displacement.
    ///
    /// `helmIdlesOffScreen()` (`OffScreenIdle`) unmounts a page's subtree while
    /// its window is off screen with `if seen { content }`, and that shape is
    /// what is mounted here. The whole fix rests on the unmount taking the
    /// coordinator with it: a coordinator that survived would come back with
    /// `hasFilled` already true, and the new empty control's first fill would
    /// animate from zero all over again — the fix would cover a first open and
    /// not a reopen.
    ///
    /// So the identities are asserted both ways round. A future SwiftUI that
    /// keeps the coordinator across an unmount fails here with the reason, which
    /// is the only warning there would be.
    func testASubtreeUnmountedAndRemountedGetsAFreshUnanimatedFill() throws {
        Witness.readings.clear()
        let host = NSHostingView(rootView: Mounted(style: .text, seen: true))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()
        let firstControl = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                         "the switcher put no NSSegmentedControl in the tree")
        let firstCoordinator = try XCTUnwrap(firstControl.target as AnyObject?)

        host.rootView = Mounted(style: .text, seen: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.everyView(ofType: NSSegmentedControl.self).count, 0, """
            the switcher is still in the tree with its subtree unmounted, so what follows is not a \
            remount and this check saw nothing.
            """)

        Witness.readings.clear()
        host.rootView = Mounted(style: .text, seen: true)
        host.layoutSubtreeIfNeeded()
        let second = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                   "the remounted switcher put no NSSegmentedControl in the tree")
        XCTAssertEqual(second.segmentCount, Mounted.words.count,
                       "the remounted control was never filled, so nothing below is a reading")
        XCTAssertFalse(second === firstControl, """
            the remounted switcher is the same NSSegmentedControl as before the unmount, so it was \
            never empty and this check cannot see a first fill.
            """)
        let secondCoordinator = try XCTUnwrap(second.target as AnyObject?)
        XCTAssertFalse(secondCoordinator === firstCoordinator, """
            the remounted switcher kept the coordinator from before the unmount, so its hasFilled \
            is already true against a control that is empty again — a window closed and reopened \
            would animate its first fill from zero, so the change would cover a first open only.
            """)

        let readings = Witness.readings.taken
        XCTAssertFalse(readings.isEmpty, """
            the remounted update compared no selection value, so this check read nothing.
            """)
        XCTAssertEqual(readings.filter(\.implicit), [], """
            the first update after a remount ran inside an implicit-animation context \
            (\(readings.map { "\($0.duration) s" }.joined(separator: ", "))): a window closed and \
            reopened animates its switcher from zero segments again.
            """)
    }

    // MARK: - 3. A later fill still animates

    /// Exactly two fills in `updateNSView`, exactly one animation group, and
    /// exactly one fill inside it.
    ///
    /// Counted rather than named: the shape is "one fill animated, one not",
    /// which is what a repair must not collapse in either direction. The defect
    /// collapses it one way — one fill, inside the group — and a repair that
    /// deleted the animation outright collapses it the other, with no group at
    /// all; both print here, and neither prints what a pass prints.
    ///
    /// This is a source reading and it says so: the animation it guards is a
    /// Core Animation animation on a layer, and a control mounted offscreen has
    /// no layer to carry one. What is asserted is what production asks AppKit
    /// for.
    func testExactlyOneOfTheTwoFillsIsInsideTheAnimationGroup() throws {
        let code = SwiftSource.code(try RepoSource.text(of: Self.file))
        let update = try XCTUnwrap(SwiftSource.body(of: "updateNSView", in: code),
                                   "\(Self.file) no longer declares updateNSView")
        XCTAssertEqual(Self.count(of: "Self.fill(", in: update), 2, """
            updateNSView fills the control \(Self.count(of: "Self.fill(", in: update)) time(s). \
            It must be two: the first fill of an empty control, unanimated, and every later fill \
            of a live one, animated.
            """)
        XCTAssertEqual(Self.count(of: "NSAnimationContext.runAnimationGroup", in: update), 1, """
            updateNSView opens \(Self.count(of: "NSAnimationContext.runAnimationGroup", in: update)) \
            animation group(s). None means a style chosen by right-click now snaps the segments \
            instead of growing them; two means the first fill is animated again.
            """)
        let group = try XCTUnwrap(Self.block(after: "NSAnimationContext.runAnimationGroup", in: update),
                                  "the animation group in updateNSView has no matched body")
        XCTAssertEqual(Self.count(of: "Self.fill(", in: group), 1, """
            \(Self.count(of: "Self.fill(", in: group)) of the two fills sit inside the animation \
            group. Exactly one must: the first fill has an empty control to animate from and the \
            later fill has a measured one.
            """)
        XCTAssertTrue(group.contains("allowsImplicitAnimation = true"), """
            the later fill's animation group no longer allows implicit animation, so the group is \
            open over a fill that AppKit will not animate — the word arrives at full strength on a \
            control that is still growing.
            """)
        XCTAssertTrue(group.contains("fillDuration(firstFill: false"), """
            the later fill's duration does not come from fillDuration(firstFill:reduceMotion:), so \
            the function the tests above pin is not what production's animation is timed by — and \
            Reduce Motion is honoured only where that function is asked.
            """)
    }

    // MARK: - The mounted switcher

    /// A selection value that records the animation context it is compared in.
    ///
    /// `nonisolated(unsafe)` because `Hashable.==` is nonisolated and this is
    /// read and written on the main thread only — the update body runs there.
    struct Witness: Hashable {
        let index: Int

        struct Reading: Equatable {
            let implicit: Bool
            let duration: TimeInterval
        }

        final class Log: @unchecked Sendable {
            private var entries: [Reading] = []
            func add(_ reading: Reading) { entries.append(reading) }
            func clear() { entries = [] }
            var taken: [Reading] { entries }
        }

        nonisolated(unsafe) static let readings = Log()

        static func == (lhs: Witness, rhs: Witness) -> Bool {
            let context = NSAnimationContext.current
            readings.add(Reading(implicit: context.allowsImplicitAnimation,
                                 duration: context.duration))
            return lhs.index == rhs.index
        }

        func hash(into hasher: inout Hasher) { hasher.combine(index) }
    }

    /// The switcher as a page mounts it, inside the shape `OffScreenIdle` gives
    /// it: a `ZStack` whose content is there only while the window is seen.
    ///
    /// The style and `seen` are stored properties rather than `@State`, so
    /// replacing the host's root view is a genuine later update — against the
    /// same coordinator where the switcher stays mounted, and against a new one
    /// where it does not.
    ///
    /// The words are not asserted anywhere, which is why they are not taken
    /// through `AppLanguage` — nothing here reads a visible string.
    struct Mounted: View {
        static let words = ["Installed", "Updates", "Search"]
        let style: ToolbarSwitcherStyle
        var seen = true
        @State private var selection = Witness(index: 0)

        var body: some View {
            ZStack {
                Color.clear
                if seen {
                    HelmToolbarSwitcher("Probe", selection: $selection,
                                        segments: Self.words.enumerated().map { index, word in
                                            HelmSwitcherSegment(Witness(index: index), word,
                                                                symbol: "circle")
                                        })
                        .environment(\.helmSwitcherStyle, style)
                }
            }
        }
    }

    // MARK: - Reading the source

    private static func count(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var found = 0
        var cursor = text.startIndex
        while let range = text.range(of: needle, range: cursor..<text.endIndex) {
            found += 1
            cursor = range.upperBound
        }
        return found
    }

    /// The brace-matched block opened by the first `{` at or after `marker`.
    ///
    /// Run over `SwiftSource.code`, where comments and the insides of string
    /// literals are already blanked, so a brace in either cannot throw the
    /// count off.
    private static func block(after marker: String, in code: String) -> String? {
        guard let start = code.range(of: marker) else { return nil }
        let characters = Array(code[start.upperBound...])
        guard let open = characters.firstIndex(of: "{") else { return nil }
        var depth = 0
        for index in open..<characters.count {
            if characters[index] == "{" { depth += 1 }
            if characters[index] == "}" {
                depth -= 1
                if depth == 0 { return String(characters[(open + 1)..<index]) }
            }
        }
        return nil
    }
}

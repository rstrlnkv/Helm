import Foundation
import HelmTestSupport
import XCTest

/// A control the keyboard cannot reach is a control some people do not have.
///
/// The tell is a tap gesture wearing a button's accessibility clothes. A
/// `.onTapGesture` carries no button trait, takes no focus and is invisible to
/// Full Keyboard Access — so `.accessibilityElement()` plus
/// `.accessibilityAction` fixes VoiceOver, which is the loud half, and leaves
/// Tab navigation exactly as broken as it was. The comment above the offending
/// line in `IconPickers` said all of this ("A real button, not a tap gesture: a
/// gesture carries no button trait, takes no focus and cannot be reached from
/// the keyboard") and the next line was `.onTapGesture`, which is how a
/// half-applied fix survives review.
///
/// So: **if it is worth an accessibility action, it is worth being a `Button`.**
/// The two go together — something given an action is something a person is
/// meant to activate, and `Button` is what makes that reachable by every input
/// the system has, for free.
///
/// A source scan, for the reason `NamedControlsTests` gives: the defect is
/// invisible at runtime to anyone who is using a mouse.
///
/// **Scope: the design system and the UI half of every module.** It was the
/// design system alone, because the three module files that had this defect were
/// "owned by other branches in flight" and failing the suite for work nobody
/// could touch is how a check gets switched off by hand. Those branches have
/// landed, so the scan reads `UISources.files()` now — the same enumeration the
/// v3 ladders share, HelmUI plus `Sources/Modules/*/UI`, taken from
/// `Package.swift` so a tenth module arrives here without anybody adding it.
///
/// What became of the three files the old exclusion named, because "widened and
/// green" must not be read as "all three were fixed":
///
/// - `KeepAwakeSettingsPage` has no tap gesture left at all. Fixed.
/// - `DiskResultView` was the recorded offender and is fixed: the row's drill is
///   a `Button` now, and the double-click that was the only way in is a mouse
///   shortcut for it. Its `.accessibilityActions` went with the fix rather than
///   beside it — a Button is reachable by VoiceOver *and* by the keyboard, so
///   keeping the action would have been the same drill written down twice.
/// - `RingView`'s tap gesture is **not** reported, and not because it is fine:
///   its chain carries no action of its own. The ring is a `Canvas`, and its
///   activation is offered through `accessibilityChildren` — `Color.clear`
///   elements carrying `.isButton` and `.accessibilityAction`, declared in
///   another property (`RingView.swift:78`–`91`). That is a different shape from
///   the one this rule reads, and whether a virtual accessibility element with
///   an action is reachable by Full Keyboard Access is a question about macOS
///   this suite cannot answer without changing a setting on the machine it runs
///   on. **Do not read its absence as a verdict.**
///
///   Two ways of answering it without touching that setting were tried on
///   2026-08-12 and **both are blind**, which is worth writing down so nobody
///   spends the afternoon twice:
///
///   1. *Walking the hosted view's accessibility children in this process.* The
///      whole subtree of an `NSHostingView` of the result screen comes back as
///      one `AXGroup` and nothing under it — SwiftUI's elements are not objects
///      the view vends, so there is nothing to ask. Asking the accessibility API
///      about one's own process does not work either: the element for our own
///      pid answers no role at all.
///   2. *Reading, from a second process, whether the focused attribute is
///      settable on each element* — which is what keyboard focus moves between.
///      The shape reproduces faithfully: the ring's virtual children appear as
///      two buttons under a group. But **a real `Button` mounted beside them
///      reads exactly the same**, false for both, so the reading separates
///      nothing. A control that answers like the suspect is an instrument, not
///      an answer.
///
///   What is left is the direct one: switch Full Keyboard Access on, press Tab,
///   and read where the focus went — a change to the machine, so it is asked for
///   rather than done.
///
/// A tap gesture that merely duplicates a real control in the same row — the
/// uninstaller's row tap, which sits beside its own checkbox — is not this
/// defect and carries no accessibility action, so the rule does not catch it.
final class KeyboardReachableControlsTests: XCTestCase {

    /// **Recorded 2026-08-12 as 1, lowered to 0 the same day by the commit that
    /// fixed the one site.**
    ///
    /// It was `DiskResultView`'s row: a double-click that drilled into a folder
    /// or revealed a file, with `.accessibilityActions` under it handing the
    /// drill to VoiceOver and nothing at all to the keyboard. The row carries a
    /// `Button` now.
    ///
    /// This number is only ever lowered, by the commit that lowers it. Raising it
    /// to admit a new offender is writing the defect down twice.
    private static let recorded = 0

    /// And *which* file, so a new violation somewhere else cannot hide behind a
    /// count that stayed at one while the recorded site was fixed in the same
    /// commit. A bare ratchet is blind to a swap. Empty, now that the count is.
    private static let recordedFiles: Set<String> = []

    // MARK: - The finding

    /// One control activated by a tap gesture, where it was written.
    private struct Offender: Hashable {
        let file: String
        let line: Int
        let text: String

        var described: String { "  \(file):\(line)  \(text.prefix(96))" }
    }

    /// Every file a control can be drawn in: HelmUI, and the UI half of every
    /// module in `Package.swift`.
    ///
    /// **One function, read by the scan and by the test that checks the scan's
    /// reach.** They were two calls to `UISources.files()`, and narrowing the
    /// scan's own list back to the design system — the very regression the
    /// widening exists to prevent — left `testTheScanReadsTheFilesTheRuleIsAbout`
    /// green, because it was looking at a list nothing else used. A check on an
    /// instrument has to hold the instrument.
    private func uiFiles() throws -> [String] { try UISources.files() }

    private func offenders() throws -> [Offender] {
        var read: [(String, [String])] = []
        for file in try uiFiles() {
            read.append((file, try RepoSource.lines(of: file)))
        }
        return Self.offenders(in: read)
    }

    /// The scan, over text, so it can be shown the shapes it is looking for.
    private static func offenders(in files: [(String, [String])]) -> [Offender] {
        var out: [Offender] = []
        for (file, lines) in files {
            for (index, raw) in lines.enumerated() {
                let code = RepoSource.code(raw)
                guard code.contains(".onTapGesture") else { continue }
                let chain = SwiftSource.modifierChain(from: index, in: lines)
                guard chain.contains("accessibilityAction")
                        || chain.contains("isButton") else { continue }
                out.append(Offender(file: file, line: index + 1,
                                    text: code.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    // The chain is `SwiftSource.modifierChain` now, and the reasoning that used
    // to stand here — depth rather than indent, because the closing brace of a
    // multi-line closure ends an indent walk and hides everything under it —
    // moved with it when a second accessibility guard needed the same reading.
    // `testAMultiLineHandlerDoesNotEndTheChain` below still holds it from here,
    // which is the point of moving it rather than copying it.

    // MARK: - The ratchet

    func testNoNewControlIsActivatedOnlyByATapGesture() throws {
        let found = try offenders()

        XCTAssertLessThanOrEqual(found.count, Self.recorded, """
            \(found.count) controls carry an accessibility action and are activated by a tap \
            gesture, so Full Keyboard Access cannot reach them at all; the recorded number is \
            \(Self.recorded). Make them Buttons.
            This number is only ever lowered, by the commit that lowers it.
            \(found.map(\.described).sorted().joined(separator: "\n"))
            """)
    }

    /// And it is the recorded file, not a different one of the same count.
    func testEveryOffenderIsTheOneTheRecordNames() throws {
        let unexpected = try offenders().filter { !Self.recordedFiles.contains($0.file) }

        XCTAssertEqual(unexpected, [], """
            a control the keyboard cannot reach in a file the record does not name. The count \
            may not have moved — a site fixed and a site added is still one — so this is the \
            half that catches it:
            \(unexpected.map(\.described).sorted().joined(separator: "\n"))
            """)
    }

    /// **And the record still names something that is there.** While the record
    /// held `DiskResultView` this was the whole guard against a ratchet that is
    /// green because it is blind: a scan that has quietly stopped matching, a
    /// `UISources` that lost the module directories, a `RepoSource` returning
    /// nothing, all read as "nothing left to fix" — `<=` cannot tell clean from
    /// blind.
    ///
    /// The record is empty now, so the loop below guards a future entry and
    /// nothing today; `testTheScanIsReadingTheTextOfTheseFiles` is what took over
    /// its job, because a test that iterates an empty set is not a check.
    func testTheRecordNamesNothingThatHasGone() throws {
        let found = try offenders()
        for file in Self.recordedFiles {
            XCTAssertTrue(found.contains { $0.file == file }, """
                \(file) is recorded as carrying a tap-gesture-only control and the scan finds \
                none. Either it was fixed — lower `recorded` and take the file off \
                `recordedFiles` in that commit — or the scan has stopped reading the tree, in \
                which case the ratchet above is passing over an empty list.
                found: \(found.map(\.described).sorted().joined(separator: "\n"))
                """)
        }
    }

    /// **A zero has to be a zero somebody read, not a zero nobody looked for.**
    ///
    /// With the record empty, every test above this line passes on a scan that
    /// reads nothing at all: `uiFiles()` can list fifty files and `offenders()`
    /// still find none if the lines come back empty. The fixtures prove the
    /// matcher; the file list proves the enumeration; this is the third leg —
    /// that the text of those files reaches the matcher.
    ///
    /// The tap gestures it counts are the legitimate ones, which is why the
    /// number is not recorded: a mouse shortcut beside a real control is the
    /// shape this rule deliberately allows, and there are several in the tree.
    /// The day there is not one left, this fails and says so — and that is a
    /// decision to make, not a line to delete: a rule about tap gestures in a
    /// tree with no tap gestures is guarding nothing.
    func testTheScanIsReadingTheTextOfTheseFiles() throws {
        var gestures = 0
        for file in try uiFiles() {
            let lines = try RepoSource.lines(of: file)
            XCTAssertFalse(lines.isEmpty, "\(file) came back as no lines at all")
            gestures += lines.filter { RepoSource.code($0).contains(".onTapGesture") }.count
        }

        XCTAssertGreaterThan(gestures, 0, """
            not one `.onTapGesture` in the whole of HelmUI and the module UIs. Either the source \
            is not reaching the matcher — in which case the ratchet above is counting an empty \
            list and the recorded 0 means nothing — or the app really has none left, and this \
            rule now guards a shape the codebase does not use
            """)
    }

    // MARK: - The scan is looking at the app

    /// Both icon pickers are the reason this exists, and the module UIs are what
    /// it was widened to. A guard that has stopped reading the source passes
    /// forever, and one still reading half the tree passes for half a reason.
    func testTheScanReadsTheFilesTheRuleIsAbout() throws {
        let files = try uiFiles()
        let names = Set(files.map { URL(fileURLWithPath: $0).lastPathComponent })

        for expected in ["IconPickers.swift",          // the design system, where it began
                         "DiskResultView.swift",       // the recorded offender
                         "RingView.swift",             // named by the old exclusion
                         "KeepAwakeSettingsPage.swift"] {
            XCTAssertTrue(names.contains(expected), "\(expected) is in no file this scan reads")
        }

        for module in try UISources.moduleNames() {
            XCTAssertTrue(files.contains { $0.hasPrefix("Sources/Modules/\(module)/UI/") },
                          "\(module)'s UI is not being read, so the widening covers eight "
                          + "modules and says nine")
        }
        XCTAssertGreaterThan(files.count, 40, "the tree moved: \(files.count) files")
    }

    // MARK: - The rule can still fail

    /// The shape the pickers had, run past the same matcher, is reported.
    ///
    /// Fixtures rather than the tree: the offence has to stay writable after the
    /// tree is clean, or the day the last one is fixed is the day the rule stops
    /// being able to fail at all.
    func testTheRuleRecognisesTheShapeItWasWrittenFor() {
        let shipped = """
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .help(s.label)
                .onTapGesture { selection = s.rawValue }
                .accessibilityElement()
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { selection = s.rawValue }
        """

        XCTAssertEqual(scanned(shipped).map(\.line), [3],
                       "the scan cannot see the shape it was written from")
    }

    /// **The blind spot the old walk had, as a fixture.** `RingView`'s gesture
    /// takes a point and needs a body, and a chain walked by indent ended at its
    /// closing brace — so an action three lines further down was invisible. Any
    /// offender could have been hidden from this rule by pressing return.
    func testAMultiLineHandlerDoesNotEndTheChain() {
        let ring = """
                .contentShape(Rectangle())
                .onTapGesture { point in
                    guard let hit = segment(at: point) else { return }
                    open(hit)
                }
                // A Canvas is one opaque rectangle to VoiceOver.
                .accessibilityElement()
                .accessibilityAction { open(focus) }
        """

        XCTAssertEqual(scanned(ring).map(\.line), [2], """
            a tap gesture whose handler spans lines is not being read to the end of its own \
            chain, so the accessibility action three lines under it is invisible and the rule \
            cannot fail on any control that needed two lines to say what it does
            """)
    }

    /// And the three shapes that are not the defect.
    func testTheScanDoesNotReportTheFixOrTheDuplicate() {
        let realButton = """
                Button { channel = option } label: { Text(name) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        """
        let besideItsOwnControl = """
                .frame(minHeight: 34)
                .contentShape(Rectangle())
                .onTapGesture { uvm.toggleChecked(app.bundleID) }
        """
        let anotherChainEntirely = """
                .onTapGesture { NotificationCenter.default.post(name: .dismiss, object: nil) }
                Spacer()
                Toggle(isOn: $on) { Text(label) }
                    .accessibilityAddTraits(.isButton)
        """
        let onlyAComment = """
                // A real button, not a tap gesture: a gesture carries no button trait and
                // `.accessibilityAction` fixes VoiceOver only — `.onTapGesture` plus
                // `.accessibilityAction` is the defect this rule reads.
                Button(action: pick) { plate }
        """

        XCTAssertEqual(scanned(realButton).count, 0,
                       "a `Button` given the selected trait is the fix, not a finding")
        XCTAssertEqual(scanned(besideItsOwnControl).count, 0,
                       "a row tap beside its own checkbox carries no action and is a shortcut, "
                       + "not the only way in")
        XCTAssertEqual(scanned(anotherChainEntirely).count, 0,
                       "the chain ran past the view it belongs to and picked up a trait from "
                       + "the next control down the stack")
        XCTAssertEqual(scanned(onlyAComment).count, 0,
                       "the scan is reading comments, so the rule reports its own explanation")
    }

    private func scanned(_ text: String) -> [Offender] {
        Self.offenders(in: [("fixture.swift", text.components(separatedBy: "\n"))])
    }
}

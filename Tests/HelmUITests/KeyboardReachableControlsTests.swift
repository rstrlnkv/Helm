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
/// - `DiskResultView` still has one, and it is the recorded offender below.
/// - `RingView`'s tap gesture is **not** reported, and not because it is fine:
///   its chain carries no action of its own. The ring is a `Canvas`, and its
///   activation is offered through `accessibilityChildren` — `Color.clear`
///   elements carrying `.isButton` and `.accessibilityAction`, declared in
///   another property (`RingView.swift:78`–`91`). That is a different shape from
///   the one this rule reads, and whether a virtual accessibility element with
///   an action is reachable by Full Keyboard Access is a question about macOS
///   this suite cannot answer without changing a setting on the machine it runs
///   on. It is reported to `helm-engineer` as prose rather than pinned here on a
///   premise nobody has measured. **Do not read its absence as a verdict.**
///
/// A tap gesture that merely duplicates a real control in the same row — the
/// uninstaller's row tap, which sits beside its own checkbox — is not this
/// defect and carries no accessibility action, so the rule does not catch it.
final class KeyboardReachableControlsTests: XCTestCase {

    /// **Recorded 2026-08-12, three consecutive runs in agreement: 1.**
    ///
    /// `DiskResultView.swift:410` — the double-click that drills into a folder or
    /// reveals a file in Finder, with `.accessibilityActions` under it offering
    /// the drill to VoiceOver. Double-click is mouse-only by construction, so the
    /// row's primary gesture has no keyboard equivalent; the context menu beside
    /// it is reachable, which is what keeps this a finding rather than an outage.
    ///
    /// This number is only ever lowered, by the commit that lowers it. Raising it
    /// to admit a new offender is writing the defect down twice.
    private static let recorded = 1

    /// And *which* file, so a new violation somewhere else cannot hide behind a
    /// count that stayed at one while the recorded site was fixed in the same
    /// commit. A bare ratchet is blind to a swap.
    private static let recordedFiles: Set<String> = ["Sources/Modules/Disk/UI/DiskResultView.swift"]

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
                let chain = self.chain(from: index, in: lines)
                guard chain.contains("accessibilityAction")
                        || chain.contains("isButton") else { continue }
                out.append(Offender(file: file, line: index + 1,
                                    text: code.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    /// The modifier chain the tap gesture belongs to, by brace depth rather than
    /// by indent.
    ///
    /// **Indent was not enough, and the widened scan is where it stops being
    /// enough.** The old walk ended the chain at the first line no deeper than
    /// the gesture's own that did not begin with a dot — and the closing brace of
    /// a multi-line closure is exactly that, so
    ///
    /// ```swift
    /// .onTapGesture { point in
    ///     open(segment(at: point))
    /// }
    /// .accessibilityAction { … }
    /// ```
    ///
    /// — `RingView`'s shape, a gesture that takes a location and therefore cannot
    /// be a one-liner — was read as a chain of one line with no action in it. The
    /// rule would have been unable to fail on any control whose handler needed a
    /// second line, which is most of them. Depth counting is what
    /// `AnImposedPickerWidthFitsItsLabelsTests` walks chains with, for the same
    /// reason.
    ///
    /// Comments are stripped by `RepoSource.code` first, and that is not
    /// optional: the rule is explained above by quoting the very thing it
    /// forbids, so a scan that read comments would report its own reasoning.
    private static func chain(from index: Int, in lines: [String]) -> String {
        var text = RepoSource.code(lines[index])
        var depth = braces(in: text)
        for raw in lines.dropFirst(index + 1) {
            let code = RepoSource.code(raw)
            let body = code.trimmingCharacters(in: .whitespaces)
            // Inside a closure of the chain: every line belongs to it.
            if depth > 0 {
                text += "\n" + code
                depth += braces(in: code)
                continue
            }
            // At depth zero only a further modifier continues the chain. A blank
            // line or a comment-only line does not end it — the modifiers in
            // this repository are separated by their own explanations.
            guard body.isEmpty || body.hasPrefix(".") else { break }
            text += "\n" + code
            depth += braces(in: code)
        }
        return text
    }

    private static func braces(in code: String) -> Int {
        code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
    }

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

    /// **And the recorded site is still there.** Without this the ratchet is
    /// green on an empty list — a scan that has quietly stopped matching, a
    /// `UISources` that lost the module directories, a regular expression that
    /// went stale, all read as "nothing left to fix". `<=` cannot tell the
    /// difference between clean and blind.
    ///
    /// So the day `DiskResultView` is fixed, this fails, and the commit that
    /// fixed it lowers `recorded` to 0 and empties `recordedFiles` — which is how
    /// a ratchet is lowered here, in the commit that earns it.
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

import AppKit
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A layout has to survive a longer string than English writes.**
///
/// The mockup audit inflates every letter run by 40 % and re-runs its geometry
/// checks (`v3/audit.js`, `pseudoLocalise`) — letters only, because a number
/// does not grow in translation and neither does a path: «775,6 ГБ» and
/// `~/Library` are the same length in every language, and inflating them would
/// produce findings that cannot happen.
///
/// **Swift cannot inflate the string, so the inflation moved to the
/// measurement.** A page's text arrives from `L()` out of the shipped
/// `.lproj` tables; nothing between the call site and the render can be asked to
/// lengthen it without a hook in `HelmUI`, and this is a test, so there is no
/// hook. Two things stand in its place, and together they are stronger than the
/// mockup's one:
///
/// 1. **Eight real languages.** `AppLanguage.override` draws every page in each
///    of the eight Helm ships, which is real data rather than simulated — and it
///    is the parameterization CLAUDE.md asks for, since a test reading
///    `AppLanguage.current` checks this machine's English eight times.
/// 2. **Forty per cent of headroom.** A control drawn narrower than 1.4 × the
///    width it asks for is a control that breaks when its label grows by 40 % —
///    the audit's inflation, applied to the arithmetic instead of to the text.
///
/// **What it can see, and what it cannot.** `intrinsicContentSize` is AppKit's,
/// so this reads the AppKit-backed controls in a page. Measured 2026-08-11, all
/// nine pages, with the configured fixture below: **23 controls in the whole
/// app** — 18 switches, 3 text fields (Layout), one search field and one
/// segmented control (Uninstaller). This comment used to name pop-ups as well,
/// and there is not one in any page's view tree: SwiftUI's `Picker(.menu)`,
/// `Button` and `Slider` are drawn by SwiftUI itself on macOS 26/27, so a walk
/// for `_NSCoreHostingView<AppKit…>` cannot find them however the page is seeded.
/// `testTheControlsFoundAreTheOnesRecorded` holds that inventory, so the day the
/// platform hands them back is a failure rather than a silent widening. So
/// `recordedAtFortyPercent` is a fact about one segmented control in eight
/// languages — and the widths this app imposes on the pickers it cannot see are
/// measured in `AnImposedPickerWidthFitsItsLabelsTests`, which hosts each one and
/// reads the same `intrinsicContentSize` this file does.
///
/// It does **not** see a `Text` truncating:
/// SwiftUI draws text already truncated, so the layer never overflows its
/// parent, and the string that would say how much was lost is not in the
/// rendered tree (the accessibility tree carries it, and is not materialized
/// offscreen — measured, zero labels on three pages). A ratchet that cannot see
/// most of the page is worth having only if it says so, so it says so.
///
/// **A ratchet, not a gate**, and there are two numbers because there are two
/// questions. What breaks *today*, in a language that ships, is the sharper one.
@MainActor
final class LongStringGeometryRatchetTests: XCTestCase {

    /// Measured 2026-08-11 against `main` = `8b8c547`, three consecutive runs in
    /// agreement. `atFullSize` was 1 and is 0: the Uninstaller's segmented control
    /// was drawn at 200 pt where Russian asks for 208, and the `.frame(width: 200)`
    /// that did it is gone.
    ///
    /// **Re-measured 2026-08-11 with the configured fixture, three consecutive runs:
    /// both numbers unchanged.** Which is a finding rather than a reassurance — the
    /// fixture puts two app-rule rows, their condition menus and the battery slider
    /// into every render, and none of them is a control this measurement can see
    /// (`testTheControlsFoundAreTheOnesRecorded` records that inventory). The pair
    /// below moves when a *segmented control*, a text field or a search field
    /// changes, and for nothing else.
    ///
    /// `atFortyPercent` is that control in all eight languages, and **a wider frame
    /// cannot lower it** — worth knowing before somebody tries. A segmented control
    /// sizes itself from its labels and does not stretch past that: Chinese drew
    /// 100 pt inside the 200 pt frame this page used to impose. So its drawn width
    /// is its intrinsic width whenever it has the room, and `drawn < intrinsic × 1.4`
    /// holds for every segmented control at any width. What lowers this number is a
    /// shorter label or a different control.
    private static let recordedAtFullSize = 0
    private static let recordedAtFortyPercent = 8

    /// The audit's number, and the reason it is 1.4 and not 2: a translation is
    /// longer, not unrecognisable.
    private static let inflation: CGFloat = 1.4

    /// One control as one language drew it.
    private struct Seen {
        let language: AppLanguage
        let module: String
        let control: ModulePageRender.Control

        var described: String {
            "\(language.rawValue)/\(module) \(control.shortName) "
            + "drawn \(control.frame.width) pt, wants \(control.intrinsic.width) pt"
        }
    }

    /// Seventy-two renders, taken once for the whole file.
    ///
    /// Not an optimization for its own sake: three tests asking the same
    /// question of three separate renders is three chances for the answers to
    /// disagree, and a page whose content arrives late (Disk's restored scan,
    /// `ModulePageRender.floors`) is
    /// exactly the shape that makes them. One reading, asserted three ways.
    private static let seen: [Seen] = {
        var out: [Seen] = []
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            // Seeded, and that is a correction rather than a refinement: against
            // an empty store the pages draw their empty states, so Keep Awake's
            // per-app rule rows, the condition pop-up in each of them and the
            // battery slider were in none of these 72 renders. The widest label a
            // configured page has was measured in no language at all.
            for page in ModulePageRender.pages(seededBy: ModulePageRender.configured) {
                page.assertItDrewSomething()
                out += page.controls.map { Seen(language: language, module: page.id, control: $0) }
            }
        }
        return out
    }()

    // MARK: - The two ratchets

    func testWhatDoesNotFitTodayDoesNotGrow() {
        let found = breakages(inflatedBy: 1)
        XCTAssertLessThanOrEqual(found.count, Self.recordedAtFullSize, """
            \(found.count) controls do not fit the text they are given, in a language Helm \
            ships; the recorded number is \(Self.recordedAtFullSize).
            This number is only ever lowered, by the commit that lowers it.
            \(found.map(\.described).joined(separator: "\n"))
            """)
    }

    func testWhatBreaksOnAFortyPerCentLongerStringDoesNotGrow() {
        let found = breakages(inflatedBy: Self.inflation)
        XCTAssertLessThanOrEqual(found.count, Self.recordedAtFortyPercent, """
            \(found.count) controls have less than \(Int((Self.inflation - 1) * 100))% headroom \
            for their own label, so a longer word breaks them; the recorded number is \
            \(Self.recordedAtFortyPercent).
            This number is only ever lowered, by the commit that lowers it.
            \(found.map(\.described).joined(separator: "\n"))
            """)
    }

    /// A control drawn to nothing at all is the other half of the audit's
    /// geometry pass (`collapsed`), and it is a different defect: a squeezed
    /// control looks tight, a collapsed one is not there.
    func testNoControlIsDrawnToNothing() {
        let gone = Self.seen
            .filter { $0.control.frame.width < 1 || $0.control.frame.height < 1 }
            .map(\.described)
        XCTAssertFalse(Self.seen.isEmpty, "no control was found in any page, in any language")
        XCTAssertEqual(gone, [], "a control collapsed: \n\(gone.joined(separator: "\n"))")
    }

    // MARK: - The measurement itself

    /// The language actually reaches the render. Without this, every count above
    /// is eight readings of English and the ratchet is a third of a test — the
    /// exact shape CLAUDE.md warns about, a language filtered out of its own
    /// guard.
    ///
    /// Asserted through a control's own intrinsic width, which is set by the
    /// text in it: the Uninstaller's segmented control is 161 pt in English and
    /// 208 in Russian, and a render that ignored the override would answer 161
    /// twice.
    func testTheLanguageChangesWhatIsDrawn() {
        var widths: [String: CGFloat] = [:]
        for language in [AppLanguage.en, .ru] {
            let previous = AppLanguage.override
            AppLanguage.override = language
            defer { AppLanguage.override = previous }
            let page = ModulePageRender.page(for: uninstaller, width: ModulePageRender.pageWidth)
            page.assertItDrewSomething()
            let segmented = page.controls.first { $0.name.contains("SegmentedControl") }
            widths[language.rawValue] = segmented?.intrinsic.width ?? 0
        }
        XCTAssertGreaterThan(widths["en"] ?? 0, 0, "no segmented control was found to compare")
        XCTAssertNotEqual(widths["en"], widths["ru"],
                          "English and Russian drew the same control width — "
                          + "the language override is not reaching the page")
    }

    /// **The fixture reaches the render.** Without this the seed is a parameter
    /// nobody can see the effect of, and the 72 renders go on being 72 empty
    /// states while the file above claims otherwise — the same shape as a language
    /// filtered out of its own guard, one argument along.
    ///
    /// Asserted as layers, which is where the difference is: two per-app rule rows
    /// with a condition menu and a remove button each, and the battery figure
    /// beside its slider, against the empty state's one button. Measured 296 → 322.
    func testTheConfiguredRowsAreDrawn() {
        let plain = ModulePageRender.page(for: keepAwake, width: ModulePageRender.pageWidth)
        let seeded = ModulePageRender.page(for: keepAwake, width: ModulePageRender.pageWidth,
                                          seededBy: ModulePageRender.configured)
        plain.assertItDrewSomething()
        seeded.assertItDrewSomething()

        XCTAssertGreaterThan(seeded.layers.count, plain.layers.count,
                             "the seeded page draws \(seeded.layers.count) layers against "
                             + "\(plain.layers.count) on an empty store, so the app rules the "
                             + "fixture writes are not being drawn at all and every render this "
                             + "file takes is still of an empty state")
    }

    /// **What this instrument can reach, recorded as an inventory rather than as a
    /// sentence.**
    ///
    /// The two numbers above are only as wide as the set of controls this walk
    /// finds, and that set is much narrower than it reads: measured over all nine
    /// pages, in every language, it is 23 controls — 18 switches (which the text
    /// rule excludes, because a switch is 36 pt in every language), 3 text fields,
    /// one search field and one segmented control. The configured Keep Awake page
    /// alone draws four `Picker(.menu)` and a row of buttons, and its whole view
    /// tree holds ten switches and nothing else: SwiftUI draws menus, buttons and
    /// sliders itself on macOS 26/27, so there is no AppKit view to ask.
    ///
    /// So this is the coverage, written down. A class **appearing** here is the day
    /// the platform hands those controls back to AppKit, and both recorded numbers
    /// have to be re-measured that day rather than inherited. A class
    /// **disappearing** is a page that has stopped drawing what it drew.
    ///
    /// The gap itself is not left as a note: what a width imposed on a picker does
    /// to its labels in eight languages is measured in
    /// `AnImposedPickerWidthFitsItsLabelsTests`, by hosting the control this walk
    /// cannot find and reading the same `intrinsicContentSize` — calibrated against
    /// this file's own reading of the one control both can see.
    func testTheControlsFoundAreTheOnesRecorded() {
        var tally: [String: Int] = [:]
        for seen in Self.seen where seen.language == .de {
            tally[seen.control.shortName, default: 0] += 1
        }
        XCTAssertFalse(tally.isEmpty, "no control was found in any page, in any language")

        XCTAssertEqual(tally, ["AppKitSwitch": 18, "AppKitTextField": 3,
                               "AppKitSearchField": 1, "AppKitSegmentedControl": 1], """
            the controls this measurement can see are not the ones it was measured with: \
            \(tally.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")).
            A pop-up, a button or a slider appearing here means the platform now backs them with \
            AppKit views, and the two recorded numbers above cover controls they never covered — \
            re-measure them rather than inherit them. A count falling means a page has stopped \
            drawing what it drew.
            """)
    }

    /// And the eight tables really are the eight. A language whose table failed
    /// to load falls every string back to English silently, which would make
    /// this test eight English runs without a word.
    func testTheEightLanguagesAreEightDifferentTables() {
        let sample = L("Uninstall", language: .en)
        let translated = AppLanguage.allCases.map { L("Uninstall", language: $0) }
        XCTAssertEqual(translated.count, 8)
        XCTAssertGreaterThan(Set(translated).count, 5,
                             "\(Set(translated).count) distinct spellings of «\(sample)» — "
                             + "some .lproj table is not loading")
    }

    /// The rule recognises the shape it was written for. A control with room to
    /// spare passes both readings; one drawn at exactly what it asks for passes
    /// the first and fails the second, which is the whole point of the 40 %.
    func testTheRuleRecognisesAControlWithNoHeadroom() {
        let tight = ModulePageRender.Control(
            module: "fixture", name: "_NSCoreHostingView<AppKitSegmentedControl>",
            frame: CGRect(x: 0, y: 0, width: 161, height: 22),
            intrinsic: CGSize(width: 161, height: 22))
        let roomy = ModulePageRender.Control(
            module: "fixture", name: "_NSCoreHostingView<AppKitSegmentedControl>",
            frame: CGRect(x: 0, y: 0, width: 400, height: 22),
            intrinsic: CGSize(width: 161, height: 22))
        let switchControl = ModulePageRender.Control(
            module: "fixture", name: "_NSCoreHostingView<AppKitSwitch>",
            frame: CGRect(x: 0, y: 0, width: 36, height: 16),
            intrinsic: CGSize(width: 36, height: 16))

        XCTAssertFalse(isSqueezed(tight, by: 1), "161 pt in 161 pt fits, as shipped")
        XCTAssertTrue(isSqueezed(tight, by: Self.inflation), "161 pt has no room for a longer word")
        XCTAssertFalse(isSqueezed(roomy, by: Self.inflation), "400 pt has room to spare")
        XCTAssertFalse(isSqueezed(switchControl, by: Self.inflation),
                       "a switch carries no text, so its width says nothing about a translation")
    }

    // MARK: - Plumbing

    private var uninstaller: any ModuleDescriptor {
        ModuleRegistry.all.first { $0.idRaw == "uninstaller" }!
    }

    private var keepAwake: any ModuleDescriptor {
        ModuleRegistry.all.first { $0.idRaw == "keep-awake" }!
    }

    private func isSqueezed(_ control: ModulePageRender.Control, by factor: CGFloat) -> Bool {
        guard control.isTextBearing, control.intrinsic.width > 0 else { return false }
        return control.frame.width + 0.5 < control.intrinsic.width * factor
    }

    private func breakages(inflatedBy factor: CGFloat) -> [Seen] {
        Self.seen.filter { isSqueezed($0.control, by: factor) }
    }
}

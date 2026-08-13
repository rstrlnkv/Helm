import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// What a partly-failed removal costs the list it is reporting on.
///
/// `HelmRemovalOutcome` sat in the same `HStack` as three buttons and two lines of
/// text, so it took the width those left over and paid for it in height: measured
/// at the minimum window, 646 × 540, the bottom bar went 49 → 171 pt and the list
/// fell **416 → 294** — the list losing 122 pt to a report about two files, with
/// the file names truncated to «co….plist» and both buttons beside it clipped to
/// «Auswahl aufh…» and «In den Papierk…».
///
/// The report is a full-width row of its own now, above the bar. The numbers below
/// are what that measured; they are what makes this a guard rather than a
/// description.
///
/// Parameterized by an explicit language, never by `AppLanguage.current`: this
/// defect is a translation running out of width, and the suite runs in English.
@MainActor
final class ARemovalReportDoesNotEatTheListTests: XCTestCase {

    // MARK: - The wire, answering a scan and a removal with refusals in it

    private final class Wire: EngineTransport, @unchecked Sendable {
        private let lock = NSLock()
        private let items: [StaleItem]
        private let removal: LeftoversRemoval
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

        init(items: [StaleItem], removal: LeftoversRemoval) {
            self.items = items
            self.removal = removal
        }

        private var currentItems: [StaleItem] { lock.lock(); defer { lock.unlock() }; return items }
        private var currentRemoval: LeftoversRemoval {
            lock.lock(); defer { lock.unlock() }; return removal
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch LeftoversCommand(rawValue: command.name) {
            case .scan: return (try? JSONEncoder().encode(currentItems)) ?? Data()
            case .trash: return (try? JSONEncoder().encode(currentRemoval)) ?? Data()
            case .setDisabled, .none: return Data()
            }
        }
    }

    private static func agent(_ name: String, bytes: Int,
                              missingTarget: String? = nil) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: bytes,
                  missingTarget: missingTarget)
    }

    private static var items: [StaleItem] {
        [agent("com.vendor.updater", bytes: 4_096),
         agent("com.vendor.broken", bytes: 12_288,
               missingTarget: "/Applications/Gone.app/Contents/MacOS/helper"),
         agent("com.vendor.quiet", bytes: 2_048),
         StaleItem(path: "\(NSHomeDirectory())/Library/Preferences/com.vendor.app.plist",
                   identifier: "com.vendor.app", kind: .preference, sizeBytes: 24_576)]
    }

    /// One moved, two refused — the shape the survey measured, and the only one
    /// that draws the failure list at all.
    private static var partlyRefused: LeftoversRemoval {
        LeftoversRemoval(
            removed: [items[0].path],
            refused: [HelmTrash.Refusal(path: items[1].path, reason: .needsFullDiskAccess),
                      HelmTrash.Refusal(path: items[3].path, reason: .noPermission)],
            freedBytes: 4_096)
    }

    /// Nothing moved and nothing refused: the round the Uninstaller's orphans view
    /// produces when every path was already gone. The banner is set all the same,
    /// because the model writes it before it knows.
    private static var silent: LeftoversRemoval {
        LeftoversRemoval(removed: [], refused: [], freedBytes: 0)
    }

    // MARK: - Mounting one reading

    /// The height of the drawn list, in points, after a scan and — when one is
    /// given — a removal.
    ///
    /// `ListCoreScrollView` is what SwiftUI backs a `List` with on macOS 26/27:
    /// its frame is the room the rows have, which is the quantity this whole file
    /// is about.
    private func listHeight(_ removal: LeftoversRemoval?, language: AppLanguage,
                            width: CGFloat, height: CGFloat,
                            appearance: NSAppearance.Name) async throws -> CGFloat {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = language

        let vm = ModuleViewModel(transport: Wire(items: Self.items,
                                                 removal: removal ?? Self.silent))
        let lvm = LeftoversViewModel.shared(vm: vm)
        let mount = MountedRender(LeftoversSettingsPage(vm: vm)
            // Named, never inherited: the banner this page draws when the grant is
            // withheld is 61 pt of the measurement (`ModulePageRender.granted`).
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted)),
                                  width: width, height: height, appearance: appearance)
        defer { mount.drop() }
        await lvm.scan()
        mount.settle(20)
        if removal != nil {
            lvm.selected = Set(Self.items.map(\.path))
            await lvm.removeSelected()
            XCTAssertNotNil(lvm.banner, "precondition: the removal reported nothing at all")
        }
        mount.settle(30)
        return Self.list(in: mount.host)?.height ?? 0
    }

    private static func list(in host: NSView) -> CGRect? {
        var found: CGRect?
        func walk(_ view: NSView) {
            if String(describing: type(of: view)).contains("ListCoreScrollView") {
                let frame = view.convert(view.bounds, to: host)
                if frame.height > (found?.height ?? 0) { found = frame }
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
    }

    // MARK: - The guards

    /// **The measurement this file exists for.** What the report costs the list it
    /// is reporting on, at the smallest window the app allows.
    ///
    /// Russian, because it is the worst of the three measured here: 122 pt with the
    /// report inside the button row (416 → 294), and **80.5 pt** with the report in
    /// a row of its own (416 → 335.5) — three consecutive runs in agreement, both
    /// appearances, 2026-08-13. The ceiling is 100: 20 pt over what the row measures
    /// and 22 pt under the reading this reflow replaced.
    ///
    /// A cost rather than a height, so the number says what it is about and holds
    /// whatever height the window is given.
    func testAReportCostsTheListOneRowRatherThanAThirdOfIt() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let untouched = try await listHeight(nil, language: .ru, width: 646, height: 540,
                                                 appearance: appearance)
            let withReport = try await listHeight(Self.partlyRefused, language: .ru,
                                                  width: 646, height: 540,
                                                  appearance: appearance)
            XCTAssertGreaterThan(untouched, 0, "precondition: the page drew a list at all")
            XCTAssertLessThanOrEqual(untouched - withReport, 100, """
                a report about two refused files costs the list \(Int(untouched - withReport)) pt \
                of its \(Int(untouched)) at the minimum window, where it measured 80.5 when this \
                landed. A report that pays for its width in height is back in the button row.
                """)
        }
    }

    /// And the room it takes is the room the report needs, rather than the remainder
    /// three buttons left it: a report squeezed into a column wraps differently in
    /// every language, so the list under it was a different height in each.
    ///
    /// Measured: 294 pt in Russian against 322 in English and German — a spread of
    /// 28 — and 331.5…335.5 pt in its own row, a spread of 4.
    func testTheReportCostsTheSameHeightWhicheverLanguageItIsIn() async throws {
        var heights: [String: CGFloat] = [:]
        for language in [AppLanguage.en, .ru, .de] {
            heights[language.rawValue] = try await listHeight(Self.partlyRefused,
                                                              language: language,
                                                              width: 646, height: 540,
                                                              appearance: .aqua)
        }
        let spread = (heights.values.max() ?? 0) - (heights.values.min() ?? 0)

        XCTAssertGreaterThan(heights.values.min() ?? 0, 0,
                             "precondition: every reading drew a list")
        XCTAssertLessThanOrEqual(spread, 20, """
            the list is \(Int(spread)) pt shorter in one language than in another with the same \
            report on it: \(heights.map { "\($0.key) \(Int($0.value))" }.sorted().joined(separator: ", ")).
            A report that wraps differently per language is a report in a column of \
            leftover width.
            """)
    }

    /// A round where nothing moved and nothing was refused says nothing — and a
    /// row that says nothing must not take a row's worth of height.
    ///
    /// `HelmRemovalOutcome.verdict` has answered `.silent` for that case since it
    /// was written, and the page deliberately does not ask a second time: measured,
    /// the frame and the padding around a view whose body is `EmptyView` cost 0 pt,
    /// so a question here would have been a guard against nothing. This is the
    /// measurement that says so — and it can fail: a `Divider()` put in that row
    /// beside the outcome took 1 pt off the list on a silent round, which is this
    /// assertion going red.
    func testAnOutcomeWithNothingToSayTakesNoRoom() async throws {
        let quiet = try await listHeight(Self.silent, language: .ru,
                                         width: 646, height: 540, appearance: .aqua)
        let untouched = try await listHeight(nil, language: .ru,
                                             width: 646, height: 540, appearance: .aqua)

        XCTAssertGreaterThan(untouched, 0, "precondition: the page drew a list at all")
        XCTAssertEqual(quiet, untouched,
                       "a removal that moved nothing and refused nothing took \(untouched - quiet) "
                       + "pt off the list — an empty row with padding on it")
    }
}

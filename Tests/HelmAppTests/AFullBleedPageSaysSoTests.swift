import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// A page that lays out its own margins has to tell its header so.
///
/// `HelmPageHeader` sits on the same column as the content below it, and which
/// column that is depends on the page: a grouped `Form` is capped at the
/// settings column and centred, so the header is too, while a full-bleed page
/// draws at a flat `HelmLayout.formInset` across the whole pane. The header
/// learns which from `descriptor.pageBleeds`, and the comment at that `frame`
/// records what happens when a page gets it wrong — the title walks away from
/// its own controls as the window grows.
///
/// **Hosts & Keys had it wrong and nothing said so.** Measured at an 845 pt
/// pane its header plate sat at x 70…98 with the first control at x 20; at
/// 1400 the plate was at x 348 and the control still at 20, a 328 pt gap. Six
/// modules declared `pageBleeds` and the seventh full-bleed page did not,
/// which is the shape a hand-written list always fails in: nothing ties the
/// declaration to the page it is about.
///
/// **So this ties it.** A page inside a grouped `Form` never spells
/// `HelmLayout.formInset` — the `Form` owns its margins — and a page that
/// positions its own content across the pane cannot avoid spelling it. That is
/// the same fact `pageBleeds` states, read off the tree instead of off a
/// declaration somebody remembered to write, and the two are asserted equal in
/// both directions: a module that stops owning its margins and keeps the
/// declaration fails here too.
@MainActor
final class AFullBleedPageSaysSoTests: XCTestCase {

    func testAPageThatOwnsItsMarginsIsAPageThatDeclaresItBleeds() throws {
        let owning = try Self.modulesOwningTheirMargins()
        let declaring = Self.modulesDeclaringPageBleeds()
        XCTAssertEqual(owning, declaring, """
            \(owning.subtracting(declaring).sorted()) lay out their own content across the \
            pane and do not declare `pageBleeds`, so their page header centres itself on a \
            column the page is not on — the title walks away from its own controls as the \
            window grows.
            \(declaring.subtracting(owning).sorted()) declare `pageBleeds` and draw no \
            margins of their own, which is a header pushed to the leading edge above \
            content that is centred.
            """)
    }

    /// **Both sets can be empty and the equality still holds**, which would be
    /// a check reading nothing and reporting success. This says each side still
    /// has members, and that neither is every module — a scan that answered
    /// «all ten» or «none» would satisfy the rule above by collapsing.
    func testBothKindsOfPageStillExist() throws {
        let owning = try Self.modulesOwningTheirMargins()
        let all = Set(ModuleRegistry.all.map { Self.folder(of: $0) })
        XCTAssertFalse(owning.isEmpty, "no module lays out its own margins; the scan is idle")
        XCTAssertNotEqual(owning, all, """
            every module reads as full-bleed, so the scan cannot tell the two kinds \
            apart any more
            """)
        XCTAssertFalse(Self.modulesDeclaringPageBleeds().isEmpty,
                       "no descriptor declares `pageBleeds`; the registry side is idle")
    }

    // MARK: - The two sides

    /// Modules whose UI positions content across the pane itself, by folder.
    ///
    /// **«Every file of every module's UI, with the module it belongs to» is
    /// owed to `UISources`.** It is spelled here and again in
    /// `AModulePlateIsTheModulesOwnColourTests`, which is the second copy —
    /// `UISources.files()` already walks these directories and drops which
    /// module each file came from, which is the one thing both of these need.
    /// It is not added there in this change because another pass is in
    /// `Tests/Support`; that is a reason for the delay and not for the
    /// duplication.
    private static func modulesOwningTheirMargins() throws -> Set<String> {
        var out: Set<String> = []
        for module in try UISources.moduleNames() {
            for file in try RepoSource.swiftFiles(under: "Sources/Modules/\(module)/UI") {
                let owns = try RepoSource.lines(of: file).map(RepoSource.code)
                    .contains { $0.contains("HelmLayout.formInset") }
                if owns { out.insert(module.lowercased()) }
            }
        }
        return out
    }

    private static func modulesDeclaringPageBleeds() -> Set<String> {
        Set(ModuleRegistry.all.filter(\.pageBleeds).map { folder(of: $0) })
    }

    /// The folder a descriptor's module lives in, from its id. «keep-awake» is
    /// one folder called KeepAwake: the id carries a hyphen a folder name does
    /// not, and that is the whole difference.
    private static func folder(of descriptor: any ModuleDescriptor) -> String {
        type(of: descriptor).id.rawValue.replacingOccurrences(of: "-", with: "")
    }
}

import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// A plate a module draws is drawn in **that module's** colour, and in nothing
/// else.
///
/// The shell already does this — every plate in the sidebar, the panel and the
/// page header reads `descriptor.moduleTint.colour` — and `ModuleTint`'s own
/// documentation says why the palette it replaced cannot be used for this. The
/// module pages had not been held to it: nine plates across six modules drew
/// `ModuleCategory.<x>.tint`, which is a colour four modules share, and one drew
/// a raw `.pink`. So the Uninstaller's header plate was red and its empty-state
/// plate cyan on the same screen, and a person looking at two plates 300 pt
/// apart had no way to know they were the same module.
///
/// **It is not only a question of identity, it is a question of legibility.**
/// `HelmIconPlate` draws its symbol in white, so the colour under it answers to
/// the 3:1 floor for a mark that carries meaning. `ModuleTint`'s values are
/// solved for that floor; the category palette is macOS's own, tuned for a dark
/// background, and `testTheCategoryPaletteIsWhyThisRuleExists` measures what it
/// gives — 2,16:1 in light and 1,76:1 in dark for the colour four of the modules
/// were using.
///
/// **Two spellings, so this reads the value and not a string.** Most of the nine
/// said `ModuleCategory.files.tint` and one said `HomebrewDescriptor.category.tint`,
/// which is the same colour reached the other way round. A scan looking for
/// either phrase would have found some of them; this one asks what the argument
/// *is*, so a third spelling of the same mistake is caught the day it is written.
@MainActor
final class AModulePlateIsTheModulesOwnColourTests: XCTestCase {

    /// The three components that draw a tinted plate. A `HelmBadge` is not one
    /// of them: a pill's colour is its *meaning* — green for trusted, orange for
    /// a warning — and painting those in the module's colour would delete the
    /// only thing they say.
    private static let plates = ["HelmIconPlate", "HelmEmptyState", "HelmWidgetHeader"]

    /// A walk that read nothing is not a walk that found nothing, and the two
    /// look identical from the assertion. `UISources.Failure` says this one
    /// module over and is internal to that target, so it is said again here
    /// rather than reached for.
    private struct NotRead: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private struct Site {
        let module: String
        let file: String
        let line: Int
        let component: String
        /// What was written after `tint:`, or nil when the call gave none and
        /// took `HelmEmptyState`'s grey default.
        let tint: String?

        var where_: String { "\(file):\(line)" }
    }

    // MARK: - The rule

    func testEveryModulePlateDrawsTheModulesOwnColour() throws {
        var offenders: [String] = []
        for site in try Self.sites() {
            let wanted = "\(site.module)Descriptor.tint.colour"
            guard site.tint != wanted else { continue }
            offenders.append("\(site.where_)  \(site.component) draws "
                             + "\(site.tint ?? "no tint at all") — it must draw \(wanted)")
        }
        XCTAssertEqual(offenders, [], """
            These plates are not the colour of the module that drew them. A category \
            tint is shared by four modules and a literal belongs to nobody; both also \
            skip the 3:1 floor `ModuleTint` is solved for, which the measurement in \
            this file shows is not academic.
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// **The scan above is satisfied by finding nothing**, which is what a
    /// walk that has stopped reading the tree also looks like. This says how
    /// much it still sees, in modules as well as in sites: a regex that matched
    /// only the two files somebody happened to edit would pass the rule and fail
    /// here.
    func testTheScanStillSeesPlatesToJudge() throws {
        let sites = try Self.sites()
        XCTAssertGreaterThan(sites.count, 12,
                             "the scan finds \(sites.count) tinted plates in the whole of "
                             + "Sources/Modules; it has stopped reading the tree")
        XCTAssertGreaterThan(Set(sites.map(\.module)).count, 5, """
            the plates it finds are in \(Set(sites.map(\.module)).sorted()) — too few \
            modules for a scan that walks all of them
            """)
    }

    // MARK: - Why the rule exists, measured

    /// The category palette against the white glyph drawn on it.
    ///
    /// This is the hazard the rule guards, asserted rather than described, for
    /// the reason `ReleaseBuildsTheProductTests` opens by asserting its own: a
    /// rule whose reason has quietly gone away is a rule nobody can argue with.
    /// Measured 2026-08-20 — `.cyan` 2,16:1 light and 1,76:1 dark, `.orange`
    /// 2,31 / 2,23, `.green` 2,22 / 2,02 — against the 3:1 floor for a mark.
    ///
    /// If this ever goes green it does not mean the plates may take a category
    /// colour again; it means macOS moved its palette, and somebody has to
    /// decide whether four modules sharing one colour is still worth forbidding
    /// for the *other* reason, which is that it names none of them.
    func testTheCategoryPaletteIsWhyThisRuleExists() {
        var failing: [String] = []
        for category in ModuleCategory.allCases {
            for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
                let ratio = Contrast.ratio(.white, Contrast.resolved(category.tint, appearance))
                guard ratio < Contrast.markFloor else { continue }
                failing.append("\(category.rawValue) in \(appearance.rawValue) "
                               + String(format: "%.2f:1", ratio))
            }
        }
        XCTAssertFalse(failing.isEmpty, """
            every colour in `ModuleCategory.tint` now carries a white glyph at \
            \(Contrast.markFloor):1. The measurement this rule was written against has \
            changed and the rule needs re-arguing, not relaxing.
            """)
    }

    // MARK: - Reading the tree

    /// Every tinted plate under `Sources/Modules/<M>/UI`, with the module that
    /// drew it.
    ///
    /// The module list is `UISources.moduleNames()`, read out of `Package.swift`
    /// — a hand-written list here would be a comment, and a module added to the
    /// manifest arrives in this scan without anybody remembering it.
    private static func sites() throws -> [Site] {
        var out: [Site] = []
        for module in try UISources.moduleNames() {
            let directory = "Sources/Modules/\(module)/UI"
            let files = try RepoSource.swiftFiles(under: directory)
            guard !files.isEmpty else {
                throw NotRead("\(directory) holds no Swift — the scan is not reading \(module)")
            }
            for file in files {
                let lines = try RepoSource.lines(of: file).map(RepoSource.code)
                for (index, line) in lines.enumerated() {
                    guard let component = plates.first(where: { line.contains("\($0)(") })
                    else { continue }
                    // A plate with no symbol draws no plate: `HelmEmptyState`'s
                    // sentence-only form is a statement, and its tint argument
                    // reaches nothing.
                    let call = arguments(from: lines, at: index, of: component)
                    guard call.contains("symbol:") else { continue }
                    out.append(Site(module: module, file: file, line: index + 1,
                                    component: component, tint: tint(in: call)))
                }
            }
        }
        return out
    }

    /// The argument list of the call opening on `index`, gathered until its
    /// parentheses balance.
    ///
    /// SwiftUI puts a call's arguments on as many lines as it likes — one of the
    /// nine sites wrote `tint:` on the line *after* the component's name — so a
    /// scan reading a single line would report four of the nine and bless five.
    private static func arguments(from lines: [String], at index: Int,
                                  of component: String) -> String {
        guard let start = lines[index].range(of: "\(component)(") else { return "" }
        var text = ""
        var depth = 1
        for offset in index..<min(index + 20, lines.count) {
            let line = lines[offset]
            // Counted by position, never by comparing the line with itself: two
            // consecutive identical lines are ordinary in a SwiftUI body, and a
            // walk that asked «is this the first one» by equality would restart
            // its depth on the second.
            for character in line[(offset == index ? start.upperBound : line.startIndex)...] {
                if character == "(" { depth += 1 }
                if character == ")" {
                    depth -= 1
                    if depth == 0 { return text }
                }
                text.append(character)
            }
            text.append("\n")
        }
        return text
    }

    /// What the call passes for `tint:`, or nil when it passes none.
    private static func tint(in call: String) -> String? {
        guard let label = call.range(of: "tint:") else { return nil }
        let rest = call[label.upperBound...]
        let value = rest.prefix { $0 != "," && $0 != "\n" }
        return value.trimmingCharacters(in: .whitespaces)
    }
}

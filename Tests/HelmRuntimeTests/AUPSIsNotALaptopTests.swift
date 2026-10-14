import HelmTestSupport
import IOKit.ps
import XCTest
@testable import HelmRuntime

/// A power source is not a battery, and a battery is not a lid.
///
/// `MacHardware` answered «has a battery» with «the IOKit power-source list is
/// not empty», and then built the lid and the built-in panel on that answer.
/// The list holds the internal battery of a laptop and, if IOKit lists it, a UPS
/// plugged into a desktop; the adapter a Mac draws from on mains is not in it. A
/// Mac mini on a UPS would then read as a laptop, with a lid and a built-in
/// panel. `PowerSource.current()` read `sources.first`, so on a laptop with a
/// UPS ahead of the battery it would report the UPS's charge as the Mac's own.
///
/// What each question is, as the rows below hold it:
///
/// - **The battery guard** (`hasBattery`) is true for any source, a UPS and a
///   source with no type included, and false for an empty list.
/// - **The lid, and the battery half of the built-in panel** are true only when
///   some source's type equals `kIOPSInternalBatteryType`, compared whole. A UPS
///   alone, an untyped source and a lookalike spelling are no lid; a UPS alone
///   and an untyped source are no panel when the window server finds none. The
///   window server is asked when no internal battery settles it (that it is left
///   unasked when one does, no row records), and its answer decides the rest (an
///   iMac on a UPS keeps its panel).
/// - **The source `current()` reads** is the first internal battery wherever it
///   sits in the list, else the first source, and nil for an empty list. That
///   the chosen source with no capacity gives nil and not another source's
///   figure is in the part of `current()` that talks to IOKit, and no row here
///   holds it.
///
/// **Held on a fixture, not on a machine.** That IOKit lists a UPS beside the
/// internal battery, or at all, was not measured: no UPS was at hand. The rows
/// above the last group feed the *types* a list would carry to the pure
/// functions; the last group reads the two source files with their comment
/// lines removed: the lid's and the panel's declarations are checked to be
/// spelled through those functions, `PowerSource.swift` as a whole to name
/// `kIOPSTypeKey` and no `sources.first`, and the body of `current()` to name
/// `readableSourceIndex` and no `sources.first`.
final class AUPSIsNotALaptopTests: XCTestCase {

    private let battery: String? = kIOPSInternalBatteryType
    private let ups: String? = kIOPSUPSType

    // MARK: - A UPS alone: a desktop

    func testAUPSAloneIsNoInternalBattery() {
        XCTAssertFalse(MacHardware.hasInternalBattery(sourceTypes: [ups]),
                       "a Mac mini on a UPS has no lid to close; the lid row and its sudoers "
                       + "grant hang on this answer")
    }

    /// The guard stays: a UPS is a source, and its charge is what the guard reads.
    func testAUPSAloneIsStillASourceTheBatteryGuardReads() {
        XCTAssertTrue(MacHardware.hasBattery(sourceTypes: [ups]))
    }

    /// No lid, so no panel from the battery half; the window server decides, and
    /// on a mini it says there is none.
    func testAUPSAloneGivesNoPanelWhenTheWindowServerFindsNone() {
        var asked = false
        let answer = MacHardware.hasBuiltInDisplay(sourceTypes: [ups],
                                                   windowServerHasBuiltIn: { asked = true; return false }())
        XCTAssertFalse(answer, "the display rule on a desktop on a UPS means «never sleep»")
        XCTAssertTrue(asked, "without an internal battery the window server is the only witness left")
    }

    /// An iMac on a UPS: the panel is real and the window server is the one that
    /// knows it. The battery half must not swallow that half.
    func testAnIMacOnAUPSStillHasItsPanel() {
        XCTAssertTrue(MacHardware.hasBuiltInDisplay(sourceTypes: [ups], windowServerHasBuiltIn: true))
    }

    // MARK: - The internal battery: a laptop

    func testTheInternalBatteryIsALidAndAGuard() {
        XCTAssertTrue(MacHardware.hasInternalBattery(sourceTypes: [battery]))
        XCTAssertTrue(MacHardware.hasBattery(sourceTypes: [battery]))
    }

    /// A laptop's panel does not depend on the window server: with the lid shut
    /// the built-in display is offline, which is why the battery is asked at all.
    func testALaptopHasAPanelWhateverTheWindowServerSays() {
        XCTAssertTrue(MacHardware.hasBuiltInDisplay(sourceTypes: [battery], windowServerHasBuiltIn: false))
    }

    func testTheBatteryIsFoundWhereverTheUPSSitsInTheList() {
        XCTAssertTrue(MacHardware.hasInternalBattery(sourceTypes: [ups, battery]))
        XCTAssertTrue(MacHardware.hasInternalBattery(sourceTypes: [battery, ups]))
        XCTAssertTrue(MacHardware.hasBuiltInDisplay(sourceTypes: [ups, battery], windowServerHasBuiltIn: false))
    }

    // MARK: - Nothing, or nothing that names itself

    func testNoSourceIsNoBatteryNoLidNoGuard() {
        XCTAssertFalse(MacHardware.hasBattery(sourceTypes: []))
        XCTAssertFalse(MacHardware.hasInternalBattery(sourceTypes: []))
    }

    func testNoSourceLeavesThePanelToTheWindowServer() {
        XCTAssertFalse(MacHardware.hasBuiltInDisplay(sourceTypes: [], windowServerHasBuiltIn: false))
        XCTAssertTrue(MacHardware.hasBuiltInDisplay(sourceTypes: [], windowServerHasBuiltIn: true))
    }

    /// A description with no type key is a source of unknown kind: it is
    /// something to read, and nobody has said it is a battery.
    func testASourceWithNoTypeIsNotTheInternalBattery() {
        XCTAssertFalse(MacHardware.hasInternalBattery(sourceTypes: [nil]))
        XCTAssertTrue(MacHardware.hasBattery(sourceTypes: [nil]),
                      "an unnamed source is still a source; the guard reads it")
        XCTAssertFalse(MacHardware.hasBuiltInDisplay(sourceTypes: [nil], windowServerHasBuiltIn: false))
    }

    /// The type is compared whole and as spelled, not by a prefix or a lowercase.
    func testATypeThatOnlyLooksLikeTheBatteryIsNot() {
        for spelling in ["internalbattery", "InternalBattery ", "Internal", "InternalBattery2", "", "UPS"] {
            XCTAssertFalse(MacHardware.hasInternalBattery(sourceTypes: [spelling]),
                           "«\(spelling)» is not \(kIOPSInternalBatteryType)")
        }
        XCTAssertFalse(MacHardware.hasInternalBattery(sourceTypes: [nil, ups, "Something macOS has not shipped yet"]))
    }

    // MARK: - Which source the reading is taken from

    func testNothingToReadWhenThereIsNoSource() {
        XCTAssertNil(PowerSource.readableSourceIndex(types: []))
    }

    /// A desktop on a UPS keeps its guard: the UPS is read when it is all there is.
    func testAUPSAloneIsReadWhenItIsAllThereIs() {
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [ups]), 0)
    }

    func testTheInternalBatteryAloneIsRead() {
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [battery]), 0)
    }

    /// The defect `current()` had: `sources.first` was the UPS here, and its
    /// charge would have been reported as the Mac's.
    func testTheBatteryIsReadWhenAUPSComesFirst() {
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [ups, battery]), 1)
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [nil, battery]), 1)
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [ups, ups, battery]), 2)
    }

    func testTheBatteryIsReadWhenItComesFirst() {
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [battery, ups]), 0)
    }

    /// Two internal batteries (nothing ships so, but the list is IOKit's, not
    /// ours): the first.
    func testTheFirstInternalBatteryWins() {
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [ups, battery, battery]), 1)
    }

    /// No internal battery among several: the first source, as today.
    func testWithoutABatteryTheFirstSourceIsRead() {
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [ups, nil]), 0)
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [nil, ups]), 0)
        XCTAssertEqual(PowerSource.readableSourceIndex(types: [nil]), 0)
    }

    // MARK: - The real readers go through them

    /// The pure functions above are what the readers ask of the real list only
    /// if the readers are written that way. This reads the two files, comments
    /// removed, because the real list is IOKit's and a test cannot put a UPS on
    /// it.
    func testTheLidAndThePanelAreNotDerivedFromTheBatteryGuard() throws {
        let code = try codeOf("Sources/HelmRuntime/MacHardware.swift")
        let lid = try declaration("public static var hasLid", in: code)
        XCTAssertFalse(lid.contains("hasBattery"),
                       "the lid is still derived from «any source»: \(lid)")
        XCTAssertTrue(lid.contains("hasInternalBattery"), "the lid asks no one: \(lid)")

        let panel = try declaration("public static var hasBuiltInDisplay", in: code)
        XCTAssertFalse(panel.contains("hasBattery"),
                       "the panel's battery half is still «any source»: \(panel)")
        XCTAssertTrue(panel.contains("hasInternalBattery") || panel.contains("hasBuiltInDisplay(sourceTypes"),
                      "the panel asks no one: \(panel)")
    }

    func testTheReadingNoLongerTakesWhateverIsFirst() throws {
        let code = try codeOf("Sources/HelmRuntime/PowerSource.swift")
        XCTAssertFalse(code.contains("sources.first"),
                       "PowerSource.swift still reads the first source, whatever it is")
        XCTAssertTrue(code.contains("kIOPSTypeKey"), "no reader looks at a source's type")

        let current = try body("public static func current()", in: code)
        XCTAssertTrue(current.contains("readableSourceIndex"),
                      "current() does not choose its source: \(current)")
        XCTAssertFalse(current.contains("sources.first"), "current() takes the first source: \(current)")
    }

    // MARK: - Reading a file without its comments

    private func codeOf(_ path: String) throws -> String {
        let text = try RepoSource.text(of: path)
        XCTAssertGreaterThan(text.count, 1000, "\(path) was not read at all")
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// From the head to the first closing brace four spaces in, where a member
    /// of `PowerSource` closes: the body of a function declared directly in it.
    private func body(_ head: String, in code: String) throws -> String {
        let start = try XCTUnwrap(code.range(of: head), "«\(head)» is not in PowerSource.swift")
        let rest = code[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: "\n    }"), "«\(head)» has no end").upperBound
        return String(rest[..<end])
    }

    /// From the declaration to the next `public static` or the end of the file.
    private func declaration(_ head: String, in code: String) throws -> String {
        let start = try XCTUnwrap(code.range(of: head), "«\(head)» is not in MacHardware.swift")
        let rest = code[start.lowerBound...].dropFirst(head.count)
        let end = rest.range(of: "public static")?.lowerBound ?? rest.endIndex
        return String(code[start.lowerBound..<end])
    }
}

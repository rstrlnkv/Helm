import Foundation
import HelmTestSupport
import XCTest

/// **Helm reads macOS's preference domains and never writes them.**
/// `com.apple.screencapture` holds the save folder and `com.apple.symbolichotkeys`
/// holds which of the system's own shortcuts are ticked; changing either is the
/// person's act in System Settings, and a write here would silently change what
/// every other program on the Mac does. The module only has a read port for
/// them, but a port is a promise about one class: this is the promise about the
/// module, read off its own source with comments and string insides blanked.
final class TheSystemPreferencesAreOnlyReadTests: XCTestCase {

    private static let writers = [
        "CFPreferencesSetValue", "CFPreferencesSetAppValue", "CFPreferencesSetMultiple",
        "setPersistentDomain", "removePersistentDomain", "UserDefaults(suiteName",
        "addSuite", "removeSuite",
    ]

    func testNothingInTheModuleWritesAPreferenceDomain() throws {
        let reads = try SwiftSource.code(under: "Sources/Modules/Screenshots")
        XCTAssertGreaterThan(reads.count, 10, "the scan found \(reads.count) files — it is not reading the module")
        var offenders: [String] = []
        for read in reads {
            for writer in Self.writers where read.text.contains(writer) {
                offenders.append("\(read.path): \(writer)")
            }
        }
        XCTAssertEqual(offenders, [], "the module writes a preference domain")
    }

    /// The scan above is silent when it reads the wrong thing, so the same files
    /// are read for what they *do* carry: the three reads this module makes.
    func testTheScanSeesTheReadsItIsClearingTheModuleOf() throws {
        let reads = try SwiftSource.code(under: "Sources/Modules/Screenshots")
        let copies = reads.reduce(0) { $0 + $1.text.components(separatedBy: "CFPreferencesCopyAppValue").count - 1 }
        XCTAssertEqual(copies, 3, "the location, the symbolic hotkeys and the interface-sounds switch are the three reads")
    }

    /// The scan can fail: a writer put in front of it is found.
    func testAWriterIsFoundWhenThereIsOne() {
        let planted = SwiftSource.code("func f() { CFPreferencesSetAppValue(key, value, domain) }")
        XCTAssertTrue(Self.writers.contains { planted.contains($0) }, "a planted writer was not seen")
    }
}

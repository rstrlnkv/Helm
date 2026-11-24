import Foundation
import XCTest

/// A construction that forgets a port is an integration test nobody meant to
/// write.
///
/// An engine's `init` defaults every port to the real thing (the Mac's own
/// keychain, its `~/Library`, its `launchctl`), because the app builds one with
/// no arguments. A test that leaves a label off asks the owner's machine and
/// reports the answer as a fact about a fixture; a keychain default can roll
/// the owner's real rules back (Architecture/TestsAndMeasurement.md § Fakes).
///
/// Read off the source: every `<Engine>(` under a module's tests is a subject,
/// so a construction added later cannot quietly take a default.
/// `SwiftSource.code` blanks comments and string insides first, so a guard can
/// mention the shape it forbids without reporting itself.
///
/// The floor has no default, because a scan that can match zero and pass is
/// not a scan: a caller says how many constructions it expects.
///
/// The subject is named, not derived as in
/// `ATestNamesTheKeychainPortsItBuildsOverTests`: a keychain port announces
/// itself by name, and nothing spells a port that walks `~/Library` or shells
/// out to `launchctl`. Both read the same walk, `misses(of:under:)`.
///
/// A module whose defaults reach nothing on this Mac (an in-memory store, a
/// marker, `nil`) needs no `check(…)`; wiring another module is a `check(…)`
/// call and a fake at each site it names.
public enum PortsAtConstruction {

    /// Fails when any construction of `engine` under `directory` leaves one of
    /// `required` to its default, or when fewer than `floor` constructions were
    /// found at all.
    ///
    /// - Parameters:
    ///   - engine: the type's name, as it is written at a call site.
    ///   - directory: repo-relative, and the *module's* tests rather than one
    ///     half of them — a UI test may construct an engine too.
    ///   - required: argument labels without their colons.
    ///   - floor: how many constructions this directory holds. Lower it only by
    ///     deciding to, never to make a red go away.
    public static func check(_ engine: String,
                             under directory: String,
                             naming required: [String],
                             atLeast floor: Int,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws {
        let found = try misses(of: [engine: required], under: directory)
        let offenders = found.misses.map { "\($0.where_): \($0.missing.joined(separator: " "))" }

        XCTAssertGreaterThanOrEqual(found.constructions, floor, """
            the scan found \(found.constructions) construction(s) of `\(engine)` under \
            \(directory), and this module has at least \(floor) — so the walk or the match has \
            stopped reading and this check is guarding nothing.
            """, file: file, line: line)
        XCTAssertEqual(offenders, [], """
            these constructions of `\(engine)` leave a port to its default argument, which is \
            the real one on the machine running the suite:
            \(offenders.joined(separator: "\n"))
            """, file: file, line: line)
    }

    /// One construction that left a port on its default.
    public struct Miss: Sendable, Equatable {
        public let file: String
        public let type: String
        public let line: Int
        /// In the order the caller asked for them, so a message is the same
        /// twice.
        public let missing: [String]

        public var where_: String { "\(file):\(line)" }
    }

    /// Every construction under `directory` of a type in `subjects` that leaves
    /// one of that type's labels unnamed — **and how many constructions were
    /// seen at all**, which is the half that goes quiet.
    ///
    /// Two guards read this: `check(…)` above, for one named engine over a
    /// module's own tests, and `ATestNamesTheKeychainPortsItBuildsOverTests`,
    /// for every keychain-defaulted type over all of `Tests/`.
    public static func misses(of subjects: [String: [String]], under directory: String)
    throws -> (misses: [Miss], constructions: Int) {
        var found: [Miss] = []
        var constructions = 0

        // The shared, memoised reading: XCTest builds an instance per test
        // case, and the tree cannot change in between.
        for file in try SwiftSource.code(under: directory) {
            for (type, required) in subjects {
                for call in SwiftSource.callSites(of: type, in: file.text) {
                    constructions += 1
                    let missing = required.filter { !call.names.contains($0) }
                    guard !missing.isEmpty else { continue }
                    found.append(Miss(file: file.path, type: type,
                                      line: call.line, missing: missing))
                }
            }
        }
        return (found.sorted { ($0.file, $0.line, $0.type) < ($1.file, $1.line, $1.type) },
                constructions)
    }
}

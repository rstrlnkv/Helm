import Foundation
import XCTest

/// **A construction that forgets a port is an integration test nobody meant to
/// write.**
///
/// An engine's `init` gives every port a default, because the app builds one
/// with no arguments — and every one of those defaults is the real thing: the
/// Mac's own keychain, its `/etc/hosts`, its `~/.ssh`, its `launchctl`. A test
/// that leaves a label off therefore asks the owner's machine a question and
/// reports the answer as a fact about a fixture. Autopilot is the case that
/// makes this concrete: eleven engine tests took the keychain default and rolled
/// the owner's real rules back, and the installed build then refused every rule
/// as an older set put back (CLAUDE.md § a default argument naming a real port).
///
/// Read off the source rather than from a list beside a list: every
/// `<Engine>(` under a module's tests is a subject, so a construction added
/// later cannot quietly take a default. `SwiftSource.code` blanks comments and
/// string insides first, which is what lets a guard mention the very shape it
/// forbids — including this documentation — without reporting itself.
///
/// **The floor is not decoration.** The first version of the Hosts scan this was
/// lifted from matched nothing and reported every file clean; a scan that can
/// match zero and pass is not a scan. So the count of constructions found is a
/// parameter with no default: a caller has to say how many it expects to see.
///
/// **The subject is named rather than derived, and that is the only difference
/// from the guard next door.** `ATestNamesTheKeychainPortsItBuildsOverTests`
/// asks the same question of the whole tree at once and needs no list, because a
/// keychain port announces itself: it walks `Sources/` for every `init` whose
/// default reaches a declaration containing «Keychain», two hops deep. Nothing
/// spells a port that walks somebody's `~/Library` or shells out to `launchctl`,
/// so the subject here is a name and a floor. When something does spell them,
/// this should derive its subjects the same way and stop taking a list. The walk
/// underneath is one — `misses(of:under:)`, which both call.
///
/// Only Leftovers is wired to this today. `Tests/Modules/Hosts/EngineTests/EveryEngineNamesItsPortsTests.swift`
/// still carries the hand-rolled copy this was lifted out of, and the other
/// eight modules have no guard at all — not because their engines are safer, but
/// because those test directories had other writers in them when this landed.
/// Wiring one is a `check(…)` call and a fake at each site it names.
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
    /// Two guards read this. `check(…)` above asks about one named engine and a
    /// module's own tests; `ATestNamesTheKeychainPortsItBuildsOverTests` asks
    /// about every type in the tree whose default reaches the keychain, over the
    /// whole of `Tests/`, and applies its own list of exceptions to what comes
    /// back. The walk was written twice before it was written here, and the
    /// second copy was a hand-rolled bracket balancer that matched nothing on
    /// its first run.
    public static func misses(of subjects: [String: [String]], under directory: String)
    throws -> (misses: [Miss], constructions: Int) {
        var found: [Miss] = []
        var constructions = 0

        for relative in try RepoSource.swiftFiles(under: directory) {
            let source = SwiftSource.code(try RepoSource.text(of: relative))
            for (type, required) in subjects {
                for call in SwiftSource.callSites(of: type, in: source) {
                    constructions += 1
                    let missing = required.filter { !call.names.contains($0) }
                    guard !missing.isEmpty else { continue }
                    found.append(Miss(file: relative, type: type,
                                      line: call.line, missing: missing))
                }
            }
        }
        return (found.sorted { ($0.file, $0.line, $0.type) < ($1.file, $1.line, $1.type) },
                constructions)
    }
}

import Foundation
import XCTest

/// **A construction that forgets a port is an integration test nobody meant to
/// write.**
///
/// An engine's `init` gives every port a default, because the app builds one with
/// no arguments — and every one of those defaults is the real thing: the Mac's own
/// keychain, its `/etc/hosts`, its `~/.ssh`, its `launchctl`. A test that leaves a
/// label off therefore asks the owner's machine a question and reports the answer
/// as a fact about a fixture. Autopilot is the case that makes this concrete:
/// eleven engine tests took the keychain default and rolled the owner's real rules
/// back, and the installed build then refused every rule as an older set put back
/// (CLAUDE.md § What not to do, and what breaks if you do).
///
/// Read off the source rather than from a list beside a list: every
/// `<Engine>(` under a module's tests is a subject, so a construction added
/// later cannot quietly take a default. `SwiftSource.code` blanks comments and
/// string insides first, which is what lets a guard mention the very shape it
/// forbids — including this documentation — without reporting itself.
///
/// **An engine the test did not spell is a construction too.** A descriptor's
/// `makeEngine(store:)` is the construction the app runs: the caller hands it a
/// store and nothing else, so a test that calls it can name no port. `ModuleHost`
/// builds through it — `setEnabled` for one module, `bootstrap` for every module
/// not switched off — and activates what it built. No `<Engine>(` stands in such
/// a test's text, so `hostBuilt(in:)` reads those three calls by their receiver,
/// and both guards ask it.
///
/// **The floor is not decoration.** The first version of the Hosts scan this was
/// lifted from matched nothing and reported every file clean; a scan that can
/// match zero and pass is not a scan. So the count of constructions found is a
/// parameter with no default: a caller has to say how many it expects to see.
///
/// **The subject is named rather than derived, and nothing is excused —
/// where the guard next door derives and keeps lists.**
/// `ATestNamesTheKeychainPortsItBuildsOverTests` asks the same question of the
/// whole tree at once and needs no list of subjects, because a keychain port
/// announces itself: it walks `Sources/` for every `init` whose default reaches
/// a declaration containing «Keychain», two hops deep. Nothing spells a port
/// that walks somebody's `~/Library` or shells out to `launchctl`, so the
/// subject here is a name and a floor. When something does spell them, this
/// should derive its subjects the same way and stop taking a list. That guard
/// also keeps the lists of what it lets through, `allowed` and
/// `builtThroughTheHost`; `check` has none. The walk underneath is one —
/// `misses(of:under:)`, which both call — and so is the reading of what the
/// host builds, `hostBuilt(under:)`.
///
/// Only Leftovers is wired to `check` today. `Tests/Modules/Hosts/EngineTests/EveryEngineNamesItsPortsTests.swift`
/// still carries the hand-rolled copy this was lifted out of, and no other module
/// calls it (`command grep -rl 'PortsAtConstruction.check' Tests/Modules` names
/// the ones that do) — not because their engines are safer, but because those test
/// directories had other writers in them when this landed. What every module's
/// tests are asked whether or not it is wired is the whole-tree pair in
/// `ATestNamesTheKeychainPortsItBuildsOverTests`: the keychain ports, and who has
/// the host build. Wiring one is a `check(…)` call, a fake at each site it names,
/// and an engine built by name wherever a test had its descriptor build it.
public enum PortsAtConstruction {

    /// Fails when any construction of `engine` under `directory` leaves one of
    /// `required` to its default, when anything under `directory` has a
    /// descriptor or the host build an engine, or when fewer than `floor`
    /// constructions were found at all.
    ///
    /// **An engine built through a descriptor is reported whole**, with no
    /// label to list: `makeEngine(store:)` takes a store and nothing else, so
    /// that test named none of `required`. The scan cannot read which engine a
    /// descriptor builds, so every such call under `directory` is held against
    /// `engine`, a stub's included. There is no list of exceptions here: the
    /// files the tree lets build that way are named once, each with its reason,
    /// in `ATestNamesTheKeychainPortsItBuildsOverTests`, and a module that
    /// wires this check builds its engine by name instead. Those calls are not
    /// counted towards `floor`, which stays the number of `<engine>(`.
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
        let throughTheHost = try hostBuilt(under: directory).map { "\($0.where_): \($0.callee)" }

        XCTAssertEqual(throughTheHost, [], """
            these have a descriptor or the host build the engine, which hands it a store and no \
            port — so if that engine is `\(engine)`, every one of \(required.joined(separator: ", ")) is \
            the real one on the machine running the suite; the scan cannot read which engine it is. \
            Build `\(engine)` by name there, with each port named:
            \(throughTheHost.joined(separator: "\n"))
            """, file: file, line: line)
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

        // The shared reading rather than a walk of its own. XCTest builds an
        // instance per test case, and the keychain guard next door calls this
        // from two of them — which was two walks, two loads and two parses of
        // the whole of `Tests/` for an answer the tree cannot have changed in
        // between.
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

    // MARK: - An engine the host builds

    /// One call that has a descriptor or the shared host build an engine.
    public struct HostBuilt: Sendable, Equatable {
        public let file: String
        public let line: Int
        /// `makeEngine`, `setEnabled` or `bootstrap`.
        public let callee: String

        public var where_: String { "\(file):\(line)" }
    }

    /// The three calls an engine comes out of without its type being spelled.
    private static let builders = ["makeEngine", "setEnabled", "bootstrap"]

    /// A name bound to the host: `name = ModuleHost.shared`, or `name: ModuleHost`
    /// as a binding's or a parameter's type. An argument labelled
    /// `name: ModuleHost.shared` is neither, which is what the look-ahead is for.
    private static let hostBinding = try? NSRegularExpression(
        pattern: #"\b([A-Za-z_]\w*)\s*(?:=\s*ModuleHost\s*\.shared\b|:\s*ModuleHost\b(?!\s*\.))"#)

    /// Every call in `code` — a source as `SwiftSource.code` reads it — that
    /// has a descriptor or the shared host build an engine.
    ///
    /// **The receiver is what is read, because the callee's name says nothing**:
    /// the log, the hosts file and a view model each have a `setEnabled`, and
    /// tests call their own helpers `makeEngine`. Three clauses, and which way
    /// each errs when it cannot tell:
    ///
    /// - `makeEngine(` with a dot in front of it, whatever stands on the other
    ///   side of the dot. A declaration and a bare call of a test's own helper
    ///   have no dot and are not counted; a call through `self.`, or on a stub
    ///   descriptor a test declares, is counted — towards reporting.
    /// - `setEnabled(` and `bootstrap(` whose receiver is `ModuleHost.shared`,
    ///   read across the line break Swift allows in front of a dot. A call that
    ///   switches a module off is counted with the rest, because the flag is an
    ///   expression and this evaluates none — towards reporting.
    /// - the same two on a name this source binds to the host (`hostBinding`),
    ///   as the last component of the receiver. The binding is looked for in
    ///   the whole source and not in the call's scope, so an unrelated second
    ///   use of the name in that file is counted too — towards reporting.
    ///
    /// **A host that arrives any other way is not seen**, and that errs
    /// towards excusing: one returned by a function, bound in another file,
    /// bound to a second name, written with its module in front, wrapped in
    /// parentheses or called through `?.` or `!.`. A host held as a property
    /// of something else is seen where this source binds the property's name
    /// to the host, and not where another file does. A call is missed the
    /// same way when it is taken without its brackets, has a space in front
    /// of the bracket, or stands inside a string's interpolation.
    /// `ModuleHost`'s `init` is private, so every host is `ModuleHost.shared` —
    /// but Swift lets that be written as a bare `.shared` wherever the type is
    /// known, so a search for `ModuleHost.shared` does not find every such
    /// route when this reports nothing.
    ///
    /// - Parameter path: what a finding names as its file.
    public static func hostBuilt(in code: String, path: String = "<source>") -> [HostBuilt] {
        // The fast no `callSites` makes per callee, made once for the three: a
        // source that spells none of them with a dot in front needs no copy.
        guard builders.contains(where: { code.contains(".\($0)(") }) else { return [] }
        let characters = Array(code)
        let whole = NSRange(code.startIndex..., in: code)
        let bound = Set(hostBinding?.matches(in: code, range: whole).compactMap {
            Range($0.range(at: 1), in: code).map { String(code[$0]) }
        } ?? [])

        var found: [HostBuilt] = []
        for callee in builders {
            for call in SwiftSource.callSites(of: callee, in: code, wholeWords: false)
            where call.characterOffset > 0 && characters[call.characterOffset - 1] == "." {
                if callee != "makeEngine" {
                    let on = receiver(before: call.characterOffset - 1, in: characters)
                    guard on == "ModuleHost.shared"
                            || bound.contains(on.components(separatedBy: ".").last ?? "")
                    else { continue }
                }
                found.append(HostBuilt(file: path, line: call.line, callee: callee))
            }
        }
        return found.sorted { ($0.line, $0.callee) < ($1.line, $1.callee) }
    }

    /// `hostBuilt(in:)` over every `.swift` file under `directory`, off the
    /// reading `misses(of:under:)` walks — so asking both costs one load.
    public static func hostBuilt(under directory: String) throws -> [HostBuilt] {
        try SwiftSource.code(under: directory)
            .flatMap { hostBuilt(in: $0.text, path: $0.path) }
            .sorted { ($0.file, $0.line, $0.callee) < ($1.file, $1.line, $1.callee) }
    }

    /// The names and dots the dot at `dot` hangs on, read leftwards. White space
    /// is passed over only where a dot follows it, which is where Swift lets a
    /// chain break; anything else ends the reading, so a receiver that closes
    /// with a bracket or a `?` reads as empty.
    private static func receiver(before dot: Int, in characters: [Character]) -> String {
        var taken: [Character] = []
        var index = dot - 1
        while index >= 0 {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                taken.append(character)
            } else if !(character.isWhitespace && (taken.last ?? ".") == ".") {
                break
            }
            index -= 1
        }
        return String(taken.reversed())
    }
}

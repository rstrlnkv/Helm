import XCTest
import HelmTestSupport

/// Nothing under `Sources/Modules/Hosts` spells a way to write `/etc/hosts` or
/// to ask root for anything.
///
/// The scan reads every Swift file of the module the way the compiler roughly
/// does (`SwiftSource.uncommented`): comments blanked, string literals kept. A
/// doc comment may therefore still explain why the module never touches the
/// file, and a literal or a type name may not say that it does.
///
/// **The needles are the spellings of the doors, not of the file alone.** The
/// path `/etc/` is one; the rest are what a write to it has to go through:
/// `PrivilegedRun` and its outcome type, `AppleScript` and the sentence it
/// builds, `osascript` and `sudo` as programs, `SudoersRule`. A bare `sudo` is
/// not a needle — it is inside "pseudo". Each needle is held against a file in
/// the tree that really spells it, so a door renamed over there turns the
/// matching row red here instead of leaving this scan reading for a word nobody
/// writes any more.
///
/// A scan that finds nothing is also what a scan that read nothing prints, so
/// a row asserts the walk returned the engine's own file, and rows run the same
/// matcher over text written for the purpose: a needle inside a string literal
/// or an identifier is found, with its line, and the same needle inside a doc
/// comment, a line comment or a block comment is not.
final class NoDoorToRootInHostsTests: XCTestCase {

    private static let module = "Sources/Modules/Hosts"

    /// A needle and a file of the tree that spells it in code or in a literal.
    private static let doors: [(needle: String, spelledIn: String)] = [
        ("/etc/", "Sources/Modules/KeepAwake/Engine/Logic/SudoersRule.swift"),
        ("PrivilegedRun", "Sources/HelmRuntime/PrivilegedRun.swift"),
        ("PrivilegedOutcome", "Sources/HelmRuntime/PrivilegedRun.swift"),
        ("AppleScript", "Sources/HelmRuntime/AppleScript.swift"),
        ("administrator privileges", "Sources/HelmRuntime/AppleScript.swift"),
        ("do shell script", "Sources/HelmRuntime/AppleScript.swift"),
        ("osascript", "Sources/HelmRuntime/PrivilegedRun.swift"),
        ("/bin/sudo", "Sources/Modules/KeepAwake/Engine/SystemPorts.swift"),
        ("SudoersRule", "Sources/Modules/KeepAwake/Engine/Logic/SudoersRule.swift"),
    ]

    private static var needles: [String] { doors.map(\.needle) }

    /// Every needle on every line of `text`, as `path:line: needle`. `text` is
    /// already read with its comments blanked and its newlines kept, so the
    /// line number is the file's own.
    private static func hits(in text: String, path: String) -> [String] {
        var out: [String] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            for needle in needles where line.contains(needle) {
                out.append("\(path):\(index + 1): \(needle)")
            }
        }
        return out
    }

    // MARK: - The scan

    func testNoFileOfTheModuleSpellsADoorToRoot() throws {
        var found: [String] = []
        for file in try SwiftSource.uncommented(under: Self.module) {
            found += Self.hits(in: file.text, path: file.path)
        }
        XCTAssertTrue(found.isEmpty, """
            the module spells a way to write `/etc/hosts` or to ask root; each hit as \
            file:line: needle
            """ + "\n" + found.joined(separator: "\n"))
    }

    // MARK: - And the scan can fail

    func testTheWalkReadTheEngine() throws {
        let read = try SwiftSource.uncommented(under: Self.module)
        XCTAssertTrue(read.map(\.path).contains("Sources/Modules/Hosts/Engine/HostsEngine.swift"),
                      "the walk returned \(read.count) files and the engine is not among them")
    }

    func testANeedleInACodeOrALiteralIsFound() {
        let source = """
            let p = "/etc/hosts"
            let run = PrivilegedRun.run(command)
            """
        XCTAssertEqual(Self.hits(in: SwiftSource.uncommented(source), path: "x.swift"),
                       ["x.swift:1: /etc/", "x.swift:2: PrivilegedRun"])
    }

    func testANeedleInACommentIsNotFound() {
        let source = """
            /// /etc/hosts, written through `PrivilegedRun`.
            // osascript and /usr/bin/sudo
            /* AppleScript
               SudoersRule */
            let harmless = 1 // administrator privileges
            """
        XCTAssertEqual(Self.hits(in: SwiftSource.uncommented(source), path: "x.swift"), [])
    }

    func testEveryNeedleIsStillSpelledByTheDoorItNames() throws {
        for door in Self.doors {
            let text = SwiftSource.uncommented(try RepoSource.text(of: door.spelledIn))
            XCTAssertTrue(text.contains(door.needle),
                          "`\(door.needle)` is no longer spelled in \(door.spelledIn): the scan reads for a word the door does not use")
        }
    }
}

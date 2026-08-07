import XCTest

/// An event name is a declaration both sides read, never a string typed twice.
///
/// `CommandNamesAreAnsweredTests` pins this for commands — a module sending a
/// name its own engine has no `case` for. Events are the same contract in the
/// other direction and had no check at all, which is how the host came to write
///
///     for await event in events where event.name == "trashChanged"
///
/// under a comment explaining that the transport boundary left it no choice. It
/// did not: a descriptor re-exports its engine's enum the way `KeepAwakeCommand`
/// and `LayoutCommand` are already re-exported for the hotkeys, so the host can
/// say the name instead of spelling it.
///
/// **The failure has no symptom at the seam.** Rename the case in the engine and
/// nothing is an error anywhere; the emitter emits a name nobody listens for and
/// the listener waits for a name nobody emits. What the person sees is a feature
/// going quiet — drag an app to the Trash and Helm never offers to clear up
/// after it — which is indistinguishable from the feature being switched off.
///
/// Both directions are checked, because either one alone can drift: a literal
/// handed to `EngineEvent(name:)` and a literal compared against `event.name`.
final class EventNamesAreNotLiteralsTests: XCTestCase {

    /// The line with its comment tail removed. This file's own explanation
    /// quotes the offending line, and so does `AppDelegate`'s — a scan that
    /// reads comments reports the warning as the offence.
    private func code(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    /// `name:` followed by a quote, and `event.name ==` followed by a quote.
    private func offences(in line: String) -> [String] {
        var found: [String] = []
        for pattern in ["EngineEvent(name: \"", ".name == \""] where line.contains(pattern) {
            found.append(pattern)
        }
        return found
    }

    func testNoEventNameIsWrittenAsALiteral() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")

        var offenders: [String] = []
        var scanned = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            scanned += 1
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let text = code(line)
                for pattern in offences(in: text) {
                    offenders.append("\(url.lastPathComponent):\(index + 1) — \(pattern) "
                                     + text.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        XCTAssertGreaterThan(scanned, 100,
                             "only \(scanned) source files were read, so a pass proves nothing")
        XCTAssertTrue(offenders.isEmpty,
                      "an event name was written as a string. Put it in the module's "
                      + "`<Module>Event` enum and re-export that through its descriptor, "
                      + "the way the hotkeys re-export their command enums — a renamed "
                      + "case is then a build error rather than a feature going quiet:\n"
                      + offenders.joined(separator: "\n"))
    }
}

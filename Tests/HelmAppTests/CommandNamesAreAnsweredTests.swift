import XCTest

/// A command name a caller sends must be one its engine handles.
///
/// **A typo is silence, and silence already means something else here.** A name
/// the engine does not recognise falls to `default: return Data()`; the caller
/// decodes nothing and gets `nil`, which this codebase reads as "the module
/// could not answer". So a misspelling is indistinguishable from a refusal, and
/// the only symptom is a feature that quietly does nothing.
///
/// The typed cure is an enum per module — 43 distinct names across nine modules
/// and 61 call sites, which is a day of churn and a real improvement. A *global*
/// enum is the wrong shape: every engine handles its own subset, so no switch
/// over it could be exhaustive, and the compiler would stay silent exactly where
/// this test speaks. Until the per-module enums exist, this scan closes the same
/// defect for the price of an hour.
///
/// **Per module, because a name means nothing on its own.** `"scan"` is a Disk
/// command and a Duplicates command and they are different commands; the
/// question is only ever whether *this* module's engine answers what *this*
/// module's UI sends.
final class CommandNamesAreAnsweredTests: XCTestCase {

    private var modules: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // HelmAppTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo
            .appendingPathComponent("Sources/Modules")
    }

    private func swiftFiles(under url: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: url,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func matches(_ pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    func testEveryCommandAModuleSendsIsOneItsEngineHandles() throws {
        let moduleDirectories = try FileManager.default
            .contentsOfDirectory(at: modules, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
        XCTAssertEqual(moduleDirectories.count, 9, "the modules moved; this test walks Sources/Modules")

        for module in moduleDirectories {
            var asked: Set<String> = []
            var handled: Set<String> = []
            for file in swiftFiles(under: module) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                if file.pathComponents.contains("Engine") {
                    handled.formUnion(matches("case\\s+\"([A-Za-z][A-Za-z0-9.]*)\"\\s*:", in: text))
                } else {
                    // A literal on the calling side. A name written as a shared
                    // constant — `ScanCommand.backgroundScan` — appears in
                    // neither set, which is the point of spelling it that way:
                    // there is one string and both sides read it.
                    asked.formUnion(matches("\\b(?:request|fire|send)\\(\\s*\"([A-Za-z][A-Za-z0-9.]*)\"",
                                            in: text))
                }
            }
            for name in asked.sorted() where !handled.contains(name) {
                XCTFail("\(module.lastPathComponent) sends `\(name)` and its engine has no case for it")
            }
        }
    }

    // There is deliberately no check the other way — a `case` nothing sends.
    //
    // Four of VPN's nine and two of Layout's three are handled without a literal
    // caller in the module, and "dead" is not the only explanation: the host
    // sends some, and a caller may spell the name through a constant. A guard
    // that would need each of those investigated before it could go green is a
    // guard that goes in with exceptions already in it, which is how a ledger
    // starts excusing things. The asked-not-handled direction is the one with a
    // known failure mode behind it.
}

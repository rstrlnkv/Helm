import XCTest
import HelmContract
@testable import HelmApp

/// A store namespace is a module's id, and the id has one spelling.
///
/// `NamespacedStore(namespace:)` decides which `module.<id>.*` keys a module
/// reads and writes, so a namespace that disagrees with its descriptor's `id`
/// does not fail — it reads a **different store**, which answers with defaults.
/// The person sees their settings gone, and nothing anywhere is an error.
///
/// Eight sites spelled a namespace as a literal when this was written, and all
/// eight happened to agree with their descriptor. That is the state this check
/// exists to keep: agreement by construction rather than by coincidence, and
/// the literal was never protecting anything — changing a descriptor id is
/// already a breaking change for stored settings, and a second spelling only
/// hides half of the breakage.
///
/// Six of the eight now read `<Module>Descriptor.id.rawValue` directly, which
/// cannot drift. Two cannot: `"app"` belongs to the host and names no module,
/// and `UninstallerEngine`'s default store is engine-side, where the descriptor
/// is out of reach on purpose — an engine importing a UI target would be a door
/// past the transport. Those two are what this test is for.
@MainActor
final class StoreNamespacesAreModuleIdsTests: XCTestCase {

    /// The host's own namespace. Not a module, and deliberately named here
    /// rather than pattern-matched, so adding a second non-module store is a
    /// decision somebody writes down.
    private static let hostNamespace = "app"

    private func code(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    func testEveryNamespaceLiteralNamesARegisteredModule() throws {
        let known = Set(ModuleRegistry.all.map { type(of: $0).id.rawValue })
            .union([Self.hostNamespace])
        XCTAssertGreaterThan(known.count, 5,
                             "the registry answered with almost nothing, so this proves nothing")

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")

        var offenders: [String] = []
        var found = 0
        let marker = "NamespacedStore(namespace: \""
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let text = code(line)
                guard let start = text.range(of: marker),
                      let end = text.range(of: "\"", range: start.upperBound..<text.endIndex)
                else { continue }
                found += 1
                let namespace = String(text[start.upperBound..<end.lowerBound])
                if !known.contains(namespace) {
                    offenders.append("\(url.lastPathComponent):\(index + 1) — \"\(namespace)\"")
                }
            }
        }

        XCTAssertGreaterThan(found, 0,
                             "no namespace literal was found at all, so this scan is "
                             + "looking for something that has changed shape")
        XCTAssertTrue(offenders.isEmpty,
                      "a store namespace names no registered module. The module will read "
                      + "an empty store and answer with defaults, which the person sees as "
                      + "their settings having been forgotten:\n"
                      + offenders.joined(separator: "\n"))
    }
}

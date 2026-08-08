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
/// cannot drift. `UninstallerEngine`'s default store was the seventh and was
/// argued to be unfixable — engine-side, where the descriptor is out of reach on
/// purpose, since an engine importing a UI target would be a door past the
/// transport. The door was the wrong way round: the engine declares `moduleID`
/// and the descriptor reads *it*, so nothing has to import upward. The eighth,
/// `"app"`, stays a literal because it belongs to the host and names no module,
/// and that is what this first test is for.
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

    /// Every line of Swift under `Sources/<subpath>`, comments stripped, with
    /// somewhere to say it. Both tests below read the tree; only what they look
    /// for differs.
    private func eachSourceLine(under subpath: String,
                                _ visit: (_ where: String, _ code: String) -> Void) -> Int {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent(subpath)

        var files = 0
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            files += 1
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                visit("\(url.lastPathComponent):\(index + 1)", code(line))
            }
        }
        return files
    }

    func testEveryNamespaceLiteralNamesARegisteredModule() throws {
        let known = Set(ModuleRegistry.all.map { type(of: $0).id.rawValue })
            .union([Self.hostNamespace])
        XCTAssertGreaterThan(known.count, 5,
                             "the registry answered with almost nothing, so this proves nothing")

        var offenders: [String] = []
        var found = 0
        let marker = "NamespacedStore(namespace: \""
        _ = eachSourceLine(under: "Sources") { site, text in
            guard let start = text.range(of: marker),
                  let end = text.range(of: "\"", range: start.upperBound..<text.endIndex)
            else { return }
            found += 1
            let namespace = String(text[start.upperBound..<end.lowerBound])
            if !known.contains(namespace) {
                offenders.append("\(site) — \"\(namespace)\"")
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

    // MARK: - The ids that are already on people's machines

    /// The ids that shipped, written down because they are **data, not names**.
    ///
    /// A module id is the `module.<id>.*` prefix of every setting that module
    /// has ever saved, and for three of them it is a directory under
    /// Application Support as well. Renaming one is not a rename: the old keys
    /// stay where they are and the module reads an empty store, so the person
    /// finds their folder, their schedule and their exclusions gone, with
    /// nothing anywhere reporting an error.
    ///
    /// Nothing caught that. Measured rather than assumed — `LeftoversEngine`'s
    /// id was changed to `leftoverz` and the whole suite passed, 2182 tests, 0
    /// failures, because Leftovers is not a scannable module and so appears in
    /// no other list. `ListsAgreeWithTheTreeTests` covers only the three that
    /// `ScanRunner.scannableModules` names.
    ///
    /// So this is a hand-written list, and it is the kind CLAUDE.md allows: it
    /// is not a second spelling of anything the tree already knows, it is a
    /// record of what is on disk elsewhere. A module gained or renamed on
    /// purpose edits it, and that edit is the moment to think about the
    /// settings being left behind.
    private static let shippedIDs: Set<String> = [
        "autopilot", "disk", "duplicates", "homebrew", "keep-awake",
        "layout", "leftovers", "uninstaller", "vpn",
    ]

    @MainActor func testNoModuleIdChangesUnderneathItsStoredSettings() {
        let now = Set(ModuleRegistry.all.map { type(of: $0).id.rawValue })

        XCTAssertEqual(now, Self.shippedIDs,
                       "a module id moved. Every `module.<id>.*` key that module has "
                       + "saved stays under the old name, so the person's settings are "
                       + "gone with nothing to say so — gained: \(now.subtracting(Self.shippedIDs)), "
                       + "lost: \(Self.shippedIDs.subtracting(now))")
    }

    // MARK: - Inside a module, an id is never a literal

    /// The other half, and the one that closes the loophole above.
    ///
    /// A module id reaches disk in three shapes: the store namespace, the
    /// journal and cache directory `ScanJournal` names after it, and the
    /// `module:` a removal is attributed to in the log. Every one of those was
    /// a literal typed inside an engine, where the descriptor is out of reach —
    /// so the id had a third spelling that nothing compared with the other two,
    /// and it named a **directory on disk**: change it and yesterday's journal
    /// and hash cache are simply not found again.
    ///
    /// Each engine now declares `moduleID` and its descriptor forwards it
    /// (`static let id = ModuleID(DuplicatesEngine.moduleID)`), the direction
    /// the descriptors already carry their command enums. That makes the two
    /// spellings one by construction; what this test does is stop a third
    /// growing back. It scans `Sources/Modules` alone: outside a module a
    /// `module:` argument may legitimately name something that is not one —
    /// `ResetEverything` passes `"reset"` — and inside one there is nothing to
    /// name but itself.
    func testNoModuleSpellsItsOwnIdAsALiteral() throws {
        var offenders: [String] = []
        var callSites = 0
        let scanned = eachSourceLine(under: "Sources/Modules") { site, text in
            for marker in ["module: ", "namespace: "] {
                guard let start = text.range(of: marker) else { continue }
                callSites += 1
                guard text[start.upperBound...].hasPrefix("\"") else { continue }
                offenders.append("\(site) — \(text.trimmingCharacters(in: .whitespaces))")
            }
        }

        // Two controls, because a scan that reaches nothing reports nothing.
        XCTAssertGreaterThan(scanned, 50,
                             "only \(scanned) files under Sources/Modules were read, so this "
                             + "scan is looking somewhere that has moved")
        XCTAssertGreaterThan(callSites, 0,
                             "no `module:` or `namespace:` argument was found at all, so the "
                             + "markers this scan looks for have changed shape")

        XCTAssertTrue(offenders.isEmpty,
                      "a module spells its own id as a literal. It names a directory on disk "
                      + "and a store, and nothing compares it with the descriptor's `id` — "
                      + "read `<Engine>.moduleID` instead:\n"
                      + offenders.joined(separator: "\n"))
    }
}

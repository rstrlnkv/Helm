import XCTest
import HelmContract
import HelmTestSupport
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
/// contract. The door was the wrong way round: the engine declares `moduleID`
/// and the descriptor reads *it*, so nothing has to import upward. The eighth,
/// `"app"`, stays a literal because it belongs to the host and names no module,
/// and that is what this first test is for.
@MainActor
final class StoreNamespacesAreModuleIdsTests: XCTestCase {

    /// The host's own namespace. Not a module, and deliberately named here
    /// rather than pattern-matched, so adding a second non-module store is a
    /// decision somebody writes down.
    private static let hostNamespace = "app"

    /// Every line of Swift under `<subpath>`, comments blanked, with somewhere
    /// to say it. Both tests below read the tree; only what they look for differs.
    private func eachSourceLine(under subpath: String,
                                _ visit: (_ where: String, _ code: String) -> Void) throws -> Int {
        let reads = try SwiftSource.uncommented(under: subpath)
        for read in reads {
            for (index, line) in read.text.components(separatedBy: "\n").enumerated() {
                visit("\(read.path):\(index + 1)", line)
            }
        }
        return reads.count
    }

    func testEveryNamespaceLiteralNamesARegisteredModule() throws {
        let known = Set(ModuleRegistry.all.map { type(of: $0).id.rawValue })
            .union([Self.hostNamespace])
        XCTAssertGreaterThan(known.count, 5,
                             "the registry answered with almost nothing, so this proves nothing")

        var offenders: [String] = []
        var found = 0
        let marker = "NamespacedStore(namespace: \""
        _ = try eachSourceLine(under: "Sources") { site, text in
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

    // MARK: - The registered ids, the prefix of what people saved

    /// The registered ids, written down because they are **data, not names**.
    ///
    /// A module id is the `module.<id>.*` prefix of every setting that module
    /// has ever saved — the host's on/off switch among them — and for the
    /// modules that scan it also names a folder under Application Support,
    /// `Scans/<id>` (`ScanJournal.directory(module:)`). Renaming one is not a
    /// rename: the old keys stay where they are and the module reads an empty
    /// store, so the person finds their folder, their schedule and their
    /// exclusions gone, with nothing anywhere reporting an error.
    ///
    /// Nothing caught that. Measured rather than assumed — `LeftoversEngine`'s
    /// id was changed to `leftoverz` and the whole suite passed, 2182 tests, 0
    /// failures, because Leftovers is not a scannable module and so appears in
    /// no other list. `ListsAgreeWithTheTreeTests` covers only the three that
    /// `ScanRunner.scannableModules` names.
    ///
    /// So this is a hand-written list, and it is the kind the house rules allow: it
    /// is not a second spelling of anything the tree already knows, it is the
    /// prefixes the registered modules' keys are stored under in people's
    /// defaults. A module gained or renamed on purpose edits it, and that edit
    /// is the moment to think about the settings being left behind. A module
    /// archived leaves the list and its keys stay: Hosts' `module.hosts.*` keys
    /// are still on machines, and the tag `archive/hosts` holds the module that
    /// read them.
    private static let registeredIDs: Set<String> = [
        "autopilot", "disk", "duplicates", "homebrew", "keep-awake", "launchpad",
        "layout", "leftovers", "screenshots", "tweaks", "uninstaller", "vpn",
    ]

    @MainActor func testNoModuleIdChangesUnderneathItsStoredSettings() {
        let now = Set(ModuleRegistry.all.map { type(of: $0).id.rawValue })

        XCTAssertEqual(now, Self.registeredIDs,
                       "a module id moved. Every `module.<id>.*` key that module has "
                       + "saved stays under the old name, so the person's settings are "
                       + "gone with nothing to say so — gained: \(now.subtracting(Self.registeredIDs)), "
                       + "lost: \(Self.registeredIDs.subtracting(now))")
    }
}

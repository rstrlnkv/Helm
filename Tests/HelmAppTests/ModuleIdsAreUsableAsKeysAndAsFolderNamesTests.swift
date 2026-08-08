import XCTest
@testable import HelmApp
import HelmContract

/// What a module id has to survive being used as, now that the descriptor
/// forwards it up from the engine.
///
/// `ListsAgreeWithTheTreeTests` proves the ids are unique and
/// `StoreNamespacesAreModuleIdsTests` proves none of the nine that shipped has
/// moved. Neither says anything about the two *other* things every id is: a
/// key in the dictionaries the host builds, and a component of a path.
///
/// The forwarding — `static let id = ModuleID(DiskEngine.moduleID)` — makes
/// four of the ids come from a constant one target away, which is the point;
/// it also means the string a host looks a module up by is no longer written
/// beside the descriptor that answers to it.
@MainActor
final class ModuleIdsAreUsableAsKeysAndAsFolderNamesTests: XCTestCase {

    /// The host looks modules up two ways — `first { $0.idRaw == id }` on a
    /// `String` at seventeen call sites, and `ModuleID` where the contract
    /// carries it. Those two have to be the same lookup.
    ///
    /// `idRaw` is `type(of: self).id.rawValue`, read off the metatype of an
    /// *instance*, while the canon test reads it off the type. A dictionary
    /// keyed by `ModuleID` and probed with `ModuleID(descriptor.idRaw)` is the
    /// round trip both spellings have to survive, and it is also what proves
    /// `ModuleID`'s `Hashable` still agrees with its `==` — a wrapper whose
    /// hash and equality disagree loses entries in a dictionary rather than
    /// answering wrongly, which nothing else here would notice.
    func testEveryDescriptorIsFoundByTheIdItAnswersWith() {
        var byID: [ModuleID: String] = [:]
        for descriptor in ModuleRegistry.all {
            byID[type(of: descriptor).id] = descriptor.idRaw
        }

        XCTAssertEqual(byID.count, ModuleRegistry.all.count,
                       "\(ModuleRegistry.all.count) modules made \(byID.count) keys — two "
                       + "descriptors hash to one entry")
        for descriptor in ModuleRegistry.all {
            XCTAssertEqual(byID[ModuleID(descriptor.idRaw)], descriptor.idRaw,
                           "`\(descriptor.idRaw)` is not found by the string the host looks "
                           + "it up with, though its own type answers to it")
        }
    }

    /// An id is a **directory name**: `ScanJournal` names the folder a module's
    /// journal and hash cache live in after it, and `HelmTrash.remove` takes it
    /// as `module:`. It is also the `module.<id>.` prefix of every stored
    /// setting.
    ///
    /// So a separator in one would be a path joined onto a path — the id would
    /// name a folder somewhere else entirely, or, with `..` in it, somewhere
    /// above. Nothing in the build says an id may not contain one, and since
    /// the id now travels up from an engine constant, the descriptor's own file
    /// no longer shows the string being registered.
    ///
    /// Asserted per module with the id in the message: every one of these is a
    /// property of the whole set, and a failure has to name which.
    func testNoModuleIdCanEscapeTheFolderOrTheKeyItNames() {
        for descriptor in ModuleRegistry.all {
            let id = descriptor.idRaw
            XCTAssertFalse(id.isEmpty, "a module has an empty id")
            XCTAssertFalse(id.contains("/"),
                           "`\(id)` carries a path separator, and it is used as a directory "
                           + "name (ScanJournal) — the journal would be written elsewhere")
            XCTAssertFalse(id.contains(".."),
                           "`\(id)` can climb out of the folder it names")
            XCTAssertFalse(id.hasPrefix("."),
                           "`\(id)` names a hidden folder, and `module..\(id)` as a key")
            XCTAssertFalse(id.contains("."),
                           "`\(id)` carries the separator the `module.<id>.<key>` prefix is "
                           + "built from, so its keys cannot be told from another module's")
            XCTAssertFalse(id.contains(where: { $0.isWhitespace }),
                           "`\(id)` carries whitespace")
            XCTAssertEqual(id, id.trimmingCharacters(in: .whitespacesAndNewlines), "`\(id)`")
            XCTAssertEqual(id, id.precomposedStringWithCanonicalMapping,
                           "`\(id)` is not in the normal form a filesystem will hand back, "
                           + "so the folder it names and the folder it finds differ")
        }
    }

    /// Two ids that differ only in case are two folders on a case-sensitive
    /// volume and one on the boot volume, and two distinct `ModuleID`s either
    /// way — which is the shape where a store and a journal disagree about how
    /// many modules there are.
    func testNoTwoModuleIdsDifferOnlyInCase() {
        let folded = ModuleRegistry.all.map { $0.idRaw.lowercased() }
        XCTAssertEqual(Set(folded).count, folded.count,
                       "two module ids differ only in case: \(folded.sorted())")
    }
}

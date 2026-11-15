import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// A save racing a read of the same sealed setting.
///
/// `stored` reads the value and its MAC as a pair and may write a MAC for the
/// value it read. A save between that read and that write leaves the new value
/// beside a MAC sealed over the old one, and the next background scan refuses
/// the folder the person just chose. Shaped like `AutopilotSealRaceTests`.
///
/// **Past defect:** two writers over one value-and-MAC pair, with no order.
final class DuplicatesSealRaceTests: XCTestCase {

    private let rounds = 5_000
    private let folder = DuplicatesSettings.folderKey

    private func fresh(firstUse: Bool) -> (NamespacedStore, SettingGuard) {
        (NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore()),
         SettingGuard(keys: SealKeyProbe(firstUse: firstUse)))
    }

    /// A sealed folder being replaced is never read as somebody else's.
    func testASaveDuringAReadNeverMakesTheFolderNotHelmsOwn() {
        let (store, settings) = fresh(firstUse: false)
        DuplicatesSettings.setFolder("/A", in: store, guardedBy: settings)
        let finished = DispatchSemaphore(value: 0)
        let rounds = self.rounds
        Thread {
            for i in 0..<rounds {
                DuplicatesSettings.setFolder(i.isMultiple(of: 2) ? "/B" : "/A",
                                             in: store, guardedBy: settings)
            }
            finished.signal()
        }.start()
        var refused = 0
        for _ in 0..<rounds {
            if case .notHelmsOwn = DuplicatesSettings.stored(folder, in: store, guardedBy: settings) {
                refused += 1
            }
        }
        finished.wait()
        XCTAssertEqual(refused, 0, "reads refused a folder Helm itself had just saved")
    }

    /// On the run that creates the key, an adoption racing a save never leaves
    /// a value beside a MAC sealed over the other value.
    func testAnAdoptionRacingASaveNeverSealsTheOtherValue() {
        let (store, settings) = fresh(firstUse: true)
        let reference = SettingGuard(keys: SealKeyProbe(firstUse: false))
        var torn = 0
        for _ in 0..<rounds {
            store.set("/A", for: folder)
            store.set(nil, for: SettingGuard.macKey(for: folder))
            DispatchQueue.concurrentPerform(iterations: 2) { n in
                if n == 0 {
                    _ = DuplicatesSettings.stored(folder, in: store, guardedBy: settings)
                } else {
                    DuplicatesSettings.setFolder("/B", in: store, guardedBy: settings)
                }
            }
            let value = store.string(folder, default: "")
            let mac = store.string(SettingGuard.macKey(for: folder), default: "")
            if reference.seal(Data(value.utf8)) != mac { torn += 1 }
        }
        XCTAssertEqual(torn, 0, "a MAC was sealed over a value other than the one stored beside it")
    }
}

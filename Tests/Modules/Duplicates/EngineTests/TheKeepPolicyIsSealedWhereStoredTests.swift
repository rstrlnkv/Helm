import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The keep policy steers work nobody is watching — a background scan decides
/// which of somebody's identical files is the spare one — and it lives in
/// `com.helm.app.plist`, which any process running as this user can rewrite.
///
/// **It refuses in a different direction from the folder beside it.** The
/// folder says *where* an unattended
/// reader walks, so a value Helm did not write stops the walk. This one only
/// says which of two identical files is offered for deletion: taking the whole
/// feature away to defend a preference is refusing in the unsafe direction, so a
/// broken seal is the default and a line in the log.
final class TheKeepPolicyIsSealedWhereStoredTests: XCTestCase {

    private var store: NamespacedStore!
    private let key = DuplicatesSettings.keepPolicyKey

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: DuplicatesEngine.moduleID,
                                backing: InMemoryKeyValueStore())
    }

    private func engine(_ keys: SealKeyProbe) -> DuplicatesEngine {
        DuplicatesEngine(store: store, settings: SettingGuard(keys: keys),
                         trashing: neverTrashes)
    }

    private func seal(_ value: String, with keys: SealKeyProbe) {
        store.set(value, for: key)
        store.set(SettingGuard(keys: keys).seal(Data(value.utf8)) ?? "",
                  for: SettingGuard.macKey(for: key))
    }

    // MARK: - What is stored, when Helm stored it

    func testASealedPolicyIsTheOneTheSearchUses() {
        let keys = SealKeyProbe(firstUse: false)
        seal(KeepPolicy.byDate.rawValue, with: keys)

        XCTAssertEqual(engine(keys).storedKeepPolicy(), .byDate)
    }

    /// The save itself: what `setKeepPolicy` writes is read back as chosen, so it
    /// wrote the MAC beside the value. A save that stored the value alone would
    /// come back as a policy nobody sealed, and the search would use the default.
    func testASavedPolicyIsTheOneTheSearchUses() {
        let keys = SealKeyProbe(firstUse: false)
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: keys))

        XCTAssertEqual(engine(keys).storedKeepPolicy(), .byDate)
    }

    func testAMacThatWasNeverAskedGetsTheDefault() {
        XCTAssertEqual(engine(SealKeyProbe(firstUse: false)).storedKeepPolicy(), .standard)
    }

    /// The door `.adopt` leaves open is spent on the first read, whatever is
    /// stored. A getter that answers with its default before touching the guard
    /// leaves an installation sitting one unsealed value away from adopting a
    /// stranger's for ever.
    func testTheKeyIsEstablishedOnTheFirstReadEvenWithNothingStored() {
        let keys = SealKeyProbe(firstUse: true)

        XCTAssertEqual(engine(keys).storedKeepPolicy(), .standard)

        XCTAssertGreaterThan(keys.reads, 0,
                             "nothing was stored and the guard was never touched, "
                             + "so the adoption door is still open tomorrow")
    }

    /// And the door itself, on the run that creates the key: a policy chosen
    /// before this setting was sealed is accepted once — and sealed, so
    /// tomorrow's run has nothing to trust.
    func testAPolicyChosenBeforeSealingIsAdoptedAndSealed() {
        store.set(KeepPolicy.byDate.rawValue, for: key)

        XCTAssertEqual(engine(SealKeyProbe(firstUse: true)).storedKeepPolicy(), .byDate)

        XCTAssertFalse(store.string(SettingGuard.macKey(for: key), default: "").isEmpty,
                       "adopting without sealing leaves the same question open tomorrow")
    }

    // MARK: - What is stored, when something else stored it

    /// The whole point: the value changed and the seal did not, because whoever
    /// wrote it does not have the key.
    func testAPolicySomethingElseWroteIsNotTheOneTheSearchUses() {
        let keys = SealKeyProbe(firstUse: false)
        seal(KeepPolicy.byPlace.rawValue, with: keys)
        store.set(KeepPolicy.byDate.rawValue, for: key)   // …and now it is forged

        // **The forged value is the one that is not the default**: planting
        // `byPlace` here would assert that the answer is `byPlace`, which a
        // reader that skipped the seal entirely also satisfies.
        XCTAssertEqual(engine(keys).storedKeepPolicy(), .standard)
    }

    /// A seal deleted along with nothing else is not evidence of an old install:
    /// whoever can write the policy can delete the MAC beside it.
    func testAMissingSealOnAnInstallationThatHasSealedBeforeIsTheDefault() {
        store.set(KeepPolicy.byDate.rawValue, for: key)

        XCTAssertEqual(engine(SealKeyProbe(firstUse: false)).storedKeepPolicy(), .standard)
    }

    /// A spelling this build does not know is the default too, and by the same
    /// route: the enum is what the raw value has to parse into.
    func testAPolicyThisBuildDoesNotKnowIsTheDefault() {
        let keys = SealKeyProbe(firstUse: false)
        seal("by-the-moon", with: keys)

        XCTAssertEqual(engine(keys).storedKeepPolicy(), .standard)
    }

    // MARK: - And a broken seal does not stop the scan

    /// The direction of the refusal, asserted where it can be seen: the folder is
    /// Helm's own, the policy is not, and the scan still happens.
    ///
    /// The fixture is in the home directory because `ScanRoot` refuses a root
    /// outside it — one in `/var/folders` would come back nil for that reason
    /// and prove nothing about this one.
    func testABrokenPolicySealStillScans() async throws {
        let fixture = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".helm-keep-policy-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture) }
        let payload = Data(repeating: 0x42, count: 1_200_000)
        try payload.write(to: fixture.appendingPathComponent("one.bin"))
        try payload.write(to: fixture.appendingPathComponent("two.bin"))

        let keys = SealKeyProbe(firstUse: false)
        store.set(fixture.path, for: "folder")
        store.set(SettingGuard(keys: keys).seal(Data(fixture.path.utf8)) ?? "",
                  for: SettingGuard.macKey(for: "folder"))
        seal(KeepPolicy.byDate.rawValue, with: keys)
        store.set(KeepPolicy.byPlace.rawValue, for: key)   // forged

        let answer = await engine(keys).backgroundScan()
        let report = try XCTUnwrap(answer,
                                   "a tampered preference is not a reason to stop looking")
        XCTAssertEqual(report.count, 1, "one extra copy of one file")
    }
}

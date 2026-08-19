import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **The off-list is read from the thread that draws, so reading it must be
/// free.**
///
/// `AppSettings.disabledScans` verifies its seal on every read, and the key
/// behind that seal comes from the login keychain. On an ad-hoc build — every
/// build this app ships — the cdhash changes each time, no access list an
/// earlier build wrote still names this one, and the answer is a modal
/// authorization dialog rather than data. `AppSettings` is `@MainActor`, so
/// *every* reader of that getter is on the thread that draws.
///
/// Measured, on the owner's own Mac: `HelmApp_2026-08-19-235500_MacBook.hang`,
/// 19,09 s unresponsive on `0.11.0-dev.1`, the main thread inside this getter by
/// way of `NSApplication.didBecomeActive` while `warmKey()` sat in securityd.
///
/// So there is a second way to ask, and it answers «not yet» rather than
/// waiting: nil until the key is in hand. Nil is not «no scans are off» and not
/// «somebody rewrote your settings» — the page already draws it as «not read»,
/// which is the state it was given a `Set<String>?` for.
@MainActor
final class TheSettingsPageNeverWaitsForTheKeychainTests: XCTestCase {

    private let key = "disabledScans"
    private var macKey: String { SettingGuard.macKey(for: key) }
    private var savedValue: Any?
    private var savedMac: String?
    private var savedGuard: SettingGuard!

    override func setUp() async throws {
        savedValue = AppSettings.store.object(key)
        savedMac = AppSettings.store.object(macKey) as? String
        savedGuard = AppSettings.scanGuard
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedValue, for: key)
        AppSettings.store.set(savedMac, for: macKey)
        AppSettings.scanGuard = savedGuard
    }

    // MARK: - Cold

    func testTheOffListIsNotReadWhileTheKeyIsStillCold() {
        let source = SealKeyProbe()
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(source))
        AppSettings.store.set(["disk"], for: key)

        XCTAssertNil(AppSettings.disabledScansIfWarm,
                     "an answer was given that only a keychain round trip could support")
        XCTAssertEqual(source.reads, 0, """
            reading the off-list went to the keychain, which on an ad-hoc build is a modal \
            dialog — and this getter is read on the thread that draws
            """)
    }

    /// The fresh-install branch too: nothing stored is where the getter used to
    /// *create* the keychain item, which is the most expensive round trip of
    /// them all and the one a first launch pays.
    func testNothingStoredIsAlsoNotAnsweredWhileTheKeyIsCold() {
        let source = SealKeyProbe()
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(source))
        AppSettings.store.set(nil, for: key)

        XCTAssertNil(AppSettings.disabledScansIfWarm)
        XCTAssertEqual(source.reads, 0, "the fresh-install branch established the key inline")
    }

    // MARK: - Warm

    func testTheOffListIsAnsweredOnceTheKeyIsInHand() async {
        let source = SealKeyProbe()
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(source))
        await AppSettings.scanGuard.warmKey()
        AppSettings.disabledScans = ["disk", "duplicates"]

        XCTAssertEqual(AppSettings.disabledScansIfWarm, ["disk", "duplicates"])
        XCTAssertEqual(source.reads, 1, "the warm ask went back to the keychain")
    }

    func testNothingStoredAnswersTheDefaultOnceTheKeyIsInHand() async {
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(SealKeyProbe()))
        await AppSettings.scanGuard.warmKey()
        AppSettings.store.set(nil, for: key)

        XCTAssertEqual(AppSettings.disabledScansIfWarm, AppSettings.defaultDisabledScans)
    }

    /// «Not yet» and «forged» stay apart. A list something else wrote is still
    /// every scan off, warm — the refusal this seal exists for is not softened
    /// by the read being cheap.
    func testAListSomethingElseWroteIsStillEveryScanOff() async {
        AppSettings.scanGuard = SettingGuard(keys: SealKeyCache(SealKeyProbe()))
        await AppSettings.scanGuard.warmKey()
        AppSettings.disabledScans = ["disk"]
        AppSettings.store.set([String](), for: key)          // "scan everything", unsigned

        XCTAssertEqual(AppSettings.disabledScansIfWarm, Set(ScanRunner.scannableModules))
    }

    // MARK: - The page reads the cheap one

    /// **Read from the source, because the type system cannot say this.** Both
    /// getters return a set of module ids and both compile anywhere; what
    /// separates them is that one can take 19 seconds. `AppSettings` is
    /// `@MainActor`, so there is no reader of it that is not on the thread that
    /// draws — the settings page and the scan coordinator alike.
    ///
    /// Two spellings are allowed and neither is a blocking read: `AppSettings`
    /// itself, which is where both getters live, and a **write**, whose key is
    /// warm by construction — nothing writes this list without having read it,
    /// and there is no row to press until it has been read.
    func testNothingInTheAppReadsTheBlockingOffList() throws {
        var offences: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources/HelmApp")
        where !path.hasSuffix("/AppSettings.swift") {
            for (index, line) in try RepoSource.lines(of: path).enumerated() {
                let code = RepoSource.code(line)
                guard code.contains("AppSettings.disabledScans"),
                      !code.contains("AppSettings.disabledScansIfWarm"),
                      !code.contains("AppSettings.disabledScans =") else { continue }
                offences.append("\(path):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offences, [], """
            the off-list is read through the getter that can go to the keychain, on the thread \
            that draws — `disabledScansIfWarm` is the one that answers «not yet» instead of \
            standing behind a modal authorization dialog
            """)
    }

    /// And the guard above can only fail if the spelling it hunts for is really
    /// there to be found — a scan whose subject has been renamed passes for ever.
    func testTheAppDoesReadTheOffList() throws {
        var readers: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources/HelmApp")
        where !path.hasSuffix("/AppSettings.swift") {
            if try RepoSource.text(of: path).contains("AppSettings.disabledScans") {
                readers.append(path)
            }
        }
        XCTAssertFalse(readers.isEmpty,
                       "the scan above is looking for a spelling no file in the app still has")
    }
}

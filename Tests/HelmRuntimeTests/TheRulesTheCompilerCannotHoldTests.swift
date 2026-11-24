import Foundation
import HelmTestSupport
import XCTest

/// The house rules the compiler cannot hold: each is a spelling that must or
/// must not appear in the source, so each is read off the source, one test a
/// rule, and each carries the control that proves its scan reads something.
///
/// Every rule is named by the `CLAUDE.local.md` rule it keeps or by the defect
/// class it guards, on its own test.
final class TheRulesTheCompilerCannotHoldTests: XCTestCase {

    // MARK: - Reading

    private struct Hit: Equatable {
        let path: String
        let line: Int
        let text: String
    }

    /// Every line of code under a directory that contains `needle`. Comments
    /// are blanked; string literals are blanked too unless `keepingStrings`.
    private func hits(_ needle: String, under directory: String,
                      keepingStrings: Bool = false) throws -> [Hit] {
        let reads = keepingStrings
            ? try SwiftSource.uncommented(under: directory)
            : try SwiftSource.code(under: directory)
        XCTAssertFalse(reads.isEmpty, "the scan read no file under \(directory)")
        var out: [Hit] = []
        for read in reads {
            for (index, line) in read.text.components(separatedBy: "\n").enumerated()
            where line.contains(needle) {
                out.append(Hit(path: read.path, line: index + 1,
                               text: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    private func files(_ hits: [Hit]) -> [String] { Array(Set(hits.map(\.path))).sorted() }

    // MARK: - 1. Launch through HelmProcess

    /// CLAUDE.local.md: launch through `HelmLaunch`, catch what it raises.
    /// `NSTask` raises an Objective-C exception on some launch paths and a
    /// Swift `catch` cannot see it, so a bare `try process.run()` aborts the app.
    func testNothingInTheShellStartsAChildWithoutTheGuard() throws {
        var offences: [String] = []
        let paths = try RepoSource.swiftFiles(under: "Sources/HelmApp")
        XCTAssertGreaterThanOrEqual(paths.count, 40,
                                    "the scan read \(paths.count) files under Sources/HelmApp where the tree holds 40 or more")
        for path in paths {
            for (index, line) in try RepoSource.lines(of: path).enumerated() {
                let code = RepoSource.code(line)
                guard code.contains("try "), code.contains(".run()") else { continue }
                offences.append("\(path):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offences, [], "a child is started here without the guard; `HelmProcess.start(_:path:)` is the door that answers")

        let runtime = try RepoSource.text(of: "Sources/HelmRuntime/HelmProcess.swift")
        XCTAssertTrue(runtime.contains(".run()") || runtime.contains("HelmLaunchTask"),
                      "`HelmProcess` no longer starts a child by either spelling this scan knows")
    }

    // MARK: - 2. A module's id is never a literal inside it

    /// CLAUDE.local.md: module id from the engine, not a literal. The id names
    /// a store and a folder on disk, and a second spelling is compared with nothing.
    func testNoModuleSpellsItsOwnIdAsALiteral() throws {
        var offenders: [String] = []
        var callSites = 0
        for root in ["Sources/Modules", "Sources/Tweaks"] {
            let reads = try SwiftSource.uncommented(under: root)
            XCTAssertFalse(reads.isEmpty, "no file under \(root) was read")
            if root == "Sources/Modules" {
                XCTAssertGreaterThan(reads.count, 50, "only \(reads.count) files under \(root) were read")
            }
            for read in reads {
                for (index, text) in read.text.components(separatedBy: "\n").enumerated() {
                    for marker in ["module: ", "namespace: "] {
                        guard let start = text.range(of: marker) else { continue }
                        callSites += 1
                        guard text[start.upperBound...].hasPrefix("\"") else { continue }
                        offenders.append("\(read.path):\(index + 1) — \(text.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertGreaterThan(callSites, 0, "no `module:` or `namespace:` argument was found at all")
        XCTAssertEqual(offenders, [], "a module spells its own id as a literal; read `<Engine>.moduleID` instead")
    }

    // MARK: - 3. A private file is written by PrivateFile

    /// CLAUDE.local.md: files naming somebody's files via `PrivateFile`, not
    /// atomic write plus mode change.
    func testNothingWritesAtomicallyAndPrivateFileStillWrites() throws {
        let reads = try SwiftSource.uncommented(under: "Sources")
        XCTAssertGreaterThanOrEqual(reads.count, 600,
                                    "the scan read \(reads.count) files under Sources where the tree holds 600 or more")
        XCTAssertEqual(try hits(".atomic", under: "Sources", keepingStrings: true).map { "\($0.path):\($0.line)" }, [],
                       "an atomic write leaves the umask's mode on the new inode until something chmods it")
        let place = "Sources/HelmRuntime/PrivateFile.swift"
        XCTAssertTrue(try RepoSource.text(of: place).contains("static func write(_ data: Data, to url: URL)"),
                      "\(place) no longer writes bytes, so the scan above guards an empty rule")
    }

    // MARK: - 4. Helm reads macOS's preference domains and never writes them

    /// Defect class: a write to `com.apple.screencapture` or
    /// `com.apple.symbolichotkeys` silently changes what every program on the Mac does.
    func testScreenshotsWritesNoPreferenceDomain() throws {
        let writers = [
            "CFPreferencesSetValue", "CFPreferencesSetAppValue", "CFPreferencesSetMultiple",
            "setPersistentDomain", "removePersistentDomain", "UserDefaults(suiteName",
            "addSuite", "removeSuite",
        ]
        let reads = try SwiftSource.code(under: "Sources/Modules/Screenshots")
        XCTAssertGreaterThan(reads.count, 10, "the scan found \(reads.count) files, it is not reading the module")
        var offenders: [String] = []
        for read in reads {
            for writer in writers where read.text.contains(writer) { offenders.append("\(read.path): \(writer)") }
        }
        XCTAssertEqual(offenders, [], "the module writes a preference domain")

        let copies = reads.reduce(0) { $0 + $1.text.components(separatedBy: "CFPreferencesCopyAppValue").count - 1 }
        XCTAssertEqual(copies, 3, "the location, the symbolic hotkeys and the interface-sounds switch are the three reads")

        let planted = SwiftSource.code("func f() { CFPreferencesSetAppValue(key, value, domain) }")
        XCTAssertTrue(writers.contains { planted.contains($0) }, "a planted writer was not seen")
    }

    // MARK: - 5. A password dialog is PrivilegedRun's

    /// Defect class: a bare `osascript` sends `(-128)`, the only sign of a
    /// cancelled dialog, to a stderr nobody reads, so a cancel reads as a failure.
    /// String literals count: the old spelling was one.
    func testOsascriptIsSpelledOnlyInPrivilegedRun() throws {
        let found = files(try hits("osascript", under: "Sources", keepingStrings: true))
        XCTAssertEqual(found, ["Sources/HelmRuntime/PrivilegedRun.swift"],
                       "`osascript` is spelled outside PrivilegedRun, which owns `-s o` and the reading of `(-128)`")
    }

    // MARK: - 6. A removal goes through HelmTrash

    /// CLAUDE.local.md: remove via `HelmTrash.swift`. The two ports below call
    /// `FileManager.trashItem(at:` directly today; they are the named exceptions.
    func testFileManagerTrashItemIsCalledOnlyWhereItIsNamed() throws {
        let expected = [
            "Sources/HelmRuntime/HelmTrash.swift",
            "Sources/Modules/Screenshots/Engine/SystemPorts.swift",
            "Sources/Modules/Uninstaller/Engine/SystemPorts.swift",
        ]
        XCTAssertEqual(files(try hits("trashItem(at:", under: "Sources")), expected,
                       "`FileManager.trashItem(at:` is called outside HelmTrash and the two named direct callers")
    }

    // MARK: - 7. Layout posts only marked events

    /// Defect class: the engine reading its own output back as typing. An event
    /// from an unmarked `CGEventSource` reaches the tap as the person's keystroke.
    func testLayoutBuildsOneEventSourceAndItIsTheMarkedOne() throws {
        let all = try hits("CGEventSource(", under: "Sources/Modules/Layout")
        XCTAssertEqual(all.count, 1, "found: \(all)")
        let path = try XCTUnwrap(all.first).path
        let helper = SwiftSource.bodiesNamed("helmEventSource", in: SwiftSource.code(try RepoSource.text(of: path)))
        XCTAssertEqual(helper.count, 1, "\(path) no longer holds exactly one helmEventSource()")
        XCTAssertEqual(try XCTUnwrap(helper.first).components(separatedBy: "CGEventSource(").count - 1, 1,
                       "the one `CGEventSource(` is not inside helmEventSource()")
    }

    // MARK: - 8. Deployed keychain items

    /// CLAUDE.local.md: never re-key a deployed keychain item. Each name is
    /// stored data on every Mac that ran the build; a second spelling is a
    /// second item or a new one that reads every saved setting as tampered with.
    func testEachDeployedKeychainNameIsSpelledInOneFileAndNothingElseDeletesOrBuildsAKey() throws {
        let sealKey = "Sources/HelmRuntime/SettingsSealKey.swift"
        let ruleKey = "Sources/Modules/Autopilot/Engine/RuleKeychain.swift"
        for (literal, file) in [(#""settings-seal""#, sealKey), (#""dev-settings-seal""#, sealKey),
                                (#""com.helm.autopilot""#, ruleKey), (#""rule-seal""#, ruleKey),
                                (#""rule-seq""#, ruleKey)] {
            XCTAssertEqual(files(try hits(literal, under: "Sources", keepingStrings: true)), [file],
                           "\(literal) is not spelled in exactly \(file)")
        }
        XCTAssertEqual(files(try hits("KeychainSealKey(", under: "Sources")), [ruleKey, sealKey].sorted(),
                       "a keychain seal key is built outside the two places that own an item")
        XCTAssertEqual(files(try hits("SecItemDelete", under: "Sources")),
                       ["Sources/Modules/VPN/Engine/SystemPorts.swift"],
                       "a keychain item is deleted outside the VPN purge")
    }

    // MARK: - 9. A suite does not land in the person's folders

    /// Defect class: a store that never asks `TestProcess` reads, and could
    /// delete, the person's own files in a suite run.
    func testEveryFileThatResolvesOneOfTheirFoldersAsksTestProcess() throws {
        let theirFolders = [".applicationSupportDirectory", ".cachesDirectory",
                            ".documentDirectory", ".libraryDirectory", ".downloadsDirectory"]
        // Resolves the folders only to compare a path as a string, and writes nothing.
        let answeredNotAsked = "Sources/Modules/Duplicates/Engine/Logic/KeepPolicy.swift"
        func folders(in line: String) -> [String] {
            let code = RepoSource.code(line)
            return theirFolders.filter { code.contains($0) }
        }

        var sites: [(file: String, line: Int, folder: String)] = []
        for file in try RepoSource.swiftFiles(under: "Sources") {
            for (index, raw) in try RepoSource.lines(of: file).enumerated() {
                for folder in folders(in: raw) { sites.append((file, index + 1, folder)) }
            }
        }
        XCTAssertGreaterThanOrEqual(sites.count, 2, "the scan is not reading anything")
        XCTAssertTrue(sites.contains { $0.file.hasSuffix("HelmSupport.swift") },
                      "HelmSupport resolves Application Support and the scan did not find it")

        let unguarded = try sites.filter { site in
            if site.file == answeredNotAsked { return false }
            return try !RepoSource.lines(of: site.file).contains { RepoSource.code($0).contains("TestProcess") }
        }
        XCTAssertEqual(unguarded.map { "\($0.file):\($0.line) \($0.folder)" }, [],
                       "these resolve a folder of the person's without asking TestProcess")

        for file in ["Sources/HelmRuntime/HelmSupport.swift", "Sources/HelmRuntime/ScanJournal.swift"] {
            let asks = try RepoSource.lines(of: file).contains { RepoSource.code($0).contains("TestProcess.isRunning") }
            XCTAssertTrue(asks, "\(file) no longer asks TestProcess.isRunning in code")
        }

        XCTAssertEqual(folders(in: "  let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)"), [".cachesDirectory"])
        XCTAssertEqual(folders(in: "    // never .cachesDirectory"), [], "an explanation was read as the offence it explains")
        XCTAssertEqual(folders(in: "    let url = home  // not .documentDirectory"), [], "a comment tail was read as code")
    }

    // MARK: - 10. VPN claims no protection it does not have

    /// Defect class: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` does nothing
    /// to an item in the file-based login keychain, so the attribute may only
    /// appear where the data-protection keychain is asked for in write, read and delete.
    func testTheVPNAccessibilityClaimIsEitherInForceOrAbsent() throws {
        let lines = try RepoSource.lines(of: "Sources/Modules/VPN/Engine/SystemPorts.swift").map(RepoSource.code)
        XCTAssertTrue(lines.contains { $0.contains("SecItemAdd") },
                      "this is no longer the file that writes the cached secret")
        let claims = lines.filter { $0.contains("kSecAttrAccessible") }
        guard !claims.isEmpty else { return }
        let protection = lines.filter { $0.contains("kSecUseDataProtectionKeychain") }
        XCTAssertGreaterThanOrEqual(protection.count, 3,
                                    "the accessibility attribute is claimed in \(claims.count) place(s) while the "
                                    + "data-protection keychain is asked for in \(protection.count); write, read and delete must agree")
    }

    // MARK: - 11. A removal is sent only where a second press is proved refused

    /// Defect class: a model that sends a removal and answers a second press by
    /// sending another reports the first as failed (`Architecture/Removal.md`
    /// § One removal at a time). A new sender needs its own second-press test, so
    /// the senders are exactly the six named here, each with the class that holds it.
    func testEveryFileThatSendsARemovalNamesTheTestThatRefusesItsSecondPress() throws {
        let proof = [
            "Sources/Modules/Disk/UI/DiskViewModel+Basket.swift": "TheBasketHoldsStillUnderARemovalTests",
            "Sources/Modules/Duplicates/UI/DuplicatesViewModel.swift": "AKeepPressedDuringARemovalIsNotALieTests",
            "Sources/Modules/Leftovers/UI/LeftoversViewModel.swift": "OneRemovalAtATimeTests",
            "Sources/Modules/Uninstaller/UI/OrphansModel.swift": "TheOrphansTabRefusesASecondPressTests",
            "Sources/Modules/Uninstaller/UI/TrashedLeftoversView.swift": "TheTrashOfferSendsOneBatchTests",
            "Sources/Modules/Uninstaller/UI/UninstallerViewModel.swift": "TheDoorTakesOneRemovalAtATimeTests",
        ]
        var senders = Set<String>()
        for needle in ["work.trash(", "work.trashPaths(", "uvm.trashPaths(", "work.removeApp("] {
            for root in ["Sources/Modules", "Sources/Tweaks"] {
                senders.formUnion(try hits(needle, under: root).map(\.path))
            }
        }
        XCTAssertEqual(senders.sorted(), proof.keys.sorted(),
                       "a new removal sender needs its own second-press test: add it to this table and to "
                       + "Architecture/Removal.md § One removal at a time")
        for (file, name) in proof {
            XCTAssertFalse(try hits("class \(name)", under: "Tests").isEmpty,
                           "\(file) is held by \(name), which is no longer a test class")
        }
    }
}

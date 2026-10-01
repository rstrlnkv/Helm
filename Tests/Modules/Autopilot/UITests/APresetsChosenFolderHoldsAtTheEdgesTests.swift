import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import Vision
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The engine's rule-number store, in memory. The twin of the engine target's
/// `TestRuleSequence`, private for the reason `ThePageNeverWaitsForTheKeychainTests`
/// gives for its own: a module's port cannot have a stand-in in `HelmTestSupport`.
private final class EdgeRuleSequence: RuleSequencePort, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64?

    func highWater() -> RuleSequence {
        lock.withLock { value.map(RuleSequence.at) ?? .absent }
    }

    @discardableResult
    func raise(to seq: UInt64) -> Bool {
        lock.withLock { value = seq; return true }
    }
}

/// **A preset's chooser, fed the inputs nobody chose on purpose — on disk.**
///
/// `APresetsFolderCanBeChosenTests` holds the chooser's decisions against
/// `/Users/x`, a home that does not exist. `WatchScope` canonicalizes through
/// the filesystem, and CLAUDE.md's order is that such a gate is tested with
/// paths that exist, because a path that does not is the one input the
/// filesystem treats differently. So everything here stands on a real scratch
/// home: real folders, a real link into its `Library`, the `/private` spelling
/// the temporary directory also answers to, and — for the deleting and moving
/// presets — a real engine behind a real transport, trashing for real.
@MainActor
final class APresetsChosenFolderHoldsAtTheEdgesTests: XCTestCase {

    private var home: URL!
    private var messages: URL!
    private var transport: LocalTransport!
    private var helm: AutopilotEngine!

    /// Called first by every test rather than from `setUp`, which XCTest does
    /// not run on the main actor this class is isolated to.
    private func standTheHome() throws {
        home = scratchDirectory("chosen-folder-edges")
        let fm = FileManager.default
        messages = home.appendingPathComponent("Library/Messages")
        for sub in ["Downloads", "Desktop", "Pictures", "Library/Messages", "Library/LaunchAgents"] {
            try fm.createDirectory(at: home.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        // Two links a panel can be walked through: one into the Library, one
        // that is only another name for a folder the page may already watch.
        try fm.createSymbolicLink(at: home.appendingPathComponent("Chats"),
                                  withDestinationURL: messages)
        try fm.createSymbolicLink(at: home.appendingPathComponent("DL"),
                                  withDestinationURL: home.appendingPathComponent("Downloads"))
    }

    /// The other spelling of a path under the temporary directory. Nil when the
    /// scratch home has only one, which would make a test about spellings vacuous.
    private func privateSpelling(_ path: String) -> String? {
        path.hasPrefix("/var/") || path.hasPrefix("/tmp/") ? "/private" + path : nil
    }

    /// The boot volume's own entry under `/Volumes` — a link to `/` — or nil on
    /// a Mac that has none. Found rather than named: the volume is called
    /// whatever its owner called it.
    private func bootVolume() -> String? {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? []
        return names.map { "/Volumes/" + $0 }
            .first { (try? fm.destinationOfSymbolicLink(atPath: $0)) == "/" }
    }

    private func fakeModel(_ wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
                           presetFolders: FakePresetFolders(home: home.path), home: home.path)
    }

    private func engineModel() -> AutopilotViewModel {
        transport = LocalTransport()
        helm = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            transport: transport, home: home.path,
            keys: SealKeyProbe(), sequence: EdgeRuleSequence())
        return AutopilotViewModel(vm: ModuleViewModel(transport: transport),
                                  presetFolders: FakePresetFolders(home: home.path),
                                  home: home.path)
    }

    private func offer(_ model: AutopilotViewModel, _ kind: PresetKind) throws -> OfferedPreset {
        try XCTUnwrap(model.presets.first { $0.preset.kind == kind }, "no \(kind) offered")
    }

    private func put(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    // MARK: - Refused, on disk, in every spelling

    /// Every place a rule may not watch, spelled every way a panel or a link can
    /// spell it, is refused before the editor believes it — and the control
    /// first, in both spellings, so a gate that refused everything, or refused
    /// the `/private` spelling of a folder it allows, cannot pass for the wrong
    /// reason.
    func testEveryRefusedPlaceIsRefusedOnDiskHoweverItIsSpelled() async throws {
        try standTheHome()
        let wire = AutopilotWire()
        let model = fakeModel(wire)
        await model.load()
        let offer = try offer(model, .screenshots)
        let h = home.path
        let spelt = try XCTUnwrap(privateSpelling(h), "precondition: the scratch home has a second spelling")

        for allowed in [h + "/Pictures", spelt + "/Pictures"] {
            XCTAssertNotNil(RuleEditor.pointing(offer.draft, at: allowed, from: offer.folder,
                                                preset: offer.preset, rvm: model),
                            "precondition: \(allowed) is a folder a rule may watch")
        }

        let refused = [
            h + "/Library/Messages", h + "/Library/LaunchAgents", h + "/Library",
            h + "/library/messages",                  // the case the volume ignores
            h + "/Pictures/../Library/Messages",      // a dotted route into it
            h + "/Chats",                             // a link into it
            spelt + "/Library/Messages", spelt + "/Chats",
            h, h + "/", spelt, "/", "", "Library/Messages",
            "/Volumes", "/Volumes/",
        ] + (bootVolume().map { [$0 + h + "/Library/Messages", $0 + h + "/Chats", $0] } ?? [])
        for path in refused {
            XCTAssertNil(RuleEditor.pointing(offer.draft, at: path, from: offer.folder,
                                             preset: offer.preset, rvm: model),
                         "\(path) was taken as the preset's folder")
        }
        XCTAssertFalse(wire.commands.contains(.previewDraft), "a refused folder was read by a dry run")
        XCTAssertEqual(wire.saved, [], "a refused choice wrote a folder list")
    }

    // MARK: - One folder, two spellings

    /// **A folder the page already watches is the same folder under any spelling
    /// the gate accepts for it.** The gate canonicalizes, so `/private/var/…`
    /// and a link to `~/Downloads` both pass it as the watched folder; the
    /// identity has to agree, or the chooser hands back a second `WatchedFolder`
    /// for one directory — stored twice, swept at once, and promised in the
    /// sheet's sentence as a folder Helm is about to start watching.
    func testAWatchedFolderIsTheWatchedOneUnderEverySpellingTheGateAccepts() async throws {
        try standTheHome()
        let downloads = home.path + "/Downloads"
        // `/private/var/…`, a link inside the home, and the boot volume's
        // entry under `/Volumes`, which is a link to `/`.
        let spellings = [try XCTUnwrap(privateSpelling(downloads)), home.path + "/DL"]
            + (bootVolume().map { [$0 + downloads] } ?? [])
        for spelling in spellings {
            let watched = WatchedFolder(id: "dl", path: downloads)
            let wire = AutopilotWire(folders: [watched],
                                     report: SweepReport(folderID: "x", examined: 0, acted: 0,
                                                         refused: 0, failed: 0))
            let model = fakeModel(wire)
            await model.load()
            let offer = try offer(model, .screenshots)

            let next = try XCTUnwrap(RuleEditor.pointing(offer.draft, at: spelling, from: offer.folder,
                                                         preset: offer.preset, rvm: model),
                                     "precondition: the gate lets \(spelling) through")
            XCTAssertEqual(next.folder.id, "dl",
                           "\(spelling) is ~/Downloads, and a second WatchedFolder was made for it")
            XCTAssertFalse(model.sweepsAfterSaving(next.rule, in: next.folder),
                           "the sheet promises to start watching \(spelling), which is watched already")

            await model.save(next.rule, in: next.folder)

            XCTAssertEqual(wire.saved.last?.count, 1,
                           "one directory stored as \(wire.saved.last?.count ?? 0) watched folders via \(spelling)")
            XCTAssertFalse(wire.commands.contains(.runNow),
                           "a folder already watched was swept on a preset's behalf via \(spelling)")
        }
    }

    /// **The panel's «Add folder…» holds the same identity.** A folder already
    /// watched, chosen again under another spelling the gate accepts, is not a
    /// second folder: nothing is stored. The control first — a different folder
    /// is stored — so a refusal of everything cannot pass for this.
    func testAddingAWatchedFolderUnderAnotherSpellingStoresNothing() async throws {
        try standTheHome()
        let downloads = home.path + "/Downloads"
        let spellings = [try XCTUnwrap(privateSpelling(downloads)), home.path + "/DL", downloads + "/"]
            + (bootVolume().map { [$0 + downloads] } ?? [])
        for spelling in spellings {
            let wire = AutopilotWire(folders: [WatchedFolder(id: "dl", path: downloads)])
            let model = fakeModel(wire)
            await model.load()

            model.addFolder(at: home.path + "/Pictures")
            XCTAssertEqual(model.folders.count, 2, "the control: a different folder was not added")
            model.addFolder(at: spelling)

            XCTAssertEqual(model.folders.map(\.id).filter { $0 == "dl" }.count, 1, spelling)
            XCTAssertEqual(model.folders.count, 2,
                           "\(spelling) is ~/Downloads, which is watched, and it was added again")
        }
    }

    /// **The sentence and the sweep read one expression, refusal included.** A
    /// rule set refused while the sheet is open makes Done do nothing, so the
    /// sheet may not promise «straight away» over it.
    func testARefusalWhileTheSheetIsOpenTakesTheSweepAndTheSentenceAway() async throws {
        try standTheHome()
        let wire = AutopilotWire()
        let model = fakeModel(wire)
        await model.load()
        let offer = try offer(model, .screenshots)
        XCTAssertTrue(model.sweepsAfterSaving(offer.draft, in: offer.folder), "precondition")

        wire.answers(AutopilotStatus(refusal: .tampered))
        await model.load()
        XCTAssertEqual(model.screen, .rulesRefused(.tampered), "precondition: the set is refused")

        XCTAssertFalse(model.sweepsAfterSaving(offer.draft, in: offer.folder),
                       "Done does nothing over a refused set, and the sheet still says it sweeps")
        await AppLanguage.only(.en) {
            let read = readSheet(RuleEditor(rvm: model, folder: offer.folder, rule: offer.draft,
                                            preset: offer.preset))
            XCTAssertTrue(read.contains { $0.contains("What would happen") },
                          "the subject: the sheet did not draw: \(read)")
            XCTAssertFalse(read.contains { $0.contains("straight away") }, "\(read)")
        }
        await model.save(offer.draft, in: offer.folder)
        XCTAssertEqual(wire.saved, [], "a refused set was written over")
        XCTAssertFalse(wire.commands.contains(.runNow), "a refused set was swept")
    }

    /// **A spelling that differs only in case is the watched folder too.** The
    /// volume ignores case, and `WatchScope` canonicalizes every component that
    /// exists — the leaf included — so `~/downloads` passes it as `~/Downloads`.
    /// The identity has to agree for the chooser and for «Add folder…» alike,
    /// or the one directory is stored twice and the second copy is swept at once.
    /// Checked on disk first: on a case-sensitive volume the lower-case spelling
    /// names nothing, and the test says so rather than passing.
    func testASpellingThatDiffersOnlyInCaseIsTheWatchedFolder() async throws {
        try standTheHome()
        let downloads = home.path + "/Downloads"
        let spellings = [home.path + "/downloads", home.path + "/DOWNLOADS"]
        for spelling in spellings {
            XCTAssertTrue(FileManager.default.fileExists(atPath: spelling),
                          "precondition: the scratch volume ignores case, so \(spelling) exists")
            XCTAssertTrue(WatchScope.allows(spelling, home: home.path),
                          "precondition: the gate lets \(spelling) through")

            let wire = AutopilotWire(folders: [WatchedFolder(id: "dl", path: downloads)],
                                     report: SweepReport(folderID: "x", examined: 0, acted: 0,
                                                         refused: 0, failed: 0))
            let model = fakeModel(wire)
            await model.load()
            let offer = try offer(model, .screenshots)
            let next = try XCTUnwrap(RuleEditor.pointing(offer.draft, at: spelling, from: offer.folder,
                                                         preset: offer.preset, rvm: model))
            XCTAssertEqual(next.folder.id, "dl",
                           "\(spelling) is ~/Downloads, and a second WatchedFolder was made for it")
            XCTAssertFalse(model.sweepsAfterSaving(next.rule, in: next.folder),
                           "the sheet promises to start watching \(spelling), which is watched already")
            await model.save(next.rule, in: next.folder)
            XCTAssertEqual(wire.saved.last?.count, 1,
                           "one directory stored as \(wire.saved.last?.count ?? 0) watched folders via \(spelling)")
            XCTAssertFalse(wire.commands.contains(.runNow),
                           "a folder already watched was swept on a preset's behalf via \(spelling)")

            let panelWire = AutopilotWire(folders: [WatchedFolder(id: "dl", path: downloads)])
            let panelModel = fakeModel(panelWire)
            await panelModel.load()
            panelModel.addFolder(at: home.path + "/Pictures")
            XCTAssertEqual(panelModel.folders.count, 2, "the control: a different folder was not added")
            panelModel.addFolder(at: spelling)
            XCTAssertEqual(panelModel.folders.count, 2,
                           "\(spelling) is ~/Downloads, which is watched, and «Add folder…» added it again")
        }
    }

    /// **Both sides of the comparison are resolved, not only the chosen one.**
    /// A folder stored under a roundabout spelling — through a link, or under
    /// `/private` — is the same directory as its plain name chosen later. A
    /// comparison that resolved only the incoming path passes every test whose
    /// stored path already happens to be the plain one.
    func testTheStoredSpellingIsResolvedAsWellAsTheChosenOne() async throws {
        try standTheHome()
        let downloads = home.path + "/Downloads"
        let stored = [home.path + "/DL", try XCTUnwrap(privateSpelling(downloads))]
        for storedPath in stored {
            let wire = AutopilotWire(folders: [WatchedFolder(id: "dl", path: storedPath)],
                                     report: SweepReport(folderID: "x", examined: 0, acted: 0,
                                                         refused: 0, failed: 0))
            let model = fakeModel(wire)
            await model.load()
            let offer = try offer(model, .screenshots)
            let next = try XCTUnwrap(RuleEditor.pointing(offer.draft, at: downloads, from: offer.folder,
                                                         preset: offer.preset, rvm: model))
            XCTAssertEqual(next.folder.id, "dl",
                           "stored as \(storedPath), chosen as \(downloads): one directory, two folders")

            let panelModel = fakeModel(AutopilotWire(folders: [WatchedFolder(id: "dl", path: storedPath)]))
            await panelModel.load()
            panelModel.addFolder(at: downloads)
            XCTAssertEqual(panelModel.folders.count, 1,
                           "stored as \(storedPath), added again as \(downloads)")
        }
    }

    /// **The sheet already on screen loses its promise when the refusal arrives.**
    /// `testARefusalWhileTheSheetIsOpenTakesTheSweepAndTheSentenceAway` draws a
    /// fresh sheet after the refusal; the person is looking at one drawn before
    /// it. The same mounted sheet is read before and after, and the «before»
    /// reading is the subject: the sentence was on screen.
    func testTheMountedSheetDropsTheSentenceWhenTheRefusalArrives() async throws {
        try standTheHome()
        let wire = AutopilotWire()
        let model = fakeModel(wire)
        await model.load()
        let offer = try offer(model, .screenshots)

        await AppLanguage.only(.en) {
            let render = MountedRender(
                RuleEditor(rvm: model, folder: offer.folder, rule: offer.draft, preset: offer.preset)
                    .transaction { $0.disablesAnimations = true },
                width: 640, height: 620, appearance: .aqua)
            var before: [String] = []
            for _ in 0..<40 {
                render.settle(10)
                before = recognised(render.host)
                if before.contains(where: { $0.contains("straight away") }) { break }
            }
            XCTAssertTrue(before.contains { $0.contains("straight away") },
                          "the subject: the open sheet never promised a sweep: \(before)")

            wire.answers(AutopilotStatus(refusal: .tampered))
            await model.load()
            XCTAssertEqual(model.screen, .rulesRefused(.tampered), "precondition: the set is refused")

            var after: [String] = []
            for _ in 0..<40 {
                render.settle(10)
                after = recognised(render.host)
                if !after.contains(where: { $0.contains("straight away") }) { break }
            }
            XCTAssertTrue(after.contains { $0.contains("What would happen") },
                          "the subject: the sheet stopped drawing: \(after)")
            XCTAssertFalse(after.contains { $0.contains("straight away") },
                           "the sheet on screen still promises a sweep over a refused set: \(after)")
        }
    }

    // MARK: - Nothing leaves the scope through the chooser — real engine

    /// **The deleting preset, pointed through the chooser, trashes nothing the
    /// gate refuses.** A real engine, a real scratch home and the real Trash.
    ///
    /// The control is the subject: the same flow, pointed back at the preset's
    /// own folder, really does trash the installer there — so «the Library file
    /// is still there» is not the absence of a sweep. Then the watched folder is
    /// replaced by a link into `~/Library/Messages` after the save, which is the
    /// state no choice can refuse in advance; the engine's root gate
    /// (`AutopilotEngine.readGated`, with the reader's own check behind it) is
    /// what stands between that and the Trash, and the sweep must act on nothing.
    func testTheDeletingPresetTrashesNothingOutsideTheScope() async throws {
        try standTheHome()
        let model = engineModel()
        await model.load()
        let offer = try offer(model, .oldInstallers)
        let fm = FileManager.default

        let secretName = unownableLeaf("secret.dmg")
        let secret = try put(secretName, in: messages)
        reclaimFromTrash(secretName)
        let installerName = unownableLeaf("installer.dmg")
        let installer = try put(installerName, in: home.appendingPathComponent("Downloads"))
        reclaimFromTrash(installerName)

        // The person's edit: a file made a second ago is not thirty days old.
        var draft = offer.draft
        draft.conditions = [.fileExtension(["dmg"])]

        for path in [messages.path, home.path + "/Chats"] {
            XCTAssertNil(RuleEditor.pointing(draft, at: path, from: offer.folder,
                                             preset: offer.preset, rvm: model),
                         "\(path) was taken as the deleting preset's folder")
        }

        // The preset's own folder, chosen again.
        let next = try XCTUnwrap(RuleEditor.pointing(draft, at: home.path + "/Downloads",
                                                     from: offer.folder, preset: offer.preset, rvm: model))
        XCTAssertEqual(next.rule.conditions, draft.conditions, "the edited condition was lost")
        XCTAssertEqual(next.rule.action, .trash)
        XCTAssertTrue(model.sweepsAfterSaving(next.rule, in: next.folder))

        await model.save(next.rule, in: next.folder)

        XCTAssertFalse(fm.fileExists(atPath: installer.path),
                       "the subject: the deleting preset did not act in its own folder at all")
        XCTAssertTrue(fm.fileExists(atPath: secret.path), "a file in ~/Library/Messages was trashed")
        let stored = try XCTUnwrap(helm.folders.first, "precondition: the folder was stored")

        // The folder becomes a door into the Library after it was judged.
        try fm.moveItem(at: home.appendingPathComponent("Downloads"),
                        to: home.appendingPathComponent("Downloads-real"))
        try fm.createSymbolicLink(at: home.appendingPathComponent("Downloads"),
                                  withDestinationURL: messages)

        let swapped = helm.runNow(stored)

        // A root that now leads into `~/Library` is refused by the root gate
        // before the reader or the runner is asked, so nothing behind it is
        // examined or planned; the assertions below are on what the disk and
        // the report show, not on which gate answered.
        XCTAssertTrue(fm.fileExists(atPath: secret.path),
                      "a file in ~/Library/Messages was trashed through a watched folder turned link")
        XCTAssertEqual(swapped.acted, 0, "the sweep acted on something behind the link")

        // A file in the watched folder that is a link into the Library. The sweep
        // filters what the reader returns through the same gate the runner asks
        // (`AutopilotEngine.readGated`), so the link is dropped before it is a
        // plan: not offered, not counted, and the report below says so rather than
        // that the runner refused it.
        try fm.removeItem(at: home.appendingPathComponent("Downloads"))
        try fm.moveItem(at: home.appendingPathComponent("Downloads-real"),
                        to: home.appendingPathComponent("Downloads"))
        let doorName = unownableLeaf("door.dmg")
        let door = home.appendingPathComponent("Downloads/" + doorName)
        try fm.createSymbolicLink(at: door, withDestinationURL: secret)
        reclaimFromTrash(doorName)

        let gated = helm.runNow(stored)

        XCTAssertTrue(fm.fileExists(atPath: secret.path), "the file behind the link went")
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: door.path),
                        "a path leading into ~/Library/Messages was acted on")
        XCTAssertEqual(gated.folder, .read, "precondition: the folder was read")
        XCTAssertEqual(gated.acted, 0, "the sweep acted on a path leading into the Library")
        XCTAssertEqual(gated.examined, 0, "the link was offered to the rules, past the read-side gate")
    }

    /// **The moving preset: its destination goes with the chosen folder, and a
    /// destination turned into a link after the save takes nothing into the
    /// Library.** Real engine, real files.
    func testTheScreenshotsDestinationGoesWithTheFolderAndNotIntoTheLibrary() async throws {
        try standTheHome()
        let model = engineModel()
        await model.load()
        let offer = try offer(model, .screenshots)
        let fm = FileManager.default
        let pictures = home.appendingPathComponent("Pictures")

        let next = try XCTUnwrap(RuleEditor.pointing(offer.draft, at: pictures.path,
                                                     from: offer.folder, preset: offer.preset, rvm: model))
        XCTAssertEqual(next.rule.action, .move(to: pictures.path + "/Screenshots"))

        let first = try put(unownableLeaf("shot.png"), in: pictures)
        await model.save(next.rule, in: next.folder)

        XCTAssertTrue(fm.fileExists(atPath: pictures.path + "/Screenshots/" + first.lastPathComponent),
                      "the subject: the screenshot did not reach the chosen folder's Screenshots")
        XCTAssertFalse(fm.fileExists(atPath: home.path + "/Desktop/Screenshots"),
                       "the preset still moved into the Desktop it was pointed away from")

        // The destination swapped for a link into the Library after the save.
        try fm.moveItem(atPath: pictures.path + "/Screenshots", toPath: pictures.path + "/Screenshots-real")
        try fm.createSymbolicLink(atPath: pictures.path + "/Screenshots", withDestinationPath: messages.path)
        let second = try put(unownableLeaf("shot.png"), in: pictures)
        let stored = try XCTUnwrap(helm.folders.first)

        let report = helm.runNow(stored)

        XCTAssertTrue(fm.fileExists(atPath: second.path), "the file left for a destination behind a link")
        XCTAssertFalse(fm.fileExists(atPath: messages.path + "/" + second.lastPathComponent),
                       "a rule moved a file into ~/Library/Messages")
        XCTAssertGreaterThanOrEqual(report.refused, 1, "the move was never attempted, so no gate was met")
    }

    /// **Chosen, then swapped before Done.** The choice was judged on a real
    /// folder; by the time Done is pressed the path leads into the Library. The
    /// save is judged again, nothing is stored or swept, and the page says why.
    func testAFolderSwappedForALinkBeforeDoneIsNotStoredOrSwept() async throws {
        try standTheHome()
        let model = engineModel()
        await model.load()
        let offer = try offer(model, .oldInstallers)
        let fm = FileManager.default
        let secret = try put(unownableLeaf("secret.dmg"), in: messages)
        reclaimFromTrash(secret.lastPathComponent)
        var draft = offer.draft
        draft.conditions = [.fileExtension(["dmg"])]

        let next = try XCTUnwrap(RuleEditor.pointing(draft, at: home.path + "/Pictures",
                                                     from: offer.folder, preset: offer.preset, rvm: model),
                                 "precondition: Pictures is a folder a rule may watch")
        try fm.removeItem(at: home.appendingPathComponent("Pictures"))
        try fm.createSymbolicLink(at: home.appendingPathComponent("Pictures"), withDestinationURL: messages)

        await AppLanguage.only(.en) {
            await model.save(next.rule, in: next.folder)
            XCTAssertEqual(model.banner, ApStr.folderOutOfReach, "the refusal was not said")
        }

        XCTAssertTrue(fm.fileExists(atPath: secret.path), "a file in ~/Library/Messages was trashed")
        XCTAssertEqual(helm.folders, [], "a folder that now leads into the Library was stored")
    }

    // MARK: - The sheet, drawn

    /// **The sentence is drawn exactly when Done sweeps**, read back off the
    /// rendered sheet rather than off the model: the model's half is held by
    /// `APresetsFolderCanBeChosenTests`, and only a rendering sees whether the
    /// sheet asks it. The chooser is drawn for a preset and not for a rule
    /// somebody wrote. English, Aqua.
    func testTheSheetDrawsTheSentenceExactlyWhenDoneSweeps() async throws {
        try standTheHome()
        let watched = WatchedFolder(id: "pics", path: home.path + "/Pictures")
        let model = fakeModel(AutopilotWire(folders: [watched]))
        await model.load()
        let offer = try offer(model, .oldInstallers)

        await AppLanguage.only(.en) {
            var off = offer.draft
            off.enabled = false
            let cases: [(String, WatchedFolder, Rule, RulePreset?, Bool)] = [
                ("new folder, rule on", offer.folder, offer.draft, offer.preset, true),
                ("new folder, rule off", offer.folder, off, offer.preset, false),
                ("watched folder", watched, offer.draft, offer.preset, false),
                ("a rule of one's own", watched, Rule(id: "own", name: "Own", action: .trash), nil, false),
            ]
            for (label, folder, rule, preset, sentence) in cases {
                XCTAssertEqual(model.sweepsAfterSaving(rule, in: folder), sentence,
                               "precondition: \(label)")
                let read = readSheet(RuleEditor(rvm: model, folder: folder, rule: rule, preset: preset))
                XCTAssertTrue(read.contains { $0.contains("What would happen") },
                              "the subject: the sheet did not draw at all (\(label)): \(read)")
                XCTAssertEqual(read.contains { $0.contains("straight away") }, sentence,
                               "\(label): sentence drawn \(!sentence), Done sweeps \(sentence): \(read)")
                XCTAssertEqual(read.contains { $0.hasPrefix("Choose") }, preset != nil,
                               "\(label): the chooser: \(read)")
            }
        }
    }

    private func readSheet<V: View>(_ sheet: V) -> [String] {
        let render = MountedRender(sheet.transaction { $0.disablesAnimations = true },
                                   width: 640, height: 620, appearance: .aqua)
        // Pumped until the dry run's own heading is read — the sheet's last
        // section to settle — and bounded, so a sheet that never draws fails on
        // the subject assertion rather than hanging.
        var read: [String] = []
        for _ in 0..<40 {
            render.settle(10)
            read = recognised(render.host)
            if read.contains(where: { $0.contains("What would happen") }) { break }
        }
        return read
    }

    private func recognised(_ host: NSView) -> [String] {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let drawn = rep.cgImage else { return [] }
        // Onto white first. The sheet's own background is the window's, which
        // an offscreen cache does not draw, so its text arrives as black on
        // transparent — which the recogniser reads as black on black: measured,
        // it read only the two AppKit fields, which paint their own ground.
        guard let context = CGContext(data: nil, width: drawn.width, height: drawn.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        let whole = CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(whole)
        context.draw(drawn, in: whole)
        guard let image = context.makeImage() else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

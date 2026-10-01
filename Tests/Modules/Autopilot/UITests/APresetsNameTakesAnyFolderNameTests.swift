import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The preset name built over a folder's name, fed the folder names nobody
/// types on purpose, and the preset's own folder reached under another
/// spelling.
///
/// The name is an interpolation into an inline table, so a folder whose name
/// is itself a format directive, a quotation mark or a colon goes straight
/// into eight sentences; and «the preset's own folder» is decided by where a
/// path leads, so a link to Downloads is still Downloads and keeps the name the
/// preset began with.
@MainActor
final class APresetsNameTakesAnyFolderNameTests: XCTestCase {

    private let fakeHome = "/Users/x"

    private func model(home: String) async -> AutopilotViewModel {
        let model = AutopilotViewModel(vm: ModuleViewModel(transport: AutopilotWire()),
                                       presetFolders: FakePresetFolders(home: home), home: home)
        await model.load()
        return model
    }

    private func offer(_ model: AutopilotViewModel, _ kind: PresetKind) throws -> OfferedPreset {
        try XCTUnwrap(model.presets.first { $0.preset.kind == kind }, "no \(kind) offered")
    }

    /// `%@`, `%d`, `%1$@`, a backslash, both quotation marks and a colon: each
    /// is carried into the name exactly once, in every language, and nothing
    /// else of the sentence is lost around it.
    func testAFolderNameThatLooksLikeAFormatOrAQuoteIsCarriedVerbatim() async throws {
        let model = await model(home: fakeHome)
        let names = ["Scans %@", "100%d done", "%1$@ %2$@", "Tom's \"Stuff\"",
                     "back\\slash", "Q1: invoices", "«Архив»"]
        for kind in [PresetKind.downloadsByKind, .desktopByMonth] {
            let offer = try offer(model, kind)
            AppLanguage.each { language in
                let bare = model.presetName(offer.preset, at: fakeHome + "/Plain")
                for name in names {
                    let built = model.presetName(offer.preset, at: fakeHome + "/" + name)
                    XCTAssertEqual(built.components(separatedBy: name).count - 1, 1,
                                   "\(kind) \(language): «\(built)» does not carry «\(name)» once")
                    // Everything but the folder is the same sentence as over a
                    // plain folder name.
                    XCTAssertEqual(built.replacingOccurrences(of: name, with: "Plain"), bare,
                                   "\(kind) \(language): «\(name)» changed the rest of the name")
                }
            }
        }
    }

    /// French takes an unbreakable space before its colon and never an ordinary
    /// one; the other languages take no space before one at all.
    func testFrenchPutsAnUnbreakableSpaceBeforeItsColon() async throws {
        let model = await model(home: fakeHome)
        for kind in [PresetKind.downloadsByKind, .desktopByMonth] {
            let offer = try offer(model, kind)
            AppLanguage.only(.fr) {
                let built = model.presetName(offer.preset, at: fakeHome + "/Factures")
                XCTAssertTrue(built.contains("Factures\u{00A0}:"), "«\(built)»")
                XCTAssertFalse(built.contains(" :"), "an ordinary space before the colon: «\(built)»")
            }
            AppLanguage.each { language in
                guard language != .fr else { return }
                let built = model.presetName(offer.preset, at: fakeHome + "/Factures")
                XCTAssertFalse(built.contains("\u{00A0}"), "\(language): «\(built)»")
                XCTAssertFalse(built.contains(" :"), "\(language): «\(built)»")
            }
        }
    }

    /// A folder macOS has no name for is called by its own name in every
    /// language — neither dropped nor left as an empty slot — and a folder macOS
    /// does name is called what macOS calls it, not by its English directory name.
    func testAFolderWithNoSystemNameIsCalledByItsOwnName() async throws {
        let model = await model(home: fakeHome)
        let offer = try offer(model, .downloadsByKind)
        AppLanguage.each { language in
            let built = model.presetName(offer.preset, at: fakeHome + "/Invoices")
            XCTAssertTrue(built.contains("Invoices"), "\(language): «\(built)»")
            XCTAssertFalse(built.hasPrefix(" ") || built.hasPrefix(":"), "\(language): «\(built)»")

            let pictures = model.presetName(offer.preset, at: fakeHome + "/Pictures")
            if let system = SystemFolderNames.display(path: fakeHome + "/Pictures", home: fakeHome,
                                                      language: language.rawValue) {
                XCTAssertTrue(pictures.contains(system), "\(language): «\(pictures)» not «\(system)»")
                XCTAssertFalse(pictures.contains("Pictures"), "\(language): «\(pictures)»")
            }
        }
    }

    /// The preset's own folder under a link and under `/private` is still its
    /// own folder, so the name stays the one it began with. On disk, because
    /// «where does this lead» is a question only a filesystem answers.
    func testTheOwnFolderUnderAnotherSpellingKeepsTheOriginalName() async throws {
        let home = scratchDirectory("preset-name-spellings")
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent("Downloads"),
                               withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent("DL"),
                                  withDestinationURL: home.appendingPathComponent("Downloads"))
        let model = await model(home: home.path)
        let offer = try offer(model, .downloadsByKind)
        var spellings = [home.path + "/DL", home.path + "/downloads", home.path + "/Downloads/"]
        if home.path.hasPrefix("/var/") { spellings.append("/private" + home.path + "/Downloads") }
        AppLanguage.each { language in
            for spelling in spellings {
                XCTAssertEqual(model.presetName(offer.preset, at: spelling),
                               ApStr.presetName(.downloadsByKind),
                               "\(language): \(spelling) is Downloads and got another name")
            }
        }
    }

    /// Chosen and chosen back through a link: the name the preset began with
    /// comes back, and a rename of the draft by the person is never undone by
    /// either choice.
    func testTheWayBackThroughALinkRestoresTheNameAndAnEditSurvivesBoth() async throws {
        let home = scratchDirectory("preset-name-way-back")
        let fm = FileManager.default
        for sub in ["Downloads", "Invoices"] {
            try fm.createDirectory(at: home.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(at: home.appendingPathComponent("DL"),
                                  withDestinationURL: home.appendingPathComponent("Downloads"))
        let model = await model(home: home.path)
        let offer = try offer(model, .downloadsByKind)
        AppLanguage.each { language in
            let away = RuleEditor.pointing(offer.draft, at: home.path + "/Invoices",
                                           from: offer.folder, preset: offer.preset, rvm: model)
            XCTAssertEqual(away?.rule.name.contains("Invoices"), true, "\(language)")
            guard let away else { return }
            let back = RuleEditor.pointing(away.rule, at: home.path + "/DL", from: away.folder,
                                           preset: offer.preset, rvm: model)
            XCTAssertEqual(back?.rule.name, offer.draft.name,
                           "\(language): back through a link did not restore the name")

            var edited = offer.draft
            edited.name = "Pictures sorted by kind"   // typed, and a name the preset could build
            let moved = RuleEditor.pointing(edited, at: home.path + "/Invoices", from: offer.folder,
                                            preset: offer.preset, rvm: model)
            XCTAssertEqual(moved?.rule.name, "Pictures sorted by kind",
                           "\(language): a name the person typed was rebuilt")
        }
    }
}

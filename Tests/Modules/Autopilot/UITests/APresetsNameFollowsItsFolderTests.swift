import HelmTestSupport
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// A «Downloads sorted by kind» rule pointed at Invoices is still called
/// «Downloads sorted by kind», and the row under that folder says so.
///
/// The name follows the folder the way the action already does, and under the
/// same condition: only while it is still the name the preset gave. A name the
/// person typed is theirs. Two of the five names carry a folder word
/// (`downloadsByKind`, `desktopByMonth`); the other three read the same anywhere.
@MainActor
final class APresetsNameFollowsItsFolderTests: XCTestCase {

    private let home = "/Users/x"

    private func model() async -> AutopilotViewModel {
        let model = AutopilotViewModel(vm: ModuleViewModel(transport: AutopilotWire()),
                                       presetFolders: FakePresetFolders(home: home), home: home)
        await model.load()
        return model
    }

    private func offer(_ model: AutopilotViewModel, _ kind: PresetKind) throws -> OfferedPreset {
        try XCTUnwrap(model.presets.first { $0.preset.kind == kind })
    }

    private func pointed(_ rule: Rule, at path: String, from folder: WatchedFolder,
                         _ preset: RulePreset, _ model: AutopilotViewModel)
        -> (folder: WatchedFolder, rule: Rule)? {
        RuleEditor.pointing(rule, at: path, from: folder, preset: preset, rvm: model)
    }

    /// Both presets that name a folder, in every language — the name is built
    /// from a per-language table, and a table that joins the folder on wrongly
    /// in one of eight is what this holds.
    func testAnUneditedNameNamesTheChosenFolderInEveryLanguage() async throws {
        let model = await model()
        for kind in [PresetKind.downloadsByKind, .desktopByMonth] {
            let offer = try offer(model, kind)
            AppLanguage.each { language in
                let draft = offer.draft
                guard let next = pointed(draft, at: home + "/Invoices", from: offer.folder,
                                         offer.preset, model) else {
                    return XCTFail("the gate refused an ordinary folder (\(language))")
                }
                XCTAssertTrue(next.rule.name.contains("Invoices"),
                              "\(kind) \(language): «\(next.rule.name)» does not name the folder")
                XCTAssertNotEqual(next.rule.name, draft.name, "\(kind) \(language)")
                XCTAssertEqual(next.rule.id, draft.id, "a rename must leave it the same preset")

                // Chosen again: the name built for Invoices is still the preset's.
                let again = pointed(next.rule, at: home + "/Receipts", from: next.folder,
                                    offer.preset, model)
                XCTAssertEqual(again?.rule.name.contains("Receipts"), true,
                               "\(kind) \(language): a second choice kept the first folder's name")
                XCTAssertEqual(again?.rule.name.contains("Invoices"), false)

                // And back where the preset began: the name it began with.
                let home = pointed(next.rule, at: offer.folder.path, from: next.folder,
                                   offer.preset, model)
                XCTAssertEqual(home?.rule.name, draft.name,
                               "\(kind) \(language): the way back did not restore the name")
            }
        }
    }

    func testTheEnglishNameNoLongerSaysDownloadsOverAnotherFolder() async throws {
        let model = await model()
        let offer = try offer(model, .downloadsByKind)
        AppLanguage.only(.en) {
            let next = pointed(offer.draft, at: home + "/Pictures", from: offer.folder,
                               offer.preset, model)
            XCTAssertEqual(next?.rule.name, "Pictures sorted by kind")
        }
    }

    func testAnEditedNameStaysWhereThePersonPutIt() async throws {
        let model = await model()
        let offer = try offer(model, .downloadsByKind)
        var edited = offer.draft
        edited.name = "Mine"

        let next = pointed(edited, at: home + "/Invoices", from: offer.folder, offer.preset, model)

        XCTAssertEqual(next?.rule.name, "Mine", "a name the person typed was rebuilt under them")
        XCTAssertEqual(next?.folder.path, home + "/Invoices", "precondition: the folder moved")
    }

    /// The three whose names say nothing about a folder read the same anywhere,
    /// so choosing another folder must not touch them.
    func testANameThatNamesNoFolderIsLeftAlone() async throws {
        let model = await model()
        for kind in [PresetKind.screenshots, .oldInstallers, .largeDownloads] {
            let offer = try offer(model, kind)
            let next = pointed(offer.draft, at: home + "/Invoices", from: offer.folder,
                               offer.preset, model)
            XCTAssertEqual(next?.rule.name, offer.draft.name, "\(kind)")
        }
    }
}

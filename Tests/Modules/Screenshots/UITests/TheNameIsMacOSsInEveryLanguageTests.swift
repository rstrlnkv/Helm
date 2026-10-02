import Foundation
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The words are macOS's, in all eight languages, and are checked against the
/// table they were copied from.** The file-name template, the noun, the four
/// shortcut boxes' names and the privacy pane's name were each read out of a
/// system bundle once, at development time, into Helm's own `.strings`. A
/// hand-written Russian "Снимок экрана" that drifted from what the Mac itself
/// calls the file would give a person two names for one thing in one folder.
///
/// Helm's `zh` is macOS's `zh_CN` and its `pt` is `pt_BR`, which is the variant
/// its own `pt.lproj` already follows.
final class TheNameIsMacOSsInEveryLanguageTests: XCTestCase {

    private static let capture = "/System/Library/CoreServices/screencaptureui.app/Contents/Resources/Localizable.loctable"
    private static let keyboard = "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/Resources/DefaultShortcutsTable.loctable"
    private static let privacy = "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable"

    private func system(_ language: AppLanguage) -> String {
        switch language {
        case .zh: "zh_CN"
        case .pt: "pt_BR"
        default: language.rawValue
        }
    }

    /// Language → key → string. A language's dictionary holds other kinds of
    /// value beside strings (plural variants), so the strings are picked out one
    /// at a time: casting the whole dictionary to `[String: String]` fails for the
    /// lot and answers "no such key" for every key in it.
    private func table(_ path: String) throws -> [String: [String: String]] {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path),
                                 "macOS's own table is not at \(path) — a check that skips is a check that passes")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        return plist.compactMapValues { language in
            (language as? [String: Any])?.compactMapValues { $0 as? String }
        }
    }

    func testTheFileNameTemplateIsMacOSsInEveryLanguage() throws {
        let capture = try table(Self.capture)
        var compared = 0
        AppLanguage.each { language in
            guard let entry = capture[system(language)],
                  let template = entry["%@ %@ at %@"], let word = entry["Screenshot"]
            else { return XCTFail("\(language): macOS has no template or no word") }
            // The word folded into the template's first slot, which is how Helm's
            // one key carries both.
            let expected = template.replacingOccurrences(of: "%@", with: word, options: [], range: template.range(of: "%@"))
            XCTAssertEqual(L("Screenshot %@ at %@", language: language), expected, "\(language)")
            XCTAssertEqual(L("Screenshot", language: language), word, "\(language): the noun")
            compared += 1
        }
        XCTAssertEqual(compared, AppLanguage.allCases.count)
    }

    func testTheRussianTemplateKeepsItsUnbreakableSpaces() {
        AppLanguage.only(.ru) {
            let template = L("Screenshot %@ at %@", language: .ru)
            XCTAssertEqual(template.filter { $0 == "\u{00A0}" }.count, 2,
                           "the Russian template carries two no-break spaces and lost them: \(template.debugDescription)")
        }
    }

    func testTheFourBoxNamesAreMacOSsInEveryLanguage() throws {
        let keyboard = try table(Self.keyboard)
        AppLanguage.each { language in
            for box in [SystemBoxName.saveScreen, .saveArea, .copyScreen, .copyArea] {
                let expected = keyboard[system(language)]?[box.key] ?? (language == .en ? box.key : nil)
                XCTAssertNotNil(expected, "\(language): macOS has no name for \(box.key)")
                XCTAssertEqual(L(box.key, language: language), expected, "\(language): \(box.key)")
            }
        }
    }

    /// Helm's `pt` and `en` write macOS's title case in sentence case, as the
    /// rest of their files do; the other six are copied as macOS has them.
    private func sentence(_ text: String, _ language: AppLanguage) -> String {
        guard language == .en || language == .pt else { return text }
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        return ([String(words[0])] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }

    /// «No timer» is its own key, not the «None» the hotkey recorder uses: German
    /// has «Keiner» for the one and macOS says «Ohne» in the Timer menu, and one key
    /// means one thing.
    /// The bar's words — the three capture buttons' tooltips, Capture, Options,
    /// the floating thumbnail and the remembered selection — are the ones the
    /// system's own bar carries, in each language.
    func testTheBarsWordsAreMacOSsInEveryLanguage() throws {
        let capture = try table(Self.capture)
        let pairs = [("Capture entire screen", "CAPTURESCREEN"), ("Capture selected window", "CAPTUREWINDOW"),
                     ("Capture selected portion", "CAPTURESELECTION"), ("Capture", "Capture"), ("Options", "Options"),
                     ("Show floating thumbnail", "Show Floating Thumbnail"),
                     ("Remember last selection", "Remember Last Selection"), ("Timer", "Timer"), ("No timer", "None")]
        var compared = 0
        AppLanguage.each { language in
            guard let entry = capture[system(language)] else { return XCTFail("\(language): no table") }
            for (key, source) in pairs {
                guard let word = entry[source] else { return XCTFail("\(language): macOS has no \(source)") }
                // The English key is Helm's own wording for macOS's «None» (see above).
                let expected = key == "No timer" && language == .en ? key : sentence(word, language)
                XCTAssertEqual(L(key, language: language), expected, "\(language): \(key)")
                compared += 1
            }
        }
        XCTAssertEqual(compared, pairs.count * AppLanguage.allCases.count)
    }

    /// The folder choice at the end of Save to is macOS's «Other…» from the same
    /// table, and its own key — KeepAwake's «Other…» stays — so Portuguese can say
    /// «Outra…» for a folder.
    func testTheFolderChoiceIsMacOSsOtherInEveryLanguage() throws {
        let capture = try table(Self.capture)
        AppLanguage.each { language in
            guard let word = capture[system(language)]?["Other…"] else { return XCTFail("\(language): macOS has no Other…") }
            // The English key is Helm's own wording, «Other folder…», since the
            // English «Other…» does not say what it is other than; the seven
            // translations are macOS's word.
            XCTAssertEqual(ScStr.targetOther, language == .en ? "Other folder…" : word, "\(language)")
        }
        AppLanguage.only(.pt) { XCTAssertEqual(ScStr.targetOther, "Outra…") }
    }

    /// «Save to» and «Save folder» are two things and read as two in every language
    /// (Japanese had one word, 保存先, for both).
    func testSaveToAndSaveFolderAreTwoLabelsInEveryLanguage() {
        AppLanguage.each { language in
            XCTAssertNotEqual(ScStr.saveTo, ScStr.folder, "\(language)")
        }
    }

    /// The page and the bar name the thumbnail the same, macOS's way: the key the
    /// bar test above compares, and no second wording for it on the page.
    func testThePageAndTheBarShareOneThumbnailKey() throws {
        let page = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ScreenshotsSettingsPage.swift")
        XCTAssertTrue(page.contains("ScStr.floatingThumbnail"), "the page does not use the bar's thumbnail key")
        XCTAssertFalse(page.contains("ScStr.thumbnail,") || page.contains("ScStr.thumbnail)"), "the page has a wording of its own")
    }

    /// «5 seconds» and «10 seconds» are macOS's own plural, taken at 5 and at 10 — the Russian
    /// is the genitive plural at both, which is why they are two keys.
    func testTheTimerChoicesAreMacOSsSecondsInEveryLanguage() throws {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: Self.capture))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        AppLanguage.each { language in
            let entry = (plist[system(language)] as? [String: Any])?["%d Seconds"] as? [String: Any]
            let forms = entry?["seconds"] as? [String: Any]
            let form = language == .ru ? "many" : "other"
            guard let pattern = forms?[form] as? String else { return XCTFail("\(language): no \(form) form") }
            for (key, number) in [("5 seconds", 5), ("10 seconds", 10)] {
                let expected = pattern.replacingOccurrences(of: "%2$@", with: String(number))
                XCTAssertEqual(L(key, language: language), language == .en ? expected.lowercased() : expected,
                               "\(language): \(key)")
            }
        }
    }

    /// Box 184's name is the one macOS's Keyboard pane draws.
    func testThePanelBoxIsNamedAsMacOSNamesIt() throws {
        let keyboard = try table(Self.keyboard)
        AppLanguage.each { language in
            XCTAssertEqual(ScStr.boxName(.panel),
                           keyboard[system(language)]?["Screenshot and recording options"] ?? "<not in macOS>",
                           "\(language)")
        }
    }

    func testTheModuleNameAndThePaneNameAreMacOSsToo() throws {
        let keyboard = try table(Self.keyboard), privacy = try table(Self.privacy)
        AppLanguage.each { language in
            XCTAssertEqual(L("Screenshots", language: language),
                           language == .en ? "Screenshots" : keyboard[system(language)]?["Screenshots"] ?? "<not in macOS>",
                           "\(language): the module's name")
            XCTAssertEqual(L("Screen & System Audio Recording", language: language),
                           privacy[system(language)]?["SCREENANDAUDIOCAPTURE"] ?? "<not in macOS>",
                           "\(language): the privacy pane's name")
        }
    }

    /// The sentences that send a person to the pane say its name as macOS draws
    /// it — a name is found by matching it, and an inflected one is not found.
    func testTheSentencesThatNameThePaneSayItAsMacOSDrawsIt() throws {
        let privacy = try table(Self.privacy)
        AppLanguage.each { language in
            guard let pane = privacy[system(language)]?["SCREENANDAUDIOCAPTURE"] else {
                return XCTFail("\(language): macOS has no name for the pane")
            }
            for key in ["Allow Helm under Screen & System Audio Recording, then press the shortcut again.",
                        "Open Screen & System Audio Recording…"] {
                XCTAssertTrue(L(key, language: language).contains(pane),
                              "\(language): «\(L(key, language: language))» does not carry «\(pane)»")
            }
        }
    }

    /// Helm's `pt` is the Brazilian one throughout, so a "saved" is *salvo* and
    /// never the European *guardado* that the same screen would put beside
    /// "Salvar e copiar".
    func testPortugueseSaysSavedTheWayTheRestOfThePtFileDoes() {
        AppLanguage.only(.pt) {
            XCTAssertEqual(L("Saved", language: .pt), "Salvo")
            XCTAssertEqual(L("Saved and copied", language: .pt), "Salvo e copiado")
            XCTAssertEqual(L("The screenshot could not be saved.", language: .pt),
                           "Não foi possível salvar a captura.")
        }
    }

    /// The word of the file name is Helm's language and its clock is the Mac's
    /// region, so a Mac set to a region whose day-period marker is in a script
    /// Helm does not speak still names its files in one language.
    func testTheFileNameClockIsHelmsLanguageInTheMacsRegion() {
        let korea = Locale(identifier: "ko_KR")
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 30; parts.hour = 22; parts.minute = 25; parts.second = 33
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let moment = calendar.date(from: parts)!
        var checked = 0
        AppLanguage.each { language in
            let naming = ScStr.naming(system: korea, language: language)
            XCTAssertEqual(naming.locale.language.languageCode?.identifier, language.rawValue, "\(language)")
            XCTAssertEqual(naming.locale.region?.identifier, "KR", "\(language): the region is the Mac's")
            let name = ShotNames.base(date: moment, naming: naming, timeZone: TimeZone(identifier: "UTC")!)
            XCTAssertFalse(name.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) },
                           "\(language): a Korean day period in a name Helm wrote in \(language): \(name)")
            checked += 1
        }
        XCTAssertEqual(checked, AppLanguage.allCases.count)
    }

    /// The save-screen box and the copy-area clipboard box carry macOS's Russian names, spelled out here
    /// rather than read from the table.
    func testTheSaveScreenAndCopyAreaBoxesAreNamedInRussian() {
        AppLanguage.only(.ru) {
            XCTAssertEqual(ScStr.boxName(.saveScreen), "Сохранить изображение экрана как файл")
            XCTAssertEqual(ScStr.boxName(.copyArea), "Скопировать изображение выбранной области в буфер обмена")
        }
    }
}

private enum SystemBoxName: CaseIterable {
    case saveScreen, saveArea, copyScreen, copyArea
    var key: String {
        switch self {
        case .saveScreen: "Save picture of screen as a file"
        case .saveArea: "Save picture of selected area as a file"
        case .copyScreen: "Copy picture of screen to the clipboard"
        case .copyArea: "Copy picture of selected area to the clipboard"
        }
    }
}

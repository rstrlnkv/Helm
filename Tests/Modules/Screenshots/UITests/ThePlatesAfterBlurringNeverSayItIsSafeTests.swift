import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **After "Blur Emails and Phone Numbers" the plate says what was done, never what the picture now is** — and a result of nothing is not
/// good news. In every language: with no finds the plate is the one asking the person to check the picture, with finds it names the count and
/// asks the same, and the item's hint names the four kinds it blurs and no others.
///
/// **The forbidden words are a tripwire, not a proof.** The lists below are short and written by hand, one per language: a plate that says
/// "safe" in a word that is not on the list passes. What they catch is the plain regression — someone writing "Personal data hidden" — and
/// the real guard is the sentences themselves, asserted whole. No plate carries a check mark either, and the plate is drawn white on dark,
/// never green (`LabelLayer`).
@MainActor
final class ThePlatesAfterBlurringNeverSayItIsSafeTests: XCTestCase {

    /// Stems of the words for safe, hidden, protected, private and personal, per language, matched without case and accents.
    private static let forbidden: [AppLanguage: [String]] = [
        .en: ["safe", "hidden", "protected", "secure", "private", "personal"],
        .de: ["sicher", "versteckt", "verborgen", "geschützt", "privat", "persönlich"],
        .es: ["seguro", "oculto", "protegid", "privad", "personal"],
        .fr: ["sûr", "sécuris", "caché", "masqué", "protégé", "privé", "personnel"],
        .ja: ["安全", "非表示", "保護", "隠", "個人"],
        .pt: ["seguro", "oculto", "protegid", "privad", "pessoal"],
        .ru: ["безопас", "скрыт", "защищ", "личн", "приват"],
        .zh: ["安全", "隐藏", "保护", "隐私", "个人"],
    ]

    /// The word that asks the person to do the checking, per language, which the plates of a blur must carry.
    private static let checkYourself: [AppLanguage: String] = [
        .en: "yourself", .de: "selbst", .es: "tú", .fr: "vous-même", .ja: "自分で", .pt: "você mesmo", .ru: "сами", .zh: "自行",
    ]

    /// The four kinds of find, per language, which the hint must name — and a postal address must not be named.
    private static let kinds: [AppLanguage: [String]] = [
        .en: ["email", "phone", "card", "links"], .de: ["E-Mail", "Telefon", "Kartennummern", "Links"],
        .es: ["correo", "teléfono", "tarjeta", "enlaces"], .fr: ["e-mail", "téléphone", "carte", "liens"],
        .ja: ["メールアドレス", "電話番号", "カード番号", "リンク"], .pt: ["e-mail", "telefone", "cartão", "links"],
        .ru: ["почты", "телефон", "карт", "ссылки"], .zh: ["电子邮件", "电话号码", "卡号", "链接"],
    ]
    private static let notNamed: [String] = ["postal", "Postadresse", "postal address", "почтовые адреса", "邮政", "郵便"]

    private func contains(_ text: String, _ stem: String) -> Bool {
        text.range(of: stem, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The same, accents kept: «tú» is a word and «tu» is the middle of another.
    private func says(_ text: String, _ word: String) -> Bool { text.range(of: word, options: .caseInsensitive) != nil }

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    func testNoPlateOfTheReadingItemsSaysSafeHiddenOrProtectedInAnyLanguage() {
        AppLanguage.each { language in
            let words = Self.forbidden[language] ?? []
            XCTAssertGreaterThan(words.count, 3, "\(language): the tripwire list is empty, so it can catch nothing")
            let plates = [ScStr.blurred(0), ScStr.blurred(1), ScStr.blurred(37), ScStr.nothingBlurred, ScStr.textCopied,
                          ScStr.noTextFound, ScStr.textUnreadable]
            XCTAssertEqual(Set(plates).count, plates.count, "\(language): two plates are the same sentence: \(plates)")
            for plate in plates {
                XCTAssertFalse(plate.isEmpty, "\(language)")
                for word in words {
                    XCTAssertFalse(contains(plate, word), "\(language): the plate «\(plate)» says «\(word)»")
                }
                XCTAssertFalse(plate.contains { "✓✔✅☑".contains($0) }, "\(language): a check mark on «\(plate)»")
            }
        }
    }

    /// The control for the list: the words it holds are found in a sentence that says what it must not.
    func testTheTripwireCatchesTheSentenceItIsMadeFor() {
        let bad = ["en": "Personal data hidden", "de": "Persönliche Daten verborgen", "es": "Datos personales ocultos",
                   "fr": "Données personnelles masquées", "ja": "個人情報を非表示にしました", "pt": "Dados pessoais ocultos",
                   "ru": "Личное скрыто", "zh": "个人信息已隐藏"]
        AppLanguage.each { language in
            let sentence = bad[language.rawValue] ?? ""
            XCTAssertFalse(sentence.isEmpty, "\(language)")
            XCTAssertTrue((Self.forbidden[language] ?? []).contains { contains(sentence, $0) }, "\(language): «\(sentence)» passes the tripwire")
        }
    }

    func testTheCountPlateAndTheZeroPlateAskThePersonToCheckInEveryLanguage() {
        AppLanguage.each { language in
            let ask = Self.checkYourself[language] ?? ""
            XCTAssertFalse(ask.isEmpty, "\(language)")
            XCTAssertTrue(says(ScStr.nothingBlurred, ask), "\(language): the zero plate «\(ScStr.nothingBlurred)» does not ask for a check")
            XCTAssertTrue(says(ScStr.blurred(3), ask), "\(language): «\(ScStr.blurred(3))» does not ask for a check")
            XCTAssertTrue(ScStr.blurred(3).contains("3"), "\(language): the count is not on the plate")
            XCTAssertFalse(ScStr.nothingBlurred.contains(where: \.isNumber), "\(language): the zero plate carries a number")
            XCTAssertFalse(says(ScStr.textCopied, ask), "\(language): the control: the copy plate does not ask, so the check above is about the blur plates")
        }
    }

    func testTheHintNamesTheFourKindsAndNoPostalAddress() {
        AppLanguage.each { language in
            let hint = ScStr.blurPersonalTextHint
            for kind in Self.kinds[language] ?? [] { XCTAssertTrue(contains(hint, kind), "\(language): the hint «\(hint)» does not name «\(kind)»") }
            XCTAssertEqual(Self.kinds[language]?.count, 4, "\(language)")
            for word in Self.notNamed { XCTAssertFalse(contains(hint, word), "\(language): the hint names «\(word)», which the item does not find") }
        }
        // The item carries it as its hint, the other reading item none.
        for case .reading(let title, _, _, _, let hint) in EditorMenu.items(for: EditorBarModel()) {
            XCTAssertEqual(hint, title == ScStr.blurPersonalText ? ScStr.blurPersonalTextHint : nil, title)
        }
    }

    /// Through the overlay, with a reading that finds nothing: the plate on the screen is the zero plate of the language, in every language.
    func testAReadingThatFindsNothingPutsUpTheZeroPlateInEveryLanguage() async throws {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        for language in AppLanguage.allCases {
            await AppLanguage.only(language) {
                var results: [OverlayResult] = []
                let tools = EditorTextTools(read: { _, _ in .read([], RecognizedBoxes.Source(pixels: area, scale: 1)) },
                                            copy: { _ in .noText })
                guard let rig = try? OverlayRig.overlay(scale: 1, area: area, textTools: tools, onResult: { results.append($0) }) else {
                    return XCTFail("\(language): no overlay")
                }
                defer { rig.overlay.close() }
                XCTAssertTrue(rig.view.visiblePlates.isEmpty, "\(language): the control: no plate before the item")
                rig.overlay.perform(.blurPersonalText)
                await waitUntil("\(language): the plate came") { !rig.view.visiblePlates.isEmpty }
                XCTAssertEqual(rig.view.visiblePlates.compactMap(\.string), [ScStr.nothingBlurred], "\(language)")
                XCTAssertEqual(rig.overlay.editedLayers, [], "\(language): a layer for no find")
                // The next input takes the plate away.
                rig.overlay.perform(.tool(.rectangle))
                XCTAssertTrue(rig.view.visiblePlates.isEmpty, "\(language): the plate stayed after the next input")
            }
        }
    }
}

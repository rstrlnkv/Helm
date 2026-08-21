import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// A caption under a switch is a caption, not a page.
///
/// `adminNote` reached **606 characters in German** — seven drawn lines under one
/// toggle, and 3.5× the next-longest caption the same page draws. Nothing was
/// wrong with what it said: it is a passwordless `sudo pmset` rule in
/// `/etc/sudoers.d`, and the person about to type a password is owed every word
/// of it. What was wrong is that all of it was spent before the decision, in the
/// row. The part the decision needs stays in the row and the consequences moved
/// behind the ⓘ `HelmSettingRow` draws when it is given an `explainer:`.
///
/// **The ceiling is measured off this page rather than chosen.** The longest
/// other caption `KeepAwakeSettingsPage` draws is `lidRefused` at 188 characters
/// in German (154 fr, 140 es, 137 pt, 130 ru, 124 en — the same sentence is 157
/// in Russian for the next one down, which is what the owner saw); 200 is that
/// number with a translator's headroom, and a third of what this rule was
/// written for. It is a ceiling for one row, not a sweep: `Layout`'s composed
/// tap-key note reaches 554 in German and is not touched here.
///
/// Every language, because the suite runs in whichever language this Mac is set
/// to — a check reading `AppLanguage.current` inspects one of the eight and
/// reports on all of them. Every `LidRowNote`, from the enum rather than a list
/// here, so a fifth state is measured the day it is written.
final class TheLidCaptionFitsUnderTheSwitchTests: XCTestCase {

    /// 200. The derivation is above; the number is here once.
    private static let ceiling = 200

    func testNoLidCaptionIsAWallOfText() {
        AppLanguage.each { language in
            for note in LidRowNote.allCases {
                let caption = KAStr.lidNote(note)
                XCTAssertLessThanOrEqual(caption.count, Self.ceiling, """
                    \(language.rawValue)/\(note): \(caption.count) characters under one \
                    switch. What the decision needs stays in the row; the rest belongs \
                    behind the ⓘ — «\(caption)»
                    """)
            }
        }
    }

    /// The ceiling above is satisfied by silence: a caption that said nothing at
    /// all would pass it, and a row that says nothing is the defect this module
    /// spent a release closing. So the subject is asserted to exist first.
    func testEveryLidStateStillSaysSomething() {
        AppLanguage.each { language in
            for note in LidRowNote.allCases {
                XCTAssertGreaterThan(KAStr.lidNote(note).count, 20,
                                     "\(language.rawValue)/\(note): the row has nothing to say")
            }
        }
    }

    /// And the half that moved is reachable from the row it moved out of. The
    /// state that offers it is the one where a password is about to be asked
    /// for; `grantRemains` offers none, because there the app can still take the
    /// rule out itself and the row says how — a glyph with an empty popover
    /// behind it is worse than no glyph.
    func testTheCostOfTheGrantKeepsItsExplanation() {
        AppLanguage.each { language in
            XCTAssertNotNil(KAStr.lidExplainer(.whatItCosts),
                            "\(language.rawValue): the row asks for a password and explains "
                            + "none of what it buys")
            for note in [LidRowNote.refused, .grantRemains, .sleepIsOff] {
                XCTAssertNil(KAStr.lidExplainer(note),
                             "\(language.rawValue)/\(note): a disclosure with nothing behind it")
            }
        }
    }
}

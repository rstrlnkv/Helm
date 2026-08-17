// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmUI
import XCTest
@testable import Module_VPN_UI

/// `VPNStr.country(_:)` names a place in the app's own language, from the
/// two-letter code an exit probe answers — never the service's own spelling
/// of it (the doc comment's «a third party does not get to name a place in
/// Helm's window»).
///
/// Looped over `AppLanguage.allCases` through `AppLanguage.override`, the
/// mechanism this suite already uses for a function that reads
/// `AppLanguage.current` directly rather than taking a language parameter
/// (`AGoneFileGetsItsOwnSentenceTests`) — a bare assertion would only ever
/// check whichever language this machine happens to be set to.
final class ACountryIsNamedInHelmsLanguageTests: XCTestCase {

    func testARealCodeAnswersARealNameInEveryLanguage() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let name = VPNStr.country("DE")
            XCTAssertNotNil(name, "\(language.rawValue) answered nothing for a real region code")
            XCTAssertFalse(name!.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue) answered an empty name for a real region code")
        }
    }

    /// The same code read back in two languages should not collapse onto one
    /// spelling — otherwise the lookup could be silently ignoring the
    /// language and returning ICU's fallback every time.
    func testTheNameDiffersAcrossAtLeastTwoLanguages() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        AppLanguage.override = .en
        let english = VPNStr.country("DE")
        AppLanguage.override = .ru
        let russian = VPNStr.country("DE")

        XCTAssertNotEqual(english, russian,
                          "the English and Russian names for the same country came back identical")
    }

    func testACodeThatIsNotOneAnswersNil() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        AppLanguage.override = .en
        // "ZZ" is CLDR's own placeholder for "Unknown Region" and answers a
        // real string — "XX" and the empty string are not region codes at
        // all, which is the case this guards.
        XCTAssertNil(VPNStr.country("XX"), "\"XX\" is not a region code and should answer nothing")
        XCTAssertNil(VPNStr.country(""), "an empty code should answer nothing")
    }
}

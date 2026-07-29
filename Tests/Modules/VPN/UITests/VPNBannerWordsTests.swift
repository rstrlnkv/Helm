// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// What the banner says, in the eight languages Helm ships.
///
/// None of it was translated: macOS ships this exact sentence in
/// `Network.appex/Contents/Resources/Localizable.loctable`, and the values
/// below are `VPN_CONNECTED`, `Connected` and `Not Connected` read out of that
/// table (ARCHITECTURE.md § Localization). Pinning them here is what keeps a
/// later edit from re-translating what macOS has already settled — German says
/// „%@“ ist verbunden, with its own quotation marks, and nobody would guess
/// that.
///
/// Parameterized by language rather than reading `AppLanguage.current`: the
/// suite runs in this machine's language, so a test that asks `current` checks
/// English eight times.
final class VPNBannerWordsTests: XCTestCase {

    /// `VPN_CONNECTED` per language, with `%@` standing where the name goes.
    private static let connected: [AppLanguage: String] = [
        .en: "NAME is connected",
        .ru: "NAME подключен",
        .es: "NAME está conectado",
        .fr: "NAME est connecté",
        .de: "„NAME“ ist verbunden",
        .ja: "NAMEは接続されています",
        .zh: "NAME已连接",
        .pt: "NAME está conectado",
    ]

    /// The same sentence negated. macOS has no settled "%@ is disconnected" —
    /// the nearest are `VPN_DISCONNECTING`, which is the transition and not the
    /// outcome, and the state `Not Connected`. So the banner reports the state
    /// the rule left behind, and each language negates its own verified
    /// sentence with the word that table already uses for it: не подключено,
    /// Nicht verbunden, Non connecté, 未连接, 未接続.
    private static let disconnected: [AppLanguage: String] = [
        .en: "NAME is not connected",
        .ru: "NAME не подключен",
        .es: "NAME no está conectado",
        .fr: "NAME n’est pas connecté",
        .de: "„NAME“ ist nicht verbunden",
        .ja: "NAMEは接続されていません",
        .zh: "NAME未连接",
        .pt: "NAME não está conectado",
    ]

    func testTheConnectedBannerIsMacOSOwnSentence() {
        for (language, expected) in Self.connected {
            XCTAssertEqual(VPNStr.automationBannerBody("NAME", kind: .connected,
                                                       language: language),
                           expected, "\(language) does not say what macOS says")
        }
    }

    func testTheDisconnectedBannerNegatesThatSameSentence() {
        for (language, expected) in Self.disconnected {
            XCTAssertEqual(VPNStr.automationBannerBody("NAME", kind: .disconnected,
                                                       language: language),
                           expected, "\(language) reworded the disconnected banner")
        }
    }

    /// The eight titles are macOS's own state words — `Connected` and
    /// `Not Connected` from the same table.
    func testTheTitleIsTheStateMacOSNamesIt() {
        let connected: [AppLanguage: String] = [
            .en: "Connected", .ru: "Подключено", .es: "Conectado", .fr: "Connecté",
            .de: "Verbunden", .ja: "接続済み", .zh: "已连接", .pt: "Conectado",
        ]
        // U+00A0 in the Russian, as macOS writes it: a two-word status with a
        // breaking space in it can be split across lines.
        let disconnected: [AppLanguage: String] = [
            .en: "Not connected", .ru: "Не\u{00A0}подключено", .es: "Sin conexión",
            .fr: "Non connecté", .de: "Nicht verbunden", .ja: "未接続",
            .zh: "未连接", .pt: "Não conectado",
        ]
        for (language, expected) in connected {
            XCTAssertEqual(VPNStr.automationBannerTitle(.connected, language: language), expected)
        }
        for (language, expected) in disconnected {
            XCTAssertEqual(VPNStr.automationBannerTitle(.disconnected, language: language), expected)
        }
    }

    /// The name is the only thing on the banner that answers *which* VPN, so a
    /// table entry that dropped the placeholder would leave the banner useless
    /// in that one language and nowhere else.
    func testEveryLanguageKeepsTheNameInBothKinds() {
        for language in AppLanguage.allCases {
            for kind in [VPNAutomation.Kind.connected, .disconnected] {
                let body = VPNStr.automationBannerBody("NAME", kind: kind, language: language)
                XCTAssertTrue(body.contains("NAME"),
                              "\(language) \(kind) dropped the connection's name: \(body)")
            }
        }
    }

    /// A disconnection is not a connection, and the banner must not say it is.
    func testTheTwoKindsReadDifferentlyInEveryLanguage() {
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(VPNStr.automationBannerBody("NAME", kind: .connected,
                                                          language: language),
                              VPNStr.automationBannerBody("NAME", kind: .disconnected,
                                                          language: language),
                              "\(language) says the same thing either way")
            XCTAssertNotEqual(VPNStr.automationBannerTitle(.connected, language: language),
                              VPNStr.automationBannerTitle(.disconnected, language: language),
                              "\(language) titles both kinds the same")
        }
    }

    /// A missing table entry is not an error — `L()` falls back to English — so
    /// the only thing that catches one is asking whether the answer is still
    /// English in a language that is not.
    func testNoLanguageFallsBackToEnglish() {
        for language in AppLanguage.allCases where language != .en {
            for kind in [VPNAutomation.Kind.connected, .disconnected] {
                XCTAssertNotEqual(VPNStr.automationBannerBody("NAME", kind: kind,
                                                              language: language),
                                  VPNStr.automationBannerBody("NAME", kind: kind, language: .en),
                                  "\(language) \(kind) body was never translated")
                XCTAssertNotEqual(VPNStr.automationBannerTitle(kind, language: language),
                                  VPNStr.automationBannerTitle(kind, language: .en),
                                  "\(language) \(kind) title was never translated")
            }
        }
    }
}

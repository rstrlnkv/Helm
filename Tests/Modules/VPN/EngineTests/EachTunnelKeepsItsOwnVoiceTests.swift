// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// Every configuration can be told how loudly to speak, and a configuration
/// nobody has told keeps saying what the app was shipped saying.
///
/// **Absence means inherit, which is why there is no migration.** The three
/// settings this replaces — the rules' notice, the drop's notice, the ring —
/// are single stored values that an installed build already has. Making them
/// per connection by *moving* them would need a one-time write keyed to
/// whichever configuration happened to be first, and a one-time write is the
/// kind of thing that runs twice or not at all. So the book holds only what
/// somebody actually changed, and everything else falls through to the value
/// that is already in the store.
///
/// **Keyed by the configuration's id, not its name.** This module has already
/// paid for that distinction once: a rule keyed by name is orphaned the moment
/// somebody renames the configuration in System Settings (`VPNRules.orphaned`
/// exists for it). `scutil` gives every service a UUID and `VPNConnection.id`
/// carries it, so a rename here costs nothing.
final class EachTunnelKeepsItsOwnVoiceTests: XCTestCase {

    private let global = (rules: VPNNotice.menuBar, drop: VPNNotice.system, spin: false)

    func testAConfigurationNobodyHasTouchedInheritsTheGlobalSetting() {
        let book = VPNNoticeBook()
        XCTAssertEqual(book.notice(for: "A", kind: .connected,
                                  rules: global.rules, drop: global.drop), .menuBar)
        XCTAssertEqual(book.notice(for: "A", kind: .dropped,
                                   rules: global.rules, drop: global.drop), .system)
        XCTAssertFalse(book.spin(for: "A", fallback: global.spin))
    }

    func testChangingOneHalfLeavesTheOtherInherited() {
        let book = VPNNoticeBook().setting("A", notice: .silent)
        XCTAssertEqual(book.notice(for: "A", kind: .connected,
                                   rules: global.rules, drop: global.drop), .silent)
        // The drop is separate news and was not touched.
        XCTAssertEqual(book.notice(for: "A", kind: .dropped,
                                   rules: global.rules, drop: global.drop), .system)
    }

    func testATeardownAnswersToTheDropSetting() {
        let book = VPNNoticeBook().setting("A", drop: .silent)
        XCTAssertEqual(book.notice(for: "A", kind: .dropped,
                                   rules: global.rules, drop: global.drop), .silent)
        XCTAssertEqual(book.notice(for: "A", kind: .disconnected,
                                   rules: global.rules, drop: global.drop), .menuBar,
                       "a disconnection Helm performed is the rules' volume, not the drop's")
    }

    func testOneConfigurationsChoiceIsNotAnotherS() {
        let book = VPNNoticeBook().setting("A", notice: .silent).setting("B", spin: true)
        XCTAssertEqual(book.notice(for: "B", kind: .connected,
                                   rules: global.rules, drop: global.drop), .menuBar)
        XCTAssertTrue(book.spin(for: "B", fallback: global.spin))
        XCTAssertFalse(book.spin(for: "A", fallback: global.spin))
    }

    func testTheBookSurvivesTheStore() throws {
        let book = VPNNoticeBook()
            .setting("A", notice: .silent)
            .setting("A", drop: .menuBar)
            .setting("B", spin: true)
        let back = VPNNoticeBook.decode(VPNNoticeBook.encode(book))
        XCTAssertEqual(back, book)
    }

    /// A store that holds something else — an older build's shape, a hand-edited
    /// plist — reads as «nobody has changed anything», which inherits. It must
    /// not read as «everything is silent».
    func testRubbishInTheStoreInheritsRatherThanSilences() {
        for text in ["", "{}", "not json at all", "[1,2,3]", "{\"A\":\"loud\"}"] {
            let book = VPNNoticeBook.decode(text)
            XCTAssertEqual(book.notice(for: "A", kind: .connected,
                                       rules: global.rules, drop: global.drop), .menuBar,
                           "\(text.isEmpty ? "an empty string" : text) silenced a configuration")
        }
    }

    /// **Nothing prunes this book.** `scutil` can answer with an empty or short
    /// list — a refusal, a machine mid-boot — and this module already refuses to
    /// act on that elsewhere. A settings store that dropped every entry it could
    /// not match against the current list would throw away a person's choices on
    /// the strength of one bad read.
    func testAConfigurationMissingFromTodaysListKeepsItsVoice() {
        let book = VPNNoticeBook().setting("A", notice: .silent)
        XCTAssertEqual(book.notice(for: "A", kind: .connected,
                                   rules: global.rules, drop: global.drop), .silent)
        XCTAssertEqual(book.entryCount, 1)
    }

    /// Setting a value back to what it inherits removes the entry rather than
    /// recording agreement: a book that grows an entry per glance is a book that
    /// pins today's default for ever.
    func testChoosingWhatItAlreadyInheritsForgetsTheEntry() {
        let book = VPNNoticeBook().setting("A", notice: .silent)
        XCTAssertEqual(book.entryCount, 1)
        let cleared = book.clearing("A")
        XCTAssertEqual(cleared.entryCount, 0)
        XCTAssertEqual(cleared.notice(for: "A", kind: .connected,
                                      rules: global.rules, drop: global.drop), .menuBar)
    }
}

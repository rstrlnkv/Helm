// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmUI
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The sentence a refusal draws, which had one form for two commands.
///
/// «macOS refused to connect «Office»» was said about a refused `--nc stop` as
/// well, so the person who asked to bring a tunnel down was told the opposite of
/// what had happened while the tunnel stayed up. `ARefusalRemembersItsVerbTests`
/// is the other half — that the engine records which command it sent.
final class ARefusedStopIsNotARefusedConnectTests: XCTestCase {

    /// One sentence per verb, in every language — including this machine's, which
    /// is the one a test reading `AppLanguage.current` would check eight times.
    func testTheRefusalNamesTheVerbInEveryLanguage() {
        for language in AppLanguage.allCases {
            let connect = VPNStr.failureRefused("Office", verb: .connect, language: language)
            let disconnect = VPNStr.failureRefused("Office", verb: .disconnect, language: language)
            XCTAssertFalse(connect.isEmpty, "\(language): no sentence at all")
            XCTAssertNotEqual(connect, disconnect,
                              "\(language) says the same thing about a refused connect and a "
                              + "refused disconnect: «\(connect)»")
            XCTAssertTrue(disconnect.contains("Office"),
                          "\(language): the sentence stopped naming the configuration")
        }
    }

    /// What the page draws, from the failure itself rather than from a switch the
    /// page keeps: `VPNStr.failure` is the one reader of `reason` and `verb`
    /// together, so a third reason cannot arrive with a sentence in one surface
    /// and none in another.
    func testAConfigurationThatIsGoneReadsTheSameWayForBothVerbs() {
        let gone = VPNFailure.Reason.noSuchService
        XCTAssertEqual(VPNStr.failure(VPNFailure(name: "Office", reason: gone, verb: .disconnect)),
                       VPNStr.failure(VPNFailure(name: "Office", reason: gone, verb: .connect)),
                       "a configuration that is no longer in System Settings is the same fact "
                       + "whichever command met it, and the next step is the same too")
        XCTAssertNotEqual(VPNStr.failure(VPNFailure(name: "Office", reason: .refused,
                                                   verb: .disconnect)),
                          VPNStr.failure(VPNFailure(name: "Office", reason: .refused,
                                                    verb: .connect)),
                          "precondition: the sentence this page draws does read the verb")
    }
}

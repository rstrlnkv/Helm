// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `ARefusalMustNotCarryTheNameTests` proves the tool's sentence loses **the
/// name the command was about**. It is not the only name the tool can print.
///
/// `scutil` explains a refusal, and the explanation is often about a *different*
/// configuration — the one already holding the interface, the one whose gateway
/// answered — and that name went into the diagnostic file in clear. One
/// configuration named in the file is the whole of what redaction exists to keep
/// out of it: it announces an employer or a provider, and the file is the thing
/// a person attaches to a bug report.
final class ARefusalNamesNoConfigurationTests: XCTestCase {

    private let asked = "Contoso Field Office"
    private let other = "Fabrikam Backup"

    private func refusal(_ output: String, name: String, known: [String]) throws -> String {
        let reply = VPNCommandReply.of(.init(status: 0, output: output),
                                       name: name, knownNames: known)
        guard case .refused(let text) = reply else {
            throw XCTSkip("expected a refusal, got \(reply)")
        }
        return text
    }

    func testARefusalAboutAnotherConfigurationDoesNotNameIt() throws {
        let text = try refusal("cannot start \(asked): \(other) holds the interface",
                               name: asked, known: [asked, other])
        XCTAssertFalse(text.contains(other),
                       "«\(text)» — the tool named a second configuration and it reached the file")
        XCTAssertTrue(text.contains(Redact.vpn(other)),
                      "«\(text)» — and its tag has to be the one the rest of the module's lines "
                      + "carry, or two lines about one tunnel cannot be matched during triage")
        XCTAssertTrue(text.contains("holds the interface"), "the diagnostic part survives")
    }

    /// A name that contains another name. The longer one has to go first, or half
    /// of it is left standing beside the shorter one's tag.
    func testANameContainingAnotherLosesAllOfItself() throws {
        let text = try refusal("cannot start Office VPN Backup: busy",
                               name: "Office", known: ["Office", "Office VPN Backup"])
        XCTAssertFalse(text.contains("Office"), "«\(text)»")
        XCTAssertTrue(text.contains(Redact.vpn("Office VPN Backup")), "«\(text)»")
    }

    /// The same name in another Unicode normalization. `scutil` reads the name out
    /// of the network configuration store and the rule was written from a text
    /// field, so the two can differ byte for byte while naming one configuration.
    ///
    /// This passes today because `replacingOccurrences` without `.literal`
    /// compares canonically — which is a property of Foundation and not of
    /// anything written here, so it is pinned: adding `.literal` for speed would
    /// silently put the name back in the file.
    func testTheNameIsFoundInEitherNormalization() throws {
        let precomposed = "Ёлка"                    // U+0451
        let decomposed = "Е\u{0308}лка"             // Е + combining diaeresis
        XCTAssertNotEqual(Array(precomposed.utf8), Array(decomposed.utf8),
                          "precondition: the two spellings really are different bytes")

        let printedDecomposed = try refusal("cannot start \(decomposed): busy",
                                            name: precomposed, known: [precomposed])
        XCTAssertTrue(printedDecomposed.contains(Redact.vpn(precomposed)), "«\(printedDecomposed)»")
        XCTAssertFalse(printedDecomposed.contains(decomposed), "«\(printedDecomposed)»")

        let printedPrecomposed = try refusal("cannot start \(precomposed): busy",
                                             name: decomposed, known: [decomposed])
        XCTAssertFalse(printedPrecomposed.contains(precomposed), "«\(printedPrecomposed)»")
    }

    /// Through the engine, which is what fills the list of names and writes the
    /// file. Without this the sweep could be perfect and wired to nothing.
    func testTheEngineHandsOverEveryNameItKnows() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        let runner = FakeRunner()
        runner.listOutput = ["Available network connection services:",
                             "* (Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"\(asked)\" [IPSec]",
                             "* (Connected) 22222222-2222-2222-2222-222222222222 IKEv2 \"\(other)\" [IKEv2]"]
            .joined(separator: "\n")
        runner.replies = [asked: "cannot start \(asked): \(other) holds the interface"]
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.refresh()

        engine.connect(asked)

        let lines = HelmLog.shared.recentEntries().filter { $0.category == "vpn" }
        XCTAssertTrue(lines.contains { $0.message.contains("refused") },
                      "precondition: the refusal reached the log at all")
        XCTAssertFalse(lines.contains { $0.message.contains(other) },
                       "a second configuration is named in the diagnostic file: "
                       + "\(lines.map(\.message))")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `scutil`'s complaint is written into the log verbatim, and it usually contains
/// the name of the configuration it is complaining about.
///
/// The log carries no names — that is the standing rule, and every line this
/// module writes runs the name through `Redact.vpn` for it: a VPN name announces
/// an employer or a provider, and the diagnostic file is the thing a person
/// attaches to a bug report. The refusal line was
/// `"\(verb) \(Redact.vpn(name)) refused: \(text)"`, which redacts the name Helm
/// knows and then prints the tool's sentence with that same name inside it.
///
/// The fix is at the point the value is made rather than at the point it is
/// printed: `VPNCommandReply.of(_:name:)` sanitises the text, so `.refused` can
/// only ever hold something already redacted. A rule enforced by the type is a
/// rule the next call site cannot forget — and there is a second one waiting, the
/// wire, since the reply's text is what any future «what did the tool say» screen
/// would read.
///
/// What is *not* redacted, deliberately: `_lastFailure.name`. The screen is
/// allowed to name what the person configured — they typed it into System
/// Settings — and the page draws «macOS refused to connect «Office VPN»» from it.
/// The split is the whole point: the file leaves the machine, the window does not.
final class ARefusalMustNotCarryTheNameTests: XCTestCase {

    private let service = "Contoso Field Office"

    // MARK: - The reading

    func testARefusalDoesNotCarryTheNameItIsAbout() throws {
        let reply = VPNCommandReply.of("cannot start \(service): busy", name: service)

        guard case .refused(let text) = reply else {
            return XCTFail("expected a refusal, got \(reply)")
        }
        XCTAssertFalse(text.contains(service),
                       "«\(text)» — the tool's own sentence names the configuration, and this "
                       + "string is written straight into the diagnostic file")
        XCTAssertTrue(text.contains(Redact.vpn(service)),
                      "«\(text)» — and what stands in its place has to be the tag the rest of "
                      + "this module's lines carry, or two lines about one tunnel cannot be "
                      + "matched up during triage")
        XCTAssertTrue(text.contains("busy"), "the part that is actually diagnostic is still there")
    }

    /// The tool has no reason to spell it the way the person did, and a case that
    /// slips through is the whole name in the file.
    func testTheNameIsFoundWhateverItsCase() throws {
        let reply = VPNCommandReply.of("Cannot start CONTOSO field OFFICE — retry", name: service)

        guard case .refused(let text) = reply else {
            return XCTFail("expected a refusal, got \(reply)")
        }
        XCTAssertFalse(text.lowercased().contains(service.lowercased()), "«\(text)»")
    }

    /// A tool that prints a wall of text is a log entry that pushes everything
    /// else out of a 2 MB file with one rollover.
    func testTheTextIsCapped() throws {
        let reply = VPNCommandReply.of(String(repeating: "e", count: 5_000), name: service)

        guard case .refused(let text) = reply else {
            return XCTFail("expected a refusal, got \(reply)")
        }
        XCTAssertLessThanOrEqual(text.count, 200, "\(text.count) characters into one log line")
    }

    // MARK: - The controls

    /// Classification happens before any of this, which matters for the one name
    /// that could change it: a configuration called «No» would otherwise have the
    /// tool's own «No service» rewritten into something this enum cannot read.
    func testAConfigurationCalledNoStillReportsAMissingService() {
        XCTAssertEqual(VPNCommandReply.of("No service", name: "No"), .noSuchService)
    }

    /// An empty name is not a pattern to search for. Replacing every empty
    /// substring is either a no-op or a disaster, depending on the
    /// implementation, and the engine can be asked to connect `""` by a rule
    /// pointing at a configuration that has been renamed away.
    func testAnEmptyNameLeavesTheTextAlone() {
        XCTAssertEqual(VPNCommandReply.of("cannot start: busy", name: ""),
                       .refused("cannot start: busy"))
    }

    func testSilenceIsStillSuccess() {
        XCTAssertEqual(VPNCommandReply.of("", name: service), .accepted)
    }

    // MARK: - Through the engine, which is what writes the file

    func testTheLogLineAboutARefusalNamesNothing() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        let runner = FakeRunner()
        runner.reply = "cannot start \(service): resource busy"
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, credentials: nil, apps: FakeApps(), work: .inline)

        engine.connect(service)

        let lines = HelmLog.shared.recentEntries().filter { $0.category == "vpn" }
        // The subject first: an absence proves nothing when nothing was written.
        XCTAssertTrue(lines.contains { $0.message.contains("refused") },
                      "precondition: the refusal reached the log at all")
        XCTAssertFalse(lines.contains { $0.message.contains(service) },
                       "the configuration's name is in the diagnostic file: "
                       + "\(lines.map(\.message))")
        XCTAssertTrue(lines.contains { $0.message.contains("resource busy") },
                      "…and the reason the tool gave is not")
    }

    /// The other half of the split, and it is the half a redaction fix is likely
    /// to break: the screen still gets the real name.
    func testTheScreenStillKnowsWhichConfigurationItWas() {
        let runner = FakeRunner()
        runner.reply = "cannot start \(service): resource busy"
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, credentials: nil, apps: FakeApps(), work: .inline)

        engine.connect(service)

        XCTAssertEqual(engine.lastFailure, VPNFailure(name: service, reason: .refused),
                       "the page says «macOS refused to connect «\(service)»» from this")
    }
}

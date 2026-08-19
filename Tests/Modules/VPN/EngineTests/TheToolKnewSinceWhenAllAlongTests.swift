// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_VPN_Engine

/// **«`scutil` cannot answer «since when»» was written in the engine for
/// several releases, and the tool had been answering all along.**
///
/// Every status read ends with `LastStatusChangeTime`, and that line was already
/// in this module's own committed fixture — `TheInterfaceComesFromTheToolTests`
/// carries it — being walked past on the way to the interface name. What it cost
/// is the hole in the first column of the page on the most ordinary Mac there
/// is: a VPN raised at login and the menu bar app started after it, where Helm's
/// own observation is the only source and Helm was not watching. The country
/// won exactly that argument an hour before this landed; the uptime had lost it
/// and nobody noticed.
///
/// The exclusions are the same shape of oversight one field over. The parser
/// calls them «the decoys» and steps over them by indentation, and the page told
/// the reader under a green tick that all of this Mac's traffic goes through the
/// VPN — while `17.0.0.0/8`, which is Apple's whole network, was declared
/// outside it.
final class TheToolKnewSinceWhenAllAlongTests: XCTestCase {

    /// The tool's own output, trimmed to what the parser reads and with every
    /// address replaced by the ranges a real configuration declares. Taken from
    /// a live `scutil --nc status` on macOS 27.
    private let connected = """
    Connected
    Extended Status <dictionary> {
      DNSServers : <array> {
        0 : 198.18.0.2
      }
      IPv4 : <dictionary> {
        ExcludedRoutes : <array> {
          0 : <dictionary> {
            DestinationAddress : 10.0.0.0
            InterfaceName : en0
            SubnetMask : 255.0.0.0
          }
          1 : <dictionary> {
            DestinationAddress : 172.16.0.0
            InterfaceName : en0
            SubnetMask : 255.240.0.0
          }
          2 : <dictionary> {
            DestinationAddress : 17.0.0.0
            InterfaceName : en0
            SubnetMask : 255.0.0.0
          }
        }
        InterfaceName : utun8
      }
      Status : 2
    }
    LastStatusChangeTime : 08/19/2026 14:57:22
    """

    // MARK: - Since when

    func testTheStampIsReadOutOfTheToolsOwnOutput() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: connected))
        let since = try XCTUnwrap(reading.since, """
            the tool wrote LastStatusChangeTime and the parser walked past it, \
            which is what left the first column empty on a Mac whose VPN starts \
            at login
            """)
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 19
        components.hour = 14; components.minute = 57; components.second = 22
        let expected = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        XCTAssertEqual(since.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1, """
            the stamp was read as \(since) — local time, because the tool writes \
            local time and this app's own log line for the same event matched it \
            to three seconds
            """)
    }

    /// **The interface still wins the way it did**, because that argument was
    /// the whole point of the parser and this change adds fields beside it.
    func testTheTunnelsOwnInterfaceStillWinsOverTheDecoys() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: connected))
        XCTAssertEqual(reading.interface, "utun8", """
            the parser answered \(reading.interface) — one of the excluded \
            routes' own interfaces, which is the false alarm this parser exists \
            to prevent
            """)
    }

    /// A tool that does not write the line, or writes it in a shape this cannot
    /// read, leaves the engine exactly where it was: with its own observation.
    /// Nil rather than a guess is what makes this change unable to subtract.
    func testAnAbsentOrUnreadableStampIsNil() throws {
        let without = connected.replacingOccurrences(
            of: "LastStatusChangeTime : 08/19/2026 14:57:22", with: "")
        XCTAssertNil(try XCTUnwrap(VPNStatusParser.reading(in: without)).since)

        let foreign = connected.replacingOccurrences(
            of: "08/19/2026 14:57:22", with: "19.08.2026, 14:57:22")
        XCTAssertNil(try XCTUnwrap(VPNStatusParser.reading(in: foreign)).since, """
            a stamp in a format this build cannot read was turned into some date \
            anyway, which is worse than none: a fabricated duration is drawn as a \
            measurement
            """)
    }

    /// **The formatter is fixed, not the reader's** — asserted on the source,
    /// because the fault it guards against cannot be reached from here.
    ///
    /// `scutil` wrote `08/19/2026 14:57:22` on the machine this was measured on,
    /// whose languages are ("ru-RU", "en-US") — so the tool is not writing the
    /// reader's format, and a formatter built on the user's locale would fail to
    /// read the tool on exactly that Mac. This target cannot switch the process
    /// locale and has no `AppLanguage` to override (the engine does not import
    /// `HelmUI`), so the running test would pass on any machine whatever the
    /// formatter said. Structural, the way `AnErasedQueryDoesNotShowOldResults`
    /// asserts that the page reads its seam.
    func testTheStampIsNotReadThroughTheReadersOwnLocale() throws {
        let parser = RepoSource.root
            .appendingPathComponent("Sources/Modules/VPN/Engine/Logic/VPNStatusParser.swift")
        let source = try String(contentsOf: parser, encoding: .utf8)
        XCTAssertTrue(source.contains("en_US_POSIX"), """
            the stamp's formatter no longer pins its locale, so it reads the             reader's format rather than the tool's
            """)
        XCTAssertFalse(source.contains("Locale.current"), "the parser reads the reader's locale")
        XCTAssertFalse(source.contains("autoupdatingCurrent"), "likewise")
    }

    // MARK: - What is not in the tunnel

    func testTheExcludedRoutesAreKeptRatherThanOnlySteppedOver() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: connected))
        XCTAssertEqual(reading.excludedRoutes.count, 3, """
            \(reading.excludedRoutes.count) exclusions were kept out of three the \
            tool declared
            """)
        XCTAssertEqual(reading.excludedRoutes.map(\.destination),
                       ["10.0.0.0", "172.16.0.0", "17.0.0.0"])
    }

    /// A destination whose dictionary the tool cut short is dropped, not paired
    /// with the next mask that happens along — which would invent a range.
    func testADestinationWithNoMaskIsNotPairedWithTheNextOne() throws {
        // **Matched without its indentation, and that matters here.** A Swift
        // multi-line literal strips the indent of its closing delimiter from
        // every line, so a pattern written with the twelve spaces the source
        // shows matches nothing in the value — the first version of this test
        // removed no line at all and then reported the parser as broken for
        // producing three routes out of three.
        let truncated = connected.replacingOccurrences(
            of: "SubnetMask : 255.240.0.0", with: "")
        XCTAssertFalse(truncated.contains("255.240.0.0"), "precondition: nothing was removed")
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: truncated))
        XCTAssertEqual(reading.excludedRoutes.map(\.destination), ["10.0.0.0", "17.0.0.0"], """
            a half-read dictionary produced \(reading.excludedRoutes.map(\.destination)) — \
            the orphaned destination took the next exclusion's mask
            """)
    }

    // MARK: - What the summary says

    func testAppleIsNamedAndTheDullRangesAreOneWord() {
        let summary = VPNExcludedRoutes.summarize([
            .init(destination: "10.0.0.0", mask: "255.0.0.0"),
            .init(destination: "192.168.0.0", mask: "255.255.0.0"),
            .init(destination: "17.0.0.0", mask: "255.0.0.0"),
        ])
        XCTAssertTrue(summary.localNetwork)
        XCTAssertTrue(summary.apple, """
            Apple's whole network was folded into the local ranges, so the one \
            exclusion worth naming is the one that reads as a printer
            """)
        XCTAssertEqual(summary.others, 0)
    }

    func testAnythingElseIsCountedRatherThanNamed() {
        let summary = VPNExcludedRoutes.summarize([
            .init(destination: "10.0.0.0", mask: "255.0.0.0"),
            .init(destination: "93.184.216.0", mask: "255.255.255.0"),
            .init(destination: "203.0.113.0", mask: "255.255.255.0"),
        ])
        XCTAssertEqual(summary.others, 2)
        XCTAssertFalse(summary.apple)
    }

    /// The ordinary tunnel, and the one that excludes nothing at all. `.none`
    /// has to be distinguishable from «the local network is excluded», or the
    /// clause appears on a configuration it is not true of.
    func testATunnelThatExcludesNothingSummarisesToNothing() {
        XCTAssertEqual(VPNExcludedRoutes.summarize([]), .none)
        XCTAssertTrue(VPNExcludedRoutes.summarize([]).isEmpty)
        XCTAssertFalse(VPNExcludedRoutes.summarize([
            .init(destination: "10.0.0.0", mask: "255.0.0.0")]).isEmpty)
    }

    /// Matched on the destination alone: a reader who excluded 10/8 with an
    /// unusual mask has still excluded the local network, which is all the word
    /// claims.
    func testTheMaskDoesNotDecideWhatARangeIs() {
        let summary = VPNExcludedRoutes.summarize([
            .init(destination: "172.16.0.0", mask: "255.255.0.0")])
        XCTAssertTrue(summary.localNetwork)
        XCTAssertEqual(summary.others, 0)
    }
}

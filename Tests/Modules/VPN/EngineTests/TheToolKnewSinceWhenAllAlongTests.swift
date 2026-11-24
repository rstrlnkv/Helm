// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_VPN_Engine

/// **`scutil` answers «since when», and what it excludes from the tunnel.**
///
/// Every status read ends with `LastStatusChangeTime`, so the page's first
/// column is known on the most ordinary Mac there is: a VPN raised at login
/// and the menu bar app started after it, where Helm's own observation has
/// nothing to say.
///
/// The exclusions sit in the same output (the parser's «decoys»). Without them
/// the page would say, under a green dot, that all of this Mac's traffic goes
/// through the VPN while `17.0.0.0/8`, Apple's whole network, is declared
/// outside it.
///
/// Guards: the since-when and exclusions the tool already printed reach the page.
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

    /// **The interface still wins**: these fields sit beside it.
    func testTheTunnelsOwnInterfaceStillWinsOverTheDecoys() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: connected))
        XCTAssertEqual(reading.interface, "utun8", """
            the parser answered \(reading.interface) — one of the excluded \
            routes' own interfaces, which is the false alarm this parser exists \
            to prevent
            """)
    }

    /// A tool that does not write the line, or writes it in a shape this cannot
    /// read, leaves the engine with its own observation: nil rather than a guess.
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
        // **Matched without its indentation.** A Swift multi-line literal strips
        // the indent of its closing delimiter from every line, so a pattern written
        // with the spaces the source shows would match nothing in the value and
        // remove no line at all.
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
            .init(destination: "10.0.0.0"),
            .init(destination: "192.168.0.0"),
            .init(destination: "17.0.0.0"),
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
            .init(destination: "10.0.0.0"),
            .init(destination: "93.184.216.0"),
            .init(destination: "203.0.113.0"),
        ])
        XCTAssertEqual(summary.others, 2)
        XCTAssertFalse(summary.apple)
    }

    /// The ordinary tunnel, and the one that excludes nothing at all. `.none`
    /// has to be distinguishable from «the local network is excluded», or the
    /// clause appears on a configuration it is not true of.
    func testATunnelThatExcludesNothingSummarisesToNothing() {
        XCTAssertEqual(VPNExcludedRoutes.summarize([]), .none)
        XCTAssertNotEqual(VPNExcludedRoutes.summarize([
            .init(destination: "10.0.0.0")]), .none)
    }
}

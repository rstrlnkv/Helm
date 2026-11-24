// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmContract
import XCTest
@testable import Module_VPN_Engine

/// **Which interface a tunnel is on is asked of `scutil`, by name.**
///
/// The dynamic store is keyed by service id, and for anything that is not a
/// classic PPP/IPSec service `scutil --nc list` names the *configuration*,
/// another identifier space: a lookup there answers nil for every
/// NetworkExtension tunnel, and the strip would be absent on every Mac. A fake
/// keyed by service id could be planted with a pair the real store cannot
/// produce (Architecture/TestsAndMeasurement.md § Fakes).
final class TheInterfaceComesFromTheToolTests: XCTestCase {

    /// `scutil --nc status "incy"` against a live NetworkExtension tunnel.
    /// Addresses replaced, structure and indentation kept exactly — **including
    /// the seven `InterfaceName : en0` decoys** the excluded routes carry before
    /// the tunnel's own line. A parser that takes the first match answers `en0`,
    /// and the verdict would read «traffic is not going through the tunnel» on a
    /// Mac where it is.
    private static let connected = """
    Connected
    Extended Status <dictionary> {
      ConnectionStatistics : <dictionary> {
        ConnectCount : 1
      }
      DNSServers : <array> {
        0 : 10.0.0.1
      }
      IPv4 : <dictionary> {
        Addresses : <array> {
          0 : 10.10.0.2
        }
        ExcludedRoutes : <array> {
          0 : <dictionary> {
            DestinationAddress : 192.0.2.0
            InterfaceName : en0
            SubnetMask : 255.255.255.0
          }
          1 : <dictionary> {
            DestinationAddress : 192.0.2.4
            InterfaceName : en0
            SubnetMask : 255.255.255.252
          }
          2 : <dictionary> {
            DestinationAddress : 192.0.2.8
            InterfaceName : en0
            SubnetMask : 255.255.255.252
          }
          3 : <dictionary> {
            DestinationAddress : 192.0.2.12
            InterfaceName : en0
            SubnetMask : 255.255.255.252
          }
          4 : <dictionary> {
            DestinationAddress : 192.0.2.16
            InterfaceName : en0
            SubnetMask : 255.255.255.252
          }
          5 : <dictionary> {
            DestinationAddress : 192.0.2.20
            InterfaceName : en0
            SubnetMask : 255.255.255.252
          }
          6 : <dictionary> {
            DestinationAddress : 192.0.2.24
            InterfaceName : en0
            SubnetMask : 255.255.255.252
          }
        }
        InterfaceName : utun8
        Router : 10.10.0.1
        ServerAddress : 198.51.100.7
      }
      IsPrimaryInterface : 1
      LastStatusChangeTime : 08/11/2026 12:40:14
      NEStatus : 3
      SessionState : 4
      Status : 2
    }
    """

    /// The same tool about a configuration that is down — every field the strip
    /// wants is simply absent. Captured from `scutil --nc status "NBCom VPN"`.
    private static let disconnected = """
    Disconnected
    Extended Status <dictionary> {
      PPP : <dictionary> {
        DeviceLastCause : 0
        LastCause : 5
        Status : 0
      }
      Status : 0
    }
    """

    // MARK: - The parser

    func testTheTunnelsOwnInterfaceIsReadPastTheExcludedRoutes() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: Self.connected))
        XCTAssertEqual(reading.interface, "utun8", """
            the parser took an excluded route's interface: seven `InterfaceName : en0` \
            lines stand before the tunnel's own, and answering «en0» makes the page \
            say the traffic goes round a tunnel it goes through
            """)
    }

    func testTheToolsOwnRoutingAnswerIsRead() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: Self.connected))
        XCTAssertEqual(reading.isPrimaryInterface, true)
    }

    /// A configuration the tool knows and cannot name an interface for: it is
    /// down, or it is coming up. Nil, never a guess.
    func testAConnectionThatIsDownNamesNoInterface() {
        XCTAssertNil(VPNStatusParser.reading(in: Self.disconnected))
    }

    /// What the tool prints for a name it does not have — and what it prints
    /// when it did not run at all.
    func testNoServiceAndSilenceAreBothNoReading() {
        XCTAssertNil(VPNStatusParser.reading(in: "No service"))
        XCTAssertNil(VPNStatusParser.reading(in: ""))
    }

    /// The flag is the tool's own and can be missing while the interface is
    /// there — the two are read separately, and neither invents the other.
    func testAReadingWithoutTheRoutingFlagStillNamesTheInterface() throws {
        let output = """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun4
          }
        }
        """
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: output))
        XCTAssertEqual(reading.interface, "utun4")
        XCTAssertNil(reading.isPrimaryInterface)
    }

    // MARK: - The engine, driven by what the tool really printed

    /// **End to end.** A connected NetworkExtension tunnel, the tool answering
    /// exactly what it answers on a real Mac, and a strip that has to appear.
    func test_a_connected_tunnel_puts_its_interface_on_the_wire() async {
        let runner = FakeRunner()
        runner.listOutput = "* (Connected) 02196763-19A0-40A0-B369-D9EA68F7F65D "
            + "VPN (llc.itdev.incy) \"incy\" [VPN:llc.itdev.incy]"
        runner.statusOutput = ["incy": Self.connected]
        let news = EngineNews<VPNEngine.StatePayload>()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun8"
        interfaces.counters = ["utun8": (in: 4_000, out: 2_000)]
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner, apps: FakeApps(),
                               news: news, interfaces: interfaces,
                               exit: FakeExit(), speed: FakeSpeed(), work: .inline)

        engine.refresh()

        let facts = await lastState(on: news)?.tunnels.first
        XCTAssertEqual(facts?.interface, "utun8", """
            the strip is absent on a Mac with a tunnel up: the interface question \
            was asked of something that cannot answer it
            """)
        XCTAssertEqual(facts?.name, "incy")
        XCTAssertEqual(facts?.exit, .throughTunnel(countryCode: nil))
    }

    /// And it is asked once per tunnel, not once per emission: `scutil` is a
    /// subprocess, and the poll behind one connect re-reads the list many times.
    func test_the_tool_is_asked_for_the_interface_once_per_tunnel() async {
        let runner = FakeRunner()
        runner.listOutput = "* (Connected) 02196763-19A0-40A0-B369-D9EA68F7F65D "
            + "VPN (llc.itdev.incy) \"incy\" [VPN:llc.itdev.incy]"
        runner.statusOutput = ["incy": Self.connected]
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun8"
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner, apps: FakeApps(),
                               interfaces: interfaces, exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.refresh()
        engine.refresh()
        engine.refresh()

        let asked = runner.issued.filter { $0.first == "--nc" && $0.dropFirst().first == "status" }
        XCTAssertEqual(asked.count, 1,
                       "\(asked.count) subprocesses for one tunnel's interface, which does not "
                       + "change while the tunnel is up: macOS makes a new utunN for the next one")
    }

    /// A tunnel that falls forgets its interface, so the next one — on a new
    /// `utunN`, which is what macOS gives it — is read again rather than drawn
    /// with its predecessor's.
    func test_a_tunnel_that_falls_is_read_again_when_it_returns() async {
        let runner = FakeRunner()
        let id = "02196763-19A0-40A0-B369-D9EA68F7F65D"
        runner.listOutput = "* (Connected) \(id) VPN (llc.itdev.incy) \"incy\" [VPN:llc.itdev.incy]"
        runner.statusOutput = ["incy": Self.connected]
        let news = EngineNews<VPNEngine.StatePayload>()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun9"
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner, apps: FakeApps(),
                               news: news, interfaces: interfaces,
                               exit: FakeExit(), speed: FakeSpeed(), work: .inline)
        engine.refresh()

        runner.listOutput = "* (Disconnected) \(id) VPN (llc.itdev.incy) \"incy\" "
            + "[VPN:llc.itdev.incy]"
        engine.refresh()
        runner.listOutput = "* (Connected) \(id) VPN (llc.itdev.incy) \"incy\" [VPN:llc.itdev.incy]"
        runner.statusOutput = ["incy": Self.connected.replacingOccurrences(of: "utun8",
                                                                           with: "utun9")]
        engine.refresh()

        let facts = await lastState(on: news)?.tunnels.first
        XCTAssertEqual(facts?.interface, "utun9", """
            the strip drew the interface of a tunnel that is gone — macOS raises \
            the next one on a new utunN, and the counters under that name are \
            somebody else's traffic
            """)
    }
}

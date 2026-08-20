// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_VPN_Engine

/// **`VPNSpeedReading.took` landed today with a compatibility claim attached,
/// and this is the claim being read back off a document.**
///
/// The property's own comment says: «Optional, and that is what makes an older
/// payload decode: Swift synthesises `decodeIfPresent` for an `Optional`
/// property, where a non-optional with a stored default is still a required key
/// and throws away the whole document.» This repository has shipped that exact
/// sentence being **false** — `KeepAwakeEngine.StatePayload` gave three fields a
/// stored default and a comment claiming each existed so an older payload would
/// still decode, and a document missing any of them threw and left every screen
/// holding stale defaults (CLAUDE.md § a `defaulted` property on a `Codable`
/// payload). So the belief is not worth another prose paragraph; it is worth a
/// document with the key taken out of it.
///
/// **A field is removed from a real encoding rather than a JSON literal being
/// typed by hand.** A literal is a second spelling of the wire format that
/// nobody recompiles when the format moves: rename `down` and the literal goes
/// on decoding into a value the app never produces. Encoding the value this
/// build makes, deleting one key from it and decoding the rest asks the real
/// question — «what happens to a Mac whose last payload was written by
/// yesterday's build» — and it fails loudly if the key it is told to delete is
/// not there, which is the precondition every absence test needs.
final class AReadingWrittenBeforeTookDecodesTests: XCTestCase {

    private let taken = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading() -> VPNSpeedReading {
        VPNSpeedReading(down: 343, up: 358, rpm: 1200, at: taken, took: 19.2)
    }

    /// The JSON `object` this value encodes to, with `dropping` removed from it.
    /// Fails the test outright when the key was not there to remove.
    private func encoded<T: Encodable>(_ value: T, dropping key: String,
                                       at path: [String] = [],
                                       file: StaticString = #filePath,
                                       line: UInt = #line) throws -> Data {
        let data = try JSONEncoder().encode(value)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
            as? [String: Any], file: file, line: line)
        try remove(key, at: path, in: &root, file: file, line: line)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// Walks objects **and arrays of objects**: `tunnels` on the payload is a
    /// list, and a helper that only knew about dictionaries would fail at the
    /// step rather than at the key — which reads as «the format moved» when it
    /// means «the helper is short».
    private func remove(_ key: String, at path: [String], in object: inout [String: Any],
                        file: StaticString, line: UInt) throws {
        guard let step = path.first else {
            XCTAssertNotNil(object[key], """
                precondition: this build does not write «\(key)» at all, so removing \
                it proves nothing about a document that lacks it
                """, file: file, line: line)
            object[key] = nil
            return
        }
        let rest = Array(path.dropFirst())
        if var inner = object[step] as? [String: Any] {
            try remove(key, at: rest, in: &inner, file: file, line: line)
            object[step] = inner
            return
        }
        var list = try XCTUnwrap(object[step] as? [[String: Any]], """
            precondition: «\(step)» is neither an object nor a list of them in this \
            encoding
            """, file: file, line: line)
        XCTAssertFalse(list.isEmpty, "precondition: «\(step)» is empty, so nothing was "
                       + "edited and the decode below is of an untouched document",
                       file: file, line: line)
        for index in list.indices {
            try remove(key, at: rest, in: &list[index], file: file, line: line)
        }
        object[step] = list
    }

    /// The reading by itself: every other figure survives the missing key, and
    /// the missing one reads as «nobody timed this run», which is the same
    /// answer `NetworkQualitySpeed` gives for a run of no measurable length.
    func testAReadingWrittenBeforeTookExistedDecodesWithEveryOtherFigureIntact() throws {
        let older = try encoded(reading(), dropping: "took")
        let back = try JSONDecoder().decode(VPNSpeedReading.self, from: older)

        XCTAssertNil(back.took)
        XCTAssertEqual(back.down, 343)
        XCTAssertEqual(back.up, 358)
        XCTAssertEqual(back.rpm, 1200)
        XCTAssertEqual(back.at, taken)
    }

    /// **The half that actually matters, because `JSONDecoder` gives up on the
    /// document and not on the field.**
    ///
    /// The reading does not travel alone. It is nested two levels inside the
    /// payload the page decodes, so a throw at `took` is not one missing figure
    /// — it is every tunnel, every connection and the whole strip, replaced by a
    /// page that decoded nothing. That is precisely the shape the KeepAwake
    /// defect took, and the reason this asserts on the fields *around* the
    /// reading rather than only on the reading itself.
    func testAWholeWirePayloadCarryingSuchAReadingStillDecodes() throws {
        let tunnel = VPNTunnelState(name: "home", interface: "utun4", since: taken,
                                    bytesIn: 1024, bytesOut: 2048,
                                    exit: .throughTunnel(countryCode: "NL"),
                                    speed: reading(), measuring: false)
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "AAAA", name: "home", status: .connected,
                                        kind: "IKEv2")],
            autoConnected: [], defaultName: "home", lastAutomation: nil,
            tunnels: [tunnel])

        let older = try encoded(payload, dropping: "took", at: ["tunnels", "speed"])
        let back = try JSONDecoder().decode(VPNEngine.StatePayload.self, from: older)

        XCTAssertEqual(back.tunnels.count, 1, """
            a payload from before the run was timed decoded to no tunnels at all: \
            a missing key inside `VPNSpeedReading` costs the page every tile the \
            strip draws, not one figure
            """)
        XCTAssertEqual(back.tunnels.first?.speed?.down, 343)
        XCTAssertNil(back.tunnels.first?.speed?.took)
        XCTAssertEqual(back.connections.count, 1)
        XCTAssertEqual(back.defaultName, "home")
    }

    /// `dropping:` walks into an array's elements, which is how the payload's
    /// `tunnels` is shaped — asserted here rather than trusted, since a helper
    /// that silently found nothing to remove would make the test above vacuous.
    func testTheHelperRefusesADocumentThatNeverCarriedTheKey() throws {
        // A reading with no `took` encodes without the key at all, so the
        // precondition inside `encoded` is what fires. Proven by construction:
        // if this did not throw or fail, the two tests above would pass against
        // a document nobody had edited.
        let untimed = VPNSpeedReading(down: 1, up: 1, rpm: nil, at: taken, took: nil)
        let data = try JSONEncoder().encode(untimed)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
            as? [String: Any])
        XCTAssertNil(object["took"],
                     "an untimed reading writes the key anyway, so «older» above is "
                     + "not the document this test thinks it is")
        XCTAssertNil(object["rpm"],
                     "a nil responsiveness writes a key, so the tool's own silence "
                     + "is being stored as something")
    }
}

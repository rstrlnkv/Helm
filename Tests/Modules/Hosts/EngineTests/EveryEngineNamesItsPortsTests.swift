import XCTest
import HelmTestSupport
@testable import Module_Hosts_Engine

/// **A construction that forgets a port is an integration test nobody meant to
/// write**, and this module has five ports that reach real files: `/etc/hosts`,
/// the support folder, `~/.ssh/config`, `~/.ssh` itself and `~/.ssh/known_hosts`.
///
/// The lesson is Autopilot's: eleven of its tests took a default argument
/// naming the Mac's own keychain and rolled the owner's real rules back. Here
/// the same slip would have every engine test read the owner's `known_hosts`,
/// and `applyKnownHosts` would write it.
///
/// Derived from the source rather than from a list beside a list: every
/// `HostsEngine(` under this module's tests is a subject, so a construction
/// added later cannot quietly take a default.
final class EveryEngineNamesItsPortsTests: XCTestCase {

    private static let required = ["file:", "privileged:", "backups:", "sshConfig:",
                                   "knownHosts:", "keys:", "agent:"]

    func testEveryConstructionInTheseTestsNamesEveryPort() throws {
        let root = RepoSource.root.appendingPathComponent("Tests/Modules/Hosts")
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            // Not this file. It names `HostsEngine(` in prose, and a guard that
            // reads itself reports its own documentation as an offender.
            .filter { !$0.hasSuffix("EveryEngineNamesItsPortsTests.swift") }
        var constructions = 0
        var offenders: [String] = []

        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative),
                                  encoding: .utf8)
            for call in Self.calls(in: text) {
                constructions += 1
                let missing = Self.required.filter { !call.contains($0) }
                if !missing.isEmpty {
                    offenders.append("\(relative): \(missing.joined(separator: " "))")
                }
            }
        }

        XCTAssertGreaterThanOrEqual(constructions, 5, """
            the scan found \(constructions) constructions of `HostsEngine` in this module's \
            tests — there are more than that, so the walk or the match has stopped reading and \
            this check is guarding nothing.
            """)
        XCTAssertEqual(offenders.sorted(), [], """
            these constructions take a default argument for a port, which reaches the real file \
            on this Mac — `/etc/hosts`, the support folder, `~/.ssh/config`, `~/.ssh` or \
            `~/.ssh/known_hosts`:
            \(offenders.sorted().joined(separator: "\n"))
            """)
    }

    /// Every `HostsEngine(…)` call, balanced by counting brackets rather than
    /// by a regular expression — the arguments nest two deep in places, and a
    /// pattern that stopped at the first `)` matched nothing at all when this
    /// check was first written, which is a scan that passes by reading nothing.
    private static func calls(in text: String) -> [String] {
        var found: [String] = []
        var search = text.startIndex..<text.endIndex
        while let start = text.range(of: "HostsEngine(", range: search) {
            var depth = 0
            var index = text.index(before: start.upperBound)
            while index < text.endIndex {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                index = text.index(after: index)
            }
            let end = index < text.endIndex ? text.index(after: index) : text.endIndex
            found.append(String(text[start.lowerBound..<end]))
            search = end..<text.endIndex
        }
        return found
    }
}

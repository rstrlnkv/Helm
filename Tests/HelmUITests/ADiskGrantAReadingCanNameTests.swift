import XCTest
import SwiftUI
import AppKit
import HelmRuntime
@testable import HelmUI

/// **A page's reading of Full Disk Access is a value, or it is this Mac.**
///
/// `helmTracksFullDiskAccess` asked `PermissionCheck.fullDiskAccess()` and
/// nothing else, so the 61 pt banner five settings pages draw appeared or not
/// according to the grants of whichever process rendered them — a terminal, CI,
/// somebody else's laptop. `HelmGrants.accessibility` already existed for exactly
/// that reason on the other grant; this is its twin.
///
/// Both directions are asserted, and that pair is what makes the check able to
/// fail: this Mac answers one of the two, so a modifier that ignored the override
/// would pass one test and fail the other whatever the machine holds.
@MainActor
final class ADiskGrantAReadingCanNameTests: XCTestCase {

    /// What the modifier wrote, or nil for «it never answered» — the two states
    /// a `PermissionState` alone cannot tell apart, since `.denied` is both a
    /// reading and the value a probe that never ran would leave behind.
    @MainActor private final class Answer {
        var state: PermissionState?
    }

    private struct Probe: View {
        let answer: Answer

        var body: some View {
            // The getter is never read for a decision — the modifier only ever
            // writes — so nil means the `.task` has not landed.
            Color.clear.helmTracksFullDiskAccess(Binding(get: { answer.state ?? .denied },
                                                        set: { answer.state = $0 }))
        }
    }

    private func reading(granting grants: HelmGrants) -> PermissionState? {
        let answer = Answer()
        let host = NSHostingView(rootView: Probe(answer: answer)
            .frame(width: 100, height: 100)
            .environment(\.helmGrants, grants))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<200 where answer.state == nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return answer.state
    }

    func testAWithheldDiskGrantIsWhatTheReadingSays() {
        XCTAssertEqual(reading(granting: HelmGrants(fullDisk: .denied)), .denied,
                       "the page asked this Mac instead of the reading it was given, so the "
                       + "Full Disk Access banner is on the page or not by the grants of "
                       + "whichever process drew it")
    }

    func testAGrantedDiskGrantIsWhatTheReadingSays() {
        XCTAssertEqual(reading(granting: HelmGrants(fullDisk: .granted)), .granted,
                       "the page asked this Mac instead of the reading it was given")
    }
}

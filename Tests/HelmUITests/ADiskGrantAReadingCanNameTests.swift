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
///
/// The rows under the mark «A holder that can say «not read»» are a second group:
/// each hands one of the three trackers (`helmTracksAccessibility`,
/// `helmTracksFullDiskAccess`, `helmTracksScreenRecording`) a
/// `Binding<PermissionState?>` under that tracker's own modifier name. The holder
/// is nil until the tracker's first answer and takes the reading's answer then,
/// is put back on nil before the app comes back to the front and again before
/// the `alsoOn:` notification and takes the answer after each, and no write the
/// tracker makes is nil. Each tracker's optional overload is wired on its own,
/// and a change to one turns red only that tracker's row: an overload that
/// writes nothing or the wrong state fails on the answer that is missing or wrong, a
/// tracker that loses one of the two re-reads fails on the missing write after
/// it, and one that writes nil fails on the nil among the writes.
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
            // writes — so nil means the `.task` has not landed. The binding
            // names its type: it is the non-optional holder that these two rows
            // are about, whatever other bindings the modifier accepts.
            Color.clear.helmTracksFullDiskAccess(
                Binding<PermissionState>(get: { answer.state ?? .denied },
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

    // MARK: A holder that can say «not read»

    /// A `PermissionState?` that starts on nil, and every value the modifier
    /// wrote into it, nil or not, in order.
    @MainActor private final class OptionalHolder {
        var state: PermissionState?
        var writes: [PermissionState?] = []
    }

    /// One tracker, handed an optional holder under its own modifier name:
    /// nil before the first answer, the reading's answer after it, and the
    /// answer again after each of the two moments the tracker re-reads at —
    /// `didBecomeActiveNotification` and the `alsoOn:` name. The holder is put
    /// back on nil before each moment, and has to stay there until the moment
    /// is posted. Every write the tracker made is recorded, and none is nil.
    private func assertAnOptionalHolderIsNilUntilTheFirstAnswer(
        _ tracker: String,
        reading grants: (PermissionState) -> HelmGrants,
        track: (Binding<PermissionState?>, Notification.Name) -> AnyView,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for answer in [PermissionState.denied, .granted] {
            let extra = Notification.Name("ADiskGrantAReadingCanNameTests.\(UUID())")
            let holder = OptionalHolder()
            let binding = Binding<PermissionState?>(
                get: { holder.state },
                set: { holder.writes.append($0); holder.state = $0 })
            let host = NSHostingView(rootView: track(binding, extra)
                .frame(width: 100, height: 100)
                .environment(\.helmGrants, grants(answer)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }

            XCTAssertNil(holder.state,
                         "\(tracker): the holder is not nil before the first answer",
                         file: file, line: line)
            XCTAssertTrue(holder.writes.isEmpty,
                          "\(tracker): the tracker wrote before the first answer",
                          file: file, line: line)

            func spin(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
                let end = Date().addingTimeInterval(seconds)
                while !done() && Date() < end {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
            }

            spin(2) { holder.state != nil }
            XCTAssertEqual(holder.state, answer,
                           "\(tracker) under a reading of \(answer): the first answer never "
                           + "reached the optional holder",
                           file: file, line: line)

            let moments: [(String, Notification.Name)] = [
                ("the app coming back", NSApplication.didBecomeActiveNotification),
                ("the alsoOn notification", extra),
            ]
            for (moment, name) in moments {
                holder.state = nil
                let written = holder.writes.count
                spin(0.1)
                XCTAssertNil(holder.state,
                             "\(tracker) wrote on its own before \(moment)",
                             file: file, line: line)
                NotificationCenter.default.post(name: name, object: nil)
                spin(2) { holder.state != nil }
                XCTAssertEqual(holder.state, answer,
                               "\(tracker) under a reading of \(answer): the holder is "
                               + "\(String(describing: holder.state)) after \(moment)",
                               file: file, line: line)
                XCTAssertGreaterThan(holder.writes.count, written,
                                     "\(tracker): no write after \(moment)",
                                     file: file, line: line)
            }

            XCTAssertGreaterThanOrEqual(holder.writes.count, 3,
                                        "\(tracker): the first answer and the two moments are "
                                        + "three writes at least, got \(holder.writes)",
                                        file: file, line: line)
            XCTAssertFalse(holder.writes.contains { $0 == nil },
                           "\(tracker) under a reading of \(answer) wrote nil into the holder: "
                           + "\(holder.writes)",
                           file: file, line: line)
        }
    }

    func testAccessibilityFillsAnOptionalHolderAndNeverEmptiesIt() {
        assertAnOptionalHolderIsNilUntilTheFirstAnswer(
            "helmTracksAccessibility",
            reading: { HelmGrants(accessibility: $0) },
            track: { AnyView(Color.clear.helmTracksAccessibility($0, alsoOn: $1)) })
    }

    func testTheDiskGrantFillsAnOptionalHolderAndNeverEmptiesIt() {
        assertAnOptionalHolderIsNilUntilTheFirstAnswer(
            "helmTracksFullDiskAccess",
            reading: { HelmGrants(fullDisk: $0) },
            track: { AnyView(Color.clear.helmTracksFullDiskAccess($0, alsoOn: $1)) })
    }

    func testScreenRecordingFillsAnOptionalHolderAndNeverEmptiesIt() {
        assertAnOptionalHolderIsNilUntilTheFirstAnswer(
            "helmTracksScreenRecording",
            reading: { HelmGrants(screenRecording: $0) },
            track: { AnyView(Color.clear.helmTracksScreenRecording($0, alsoOn: $1)) })
    }
}

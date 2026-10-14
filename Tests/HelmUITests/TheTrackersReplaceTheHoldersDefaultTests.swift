import XCTest
import SwiftUI
import AppKit
import HelmRuntime
@testable import HelmUI

/// **A tracker's answer replaces whatever its holder started with, at each of
/// the three moments the tracker reads.**
///
/// A settings page declares `@State private var diskAccess: PermissionState =
/// .granted` and hands a binding of it to `helmTracksFullDiskAccess` (or its
/// Accessibility and Screen Recording twins). The page draws the banner off that
/// state, so it draws by the declared default until the tracker's first write and
/// by the answer after it. What each row asserts is the write, from a holder that
/// starts on the opposite of the answer:
///
/// - the first answer, as the page appears;
/// - the answer again when `NSApplication.didBecomeActiveNotification` arrives;
/// - the answer again when the notification named in `alsoOn:` arrives.
///
/// Each runs under `HelmGrants` naming the answer, in both directions, so a
/// tracker that ignored the default and wrote a fixed value (always `.denied`,
/// always `.granted`) fails one of the two. The reading is the only source of
/// the answer here: this Mac's own grants are never consulted.
///
/// The holder is put back on its default before each re-read, and the row waits
/// a moment to see that it stays there until the notification is posted, so a
/// change that follows the post is the post's.
///
/// Every binding is typed `Binding<PermissionState>`, the non-optional holder.
@MainActor
final class TheTrackersReplaceTheHoldersDefaultTests: XCTestCase {

    /// The three trackers, by the grant each reads and the modifier that keeps it.
    private enum Grant {
        case accessibility, fullDisk, screenRecording

        func reading(_ state: PermissionState) -> HelmGrants {
            switch self {
            case .accessibility: return HelmGrants(accessibility: state)
            case .fullDisk: return HelmGrants(fullDisk: state)
            case .screenRecording: return HelmGrants(screenRecording: state)
            }
        }

        @MainActor
        func track(_ binding: Binding<PermissionState>, alsoOn extra: Notification.Name?) -> AnyView {
            switch self {
            case .accessibility:
                return AnyView(Color.clear.helmTracksAccessibility(binding, alsoOn: extra))
            case .fullDisk:
                return AnyView(Color.clear.helmTracksFullDiskAccess(binding, alsoOn: extra))
            case .screenRecording:
                return AnyView(Color.clear.helmTracksScreenRecording(binding, alsoOn: extra))
            }
        }
    }

    private enum Moment: String {
        case theAppComesBack = "Helm came back to the front"
        case theExtraNotification = "the alsoOn notification arrived"
    }

    /// The state a page declares, and everything the tracker wrote into it.
    @MainActor private final class Holder {
        let start: PermissionState
        var state: PermissionState
        var writes: [PermissionState] = []

        init(startingAt start: PermissionState) {
            self.start = start
            self.state = start
        }
    }

    private static func other(_ state: PermissionState) -> PermissionState {
        state == .granted ? .denied : .granted
    }

    /// Runs `body` while a tracker of `grant` is on a view in an unshown window,
    /// under a reading that says `answer`, over a holder that starts on the
    /// other state.
    private func hosted(_ grant: Grant, answering answer: PermissionState,
                        alsoOn extra: Notification.Name? = nil,
                        _ body: (Holder) -> Void) {
        let holder = Holder(startingAt: Self.other(answer))
        let binding = Binding<PermissionState>(
            get: { holder.state },
            set: { holder.writes.append($0); holder.state = $0 })
        let host = NSHostingView(rootView: grant.track(binding, alsoOn: extra)
            .frame(width: 100, height: 100)
            .environment(\.helmGrants, grant.reading(answer)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        body(holder)
    }

    /// Turns the run loop until `done`, for two seconds at most.
    private func settle(until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(2)
        while !done() && Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return done()
    }

    private func idle(for seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func assertTheFirstAnswerReplacesTheDefault(of grant: Grant,
                                                        file: StaticString = #filePath,
                                                        line: UInt = #line) {
        for answer in [PermissionState.denied, .granted] {
            hosted(grant, answering: answer) { holder in
                let landed = settle { holder.state == answer }
                XCTAssertTrue(landed,
                              "\(grant) under a reading of \(answer): the holder still says "
                              + "\(holder.state) after two seconds (it started on \(holder.start); "
                              + "the tracker wrote \(holder.writes))",
                              file: file, line: line)
                XCTAssertFalse(holder.writes.isEmpty,
                               "\(grant) under a reading of \(answer): the tracker wrote nothing",
                               file: file, line: line)
            }
        }
    }

    private func assertAMomentWritesAgain(of grant: Grant, _ moment: Moment,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) {
        for answer in [PermissionState.denied, .granted] {
            let extra = Notification.Name("TheTrackersReplaceTheHoldersDefaultTests.\(UUID())")
            let name: Notification.Name
            switch moment {
            case .theAppComesBack: name = NSApplication.didBecomeActiveNotification
            case .theExtraNotification: name = extra
            }
            hosted(grant, answering: answer,
                   alsoOn: moment == .theExtraNotification ? extra : nil) { holder in
                // The first answer has to have landed, or "written again" has no
                // first write to be again of.
                guard settle(until: { holder.state == answer }) else {
                    XCTFail("\(grant) under a reading of \(answer): the first answer never landed",
                            file: file, line: line)
                    return
                }
                holder.state = holder.start
                let written = holder.writes.count

                idle(for: 0.1)
                XCTAssertEqual(holder.state, holder.start,
                               "\(grant) wrote on its own before \(moment.rawValue)",
                               file: file, line: line)
                XCTAssertEqual(holder.writes.count, written,
                               "\(grant) wrote on its own before \(moment.rawValue)",
                               file: file, line: line)

                NotificationCenter.default.post(name: name, object: nil)
                let landed = settle { holder.state == answer }
                XCTAssertTrue(landed,
                              "\(grant) under a reading of \(answer): the holder still says "
                              + "\(holder.state) after \(moment.rawValue), so the tracker did "
                              + "not read again at that moment",
                              file: file, line: line)
                XCTAssertGreaterThan(holder.writes.count, written,
                                     "\(grant) under a reading of \(answer): no write after "
                                     + "\(moment.rawValue)",
                                     file: file, line: line)
            }
        }
    }

    func testAccessibilitysFirstAnswerReplacesTheDefault() {
        assertTheFirstAnswerReplacesTheDefault(of: .accessibility)
    }

    func testTheDiskGrantsFirstAnswerReplacesTheDefault() {
        assertTheFirstAnswerReplacesTheDefault(of: .fullDisk)
    }

    func testScreenRecordingsFirstAnswerReplacesTheDefault() {
        assertTheFirstAnswerReplacesTheDefault(of: .screenRecording)
    }

    func testAccessibilityReadsAgainWhenTheAppComesBack() {
        assertAMomentWritesAgain(of: .accessibility, .theAppComesBack)
    }

    func testTheDiskGrantReadsAgainWhenTheAppComesBack() {
        assertAMomentWritesAgain(of: .fullDisk, .theAppComesBack)
    }

    func testScreenRecordingReadsAgainWhenTheAppComesBack() {
        assertAMomentWritesAgain(of: .screenRecording, .theAppComesBack)
    }

    func testAccessibilityReadsAgainOnTheExtraNotification() {
        assertAMomentWritesAgain(of: .accessibility, .theExtraNotification)
    }

    func testTheDiskGrantReadsAgainOnTheExtraNotification() {
        assertAMomentWritesAgain(of: .fullDisk, .theExtraNotification)
    }

    func testScreenRecordingReadsAgainOnTheExtraNotification() {
        assertAMomentWritesAgain(of: .screenRecording, .theExtraNotification)
    }
}

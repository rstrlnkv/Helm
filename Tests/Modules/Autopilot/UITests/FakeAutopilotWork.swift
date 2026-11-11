import Foundation
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The engine's door as the model sees it, standing for the engine and nothing else.
///
/// **Carries the engine's states only.** Four things the rule store can be in (valid,
/// empty, absent, refused) and the history it keeps; no lost-reply state (a refused
/// send, an empty reply) because the door has none: every answer is a return, and
/// a state the real engine cannot be in would let a test pass for the fake's reasons.
///
/// A save over a refused status is not held, the rule `SealedRules.write` keeps: a
/// fake that stored it would tell the model its own save had landed.
///
/// `calls` records the member names in order, so a test can assert that a gesture
/// really reached the engine before asserting what was said about it, and that a
/// stopped model reached it no more.
final class FakeAutopilotWork: AutopilotWork, @unchecked Sendable {

    private let lock = NSLock()
    private var folders: [WatchedFolder]
    private var status: AutopilotStatus
    private var history: [ActionRecord]
    private let preview: [PreviewRow]
    private var report: SweepReport?
    private var seen: [String] = []
    private var savedLists: [[WatchedFolder]] = []
    private var asked: WatchedFolder?

    init(folders: [WatchedFolder] = [],
         status: AutopilotStatus = AutopilotStatus(refusal: nil),
         history: [ActionRecord] = [],
         preview: [PreviewRow] = [],
         report: SweepReport? = nil) {
        self.folders = folders
        self.status = status
        self.history = history
        self.preview = preview
        self.report = report
    }

    // The engine changing under the model.
    func holds(_ next: [WatchedFolder]) { lock.withLock { folders = next } }
    func answers(_ next: AutopilotStatus) { lock.withLock { status = next } }
    func holdsHistory(_ next: [ActionRecord]) { lock.withLock { history = next } }

    // What the model did.
    var calls: [String] { lock.withLock { seen } }
    var saved: [[WatchedFolder]] { lock.withLock { savedLists } }
    var previewed: WatchedFolder? { lock.withLock { asked } }
    func count(_ name: String) -> Int { lock.withLock { seen.filter { $0 == name }.count } }

    private func note(_ name: String) { lock.withLock { seen.append(name) } }

    func readFolders() async -> [WatchedFolder] { lock.withLock { seen.append("readFolders"); return folders } }
    func readStatus() async -> AutopilotStatus { lock.withLock { seen.append("readStatus"); return status } }
    func readHistory() async -> [ActionRecord] { lock.withLock { seen.append("readHistory"); return history } }

    func save(_ list: [WatchedFolder]) async {
        lock.withLock {
            seen.append("save")
            savedLists.append(list)
            if status.refusal == nil { folders = list }
        }
    }

    func dropRefusedRules() async { note("dropRefusedRules") }
    func dropHistory() async { lock.withLock { seen.append("dropHistory"); history = [] } }

    func dryRun(_ draft: WatchedFolder) async -> [PreviewRow] {
        lock.withLock { seen.append("dryRun"); asked = draft; return preview }
    }

    func sweepNow(folderID: String) async -> SweepReport? {
        lock.withLock { seen.append("sweepNow"); return report }
    }

    func putBack(record id: String) async -> UndoReport {
        lock.withLock { seen.append("putBack(record:)") }
        return UndoReport(lines: [])
    }

    func putBack(run id: String) async -> UndoReport {
        lock.withLock { seen.append("putBack(run:)") }
        return UndoReport(lines: [])
    }
}

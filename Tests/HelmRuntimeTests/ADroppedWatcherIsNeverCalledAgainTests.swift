import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What a dropped `FolderWatcher` leaves behind: is its change callback called
/// again, and does the object the stream holds leave memory?
///
/// The stream's context is a `FolderWatcher.Sink`, which the stream retains, and
/// never the watcher. The watcher's `deinit` runs on whichever thread dropped
/// the last reference: it clears the sink's action there and puts one block on
/// the watcher's queue that stops and releases the stream, behind whatever is
/// running on that queue. Three cases, all deterministic, one per thing that
/// follows from that:
/// - **a delivery behind a held callback calls nothing once the watcher is
///   dropped**, whether the drop came while the second write's delivery was due
///   or before the write was made (with a control that shows the same delivery
///   does reach the callback when the watcher is not dropped), and the sink is
///   gone within a second of the gate opening;
/// - **the sink leaves memory within a second of the drop**, whatever the stream
///   was doing: never started, live, live after a delivery, replaced, stopped
///   (read through a weak reference to `FolderWatcher.sink`);
/// - **a callback in flight does not hold the watcher**, which is gone as the
///   drop returns, while the sink stays until the callback has ended and the
///   queue has run the block.
///
/// **What this family holds**, found by taking each part of the teardown out of
/// `FolderWatcher.swift` and running it: the block `deinit` puts on the queue
/// (red in all three cases wherever a stream was live at the drop, on the sink
/// still being in memory) and the context's release callback (red in the same
/// places, and in the stopped shape too). Both are held in one direction only:
/// that the sink leaves memory.
///
/// **What it does not hold**; each of these left the family green when it was
/// done to the code:
/// - the clear of the action in `deinit`. Without it the second call did not
///   begin in either kind of the first case: no case here has a delivery begin
///   between the end of `deinit` and the block it queued;
/// - the context's retain callback, with the release callback taken out beside
///   it. The block `deinit` queues holds the sink through the stop, and no
///   delivery comes after a stop, so nothing here reads what the stream's own
///   hold on the sink is for;
/// - which thread stops the stream. With `deinit` stopping it itself, instead of
///   queueing the block, all three cases stayed green.
///
/// So of a drop that lands while a callback is running, which is where the doc
/// comment of `FolderWatcher.Sink` puts the danger, this family holds one
/// thing: that the sink leaves memory afterwards.
///
/// `HELM_PROBE_SCALE=N` multiplies the rounds of each case by N, and the run's
/// length with it. A default run of the family takes about ten seconds; every
/// wait in it has a deadline of its own.
///
/// **What counts as a call after the drop:** a call of `onChange` that began at
/// or after the clock read just before the dropping assignment.
final class ADroppedWatcherIsNeverCalledAgainTests: XCTestCase {

    /// More rounds for a longer run: `HELM_PROBE_SCALE=4` is four times as many.
    private let scale = max(1, Int(ProcessInfo.processInfo.environment["HELM_PROBE_SCALE"] ?? "") ?? 1)
    private let batch = 20

    // MARK: - a delivery waiting behind a held callback

    func testNoDeliveryBehindAHeldCallbackCallsAnythingOnceTheWatcherIsDropped() {
        let root = scratchDirectory("watcher-deinit-waiting")
        var rounds: [ProbeRound] = []
        for _ in 0..<(2 * scale) {
            rounds += inParallel(30, deadline: 40) { i in
                gatedRound(i, root: root, kind: GatedKind.allCases[i % GatedKind.allCases.count])
            }
        }
        let wanted = 20 * scale

        // The control: the same timeline, nothing dropped. Its second call has
        // to come, and to come straight after the gate opens, or the dropped
        // rounds below had no second delivery to lose.
        let control = rounds.filter { $0.tag == GatedKind.nothingDropped.rawValue }
        let afterGate = control.compactMap { $0.secondCallAfterGateMs }.sorted()
        let waiting = afterGate.filter { $0 < 300 }.count
        print("[waiting control, nothing dropped] rounds \(control.count) of \(wanted) · second call seen in \(afterGate.count) · began within 300 ms of the gate opening: \(waiting) · ms after the gate opened: \(quantiles(afterGate))")
        XCTAssertGreaterThanOrEqual(control.count, wanted * 8 / 10,
            "precondition: too few control rounds ran (\(control.count) of \(wanted))")
        XCTAssertGreaterThanOrEqual(waiting, control.count * 8 / 10,
            "precondition: the second delivery did not begin within 300 ms of the gate opening in \(control.count - waiting) of \(control.count) control rounds, so a dropped round below says nothing")

        // The same timeline with the last reference dropped, in each of the two
        // places it can be dropped while the held call keeps the queue.
        for kind in GatedKind.allCases where kind != .nothingDropped {
            let dropped = rounds.filter { $0.tag == kind.rawValue }
            let calls = dropped.map { $0.calls.count }
            let afterTheDrop = dropped.map { $0.callsBeganAfterTheDrop }.reduce(0, +)
            let gone = dropped.compactMap { $0.sinkGoneAfterGateMs }.sorted()
            print("[waiting, \(kind.rawValue)] rounds \(dropped.count) of \(wanted) · both writes made in \(dropped.filter { $0.writesMade == 2 }.count) · the watcher was gone as the drop returned in \(dropped.filter { $0.droppedLast == true }.count) · calls seen per round: \(Set(calls).sorted()) · calls that began after the drop began: \(afterTheDrop) · sink gone within 1 s of the gate opening in \(gone.count), ms: \(quantiles(gone))")
            XCTAssertGreaterThanOrEqual(dropped.count, wanted * 8 / 10,
                "precondition, \(kind.rawValue): too few dropped rounds ran (\(dropped.count) of \(wanted))")
            XCTAssertEqual(dropped.filter { $0.writesMade == 2 }.count, dropped.count,
                "precondition, \(kind.rawValue): a round did not make both writes, so it had no second delivery")
            XCTAssertEqual(dropped.filter { $0.droppedLast == true }.count, dropped.count,
                "\(kind.rawValue): the watcher outlived its drop in a round, so the drop was not the last reference")
            XCTAssertEqual(dropped.filter { $0.calls.count == 1 }.count, dropped.count,
                "\(kind.rawValue): a dropped round saw a number of calls other than the one held call; calls per round: \(calls)")
            XCTAssertEqual(afterTheDrop, 0,
                "\(kind.rawValue): onChange was called by a delivery after the watcher was dropped")
            XCTAssertEqual(gone.count, dropped.count,
                "\(kind.rawValue): the sink was still in memory a second after the gate opened in \(dropped.count - gone.count) of \(dropped.count) rounds")
        }
    }

    // MARK: - the sink leaves memory

    func testTheSinkLeavesMemoryWithinASecondOfTheDropWhateverTheStreamWasDoing() {
        let root = scratchDirectory("watcher-deinit-sink")
        for shape in SinkShape.allCases {
            var rounds: [ProbeRound] = []
            for _ in 0..<scale {
                rounds += inParallel(10, deadline: 30) { i in sinkRound(i, root: root, shape: shape) }
            }
            let wanted = 10 * scale
            let gone = rounds.compactMap { $0.sinkGoneAfterDropMs }.sorted()
            print("[sink, \(shape.label)] rounds \(rounds.count) of \(wanted) · sink alive just before the drop \(rounds.filter { $0.sinkAliveBeforeDrop == true }.count) · gone within 1 s of the drop \(gone.count) · ms until gone: \(quantiles(gone))")
            XCTAssertEqual(rounds.count, wanted, "\(shape.label): a round did not run to the drop")
            XCTAssertEqual(rounds.filter { $0.sinkAliveBeforeDrop == true }.count, rounds.count,
                "precondition, \(shape.label): the weak reference did not read the sink just before the drop, so nil afterwards means nothing")
            XCTAssertEqual(gone.count, rounds.count,
                "\(shape.label): the sink was still in memory a second after the watcher was dropped in \(rounds.count - gone.count) of \(rounds.count) rounds")
        }
    }

    // MARK: - a callback in flight

    func testACallbackInFlightDoesNotHoldTheWatcherAndTheSinkOutlivesItsHold() {
        let root = scratchDirectory("watcher-deinit-inflight")
        let hold = 0.4
        var rounds: [ProbeRound] = []
        for _ in 0..<(2 * scale) {
            rounds += inParallel(batch, deadline: 30) { i in inFlightRound(i, root: root, hold: hold) }
        }
        let wanted = 2 * scale * batch
        let gone = rounds.compactMap { $0.sinkGoneAfterGateMs }.sorted()
        print("[in flight, hold \(Int(hold * 1000)) ms] rounds \(rounds.count) of \(wanted) · the watcher was gone as the drop returned in \(rounds.filter { $0.droppedLast == true }.count) · the sink was in memory at the end of the hold in \(rounds.filter { $0.sinkAliveAtEndOfHold == true }.count) · the held call ended in \(rounds.filter { ($0.calls.first?.ended ?? 0) != 0 }.count) · sink gone within 1 s of the gate opening in \(gone.count), ms: \(quantiles(gone))")
        XCTAssertEqual(rounds.count, wanted, "a round did not reach its drop")
        XCTAssertEqual(rounds.filter { $0.calls.count == 1 }.count, rounds.count,
            "precondition: a round did not have exactly the one held call in flight at the drop")
        XCTAssertEqual(rounds.filter { $0.droppedLast == true }.count, rounds.count,
            "a callback in flight held the watcher: it was still in memory when the drop returned")
        XCTAssertEqual(rounds.filter { $0.sinkAliveAtEndOfHold == true }.count, rounds.count,
            "the sink left memory while a callback was still running on the watcher's queue")
        XCTAssertEqual(rounds.filter { ($0.calls.first?.ended ?? 0) != 0 }.count, rounds.count,
            "the held call did not run to its end")
        XCTAssertEqual(gone.count, rounds.count,
            "the sink was still in memory a second after the held call ended in \(rounds.count - gone.count) of \(rounds.count) rounds")
    }
}

// MARK: - the clock

private func probeNow() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

private func millis(_ from: UInt64, _ to: UInt64) -> Double {
    Double(Int64(bitPattern: to &- from)) / 1_000_000
}

/// Sleeps most of the way and spins the last 1.5 ms, so the moment of a drop is
/// not the scheduler's.
private func wait(until target: UInt64) {
    while true {
        let t = probeNow()
        if t >= target { return }
        let rest = target - t
        if rest > 2_500_000 { Thread.sleep(forTimeInterval: Double(rest - 1_500_000) / 1e9) }
    }
}

private func quantiles(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "n=0" }
    let s = values.sorted()
    func at(_ p: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * p + 0.5))] }
    return String(format: "n=%d min %.3f p10 %.3f median %.3f p90 %.3f max %.3f",
                  s.count, s[0], at(0.1), at(0.5), at(0.9), s[s.count - 1])
}

// MARK: - the pieces

private final class ProbeCollected<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

private final class ProbeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
}

/// A child process that appends a byte to one file each time it reads a line
/// on its standard input. It lives from before the round's clock starts, so
/// the write is not delayed by a launch.
private final class ProbeWriter: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let gone = DispatchSemaphore(value: 0)
    let started: Bool

    init(file: String) {
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while read -r line; do printf x >> \"$1\"; done", "sh", file]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let gone = self.gone
        process.terminationHandler = { _ in gone.signal() }
        started = HelmProcess.start(process, path: "/bin/sh")
    }

    /// Writes one line to the child, which appends a byte to the file.
    func trigger() {
        try? input.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
    }

    func finish() {
        try? input.fileHandleForWriting.close()
        if gone.wait(timeout: .now() + 5) == .timedOut { process.terminate() }
    }
}

/// One watcher over one folder, which this object holds in `only`, and
/// everything that happened to both.
private final class ProbeRound: @unchecked Sendable {
    struct Call {
        let began: UInt64
        var ended: UInt64 = 0
    }

    /// When there is one, the first call waits on it (for at most 20 s) before
    /// it returns, so the queue stays held until the round opens it.
    private let gate: DispatchSemaphore?
    private let lock = NSLock()
    private weak var watcher: FolderWatcher?
    private weak var sink: FolderWatcher.Sink?
    private var only: FolderWatcher?
    private var recorded: [Call] = []
    private let firstCallBegan = DispatchSemaphore(value: 0)

    private(set) var writesMade = 0
    private(set) var dropBegan: UInt64 = 0
    private(set) var dropReturned: UInt64 = 0
    private(set) var gateOpened: UInt64 = 0
    private(set) var sinkGoneAt: UInt64 = 0
    /// Whether the weak reference to the watcher read nil as soon as the
    /// assignment that dropped it returned, that is, whether nothing else held
    /// the watcher then.
    private(set) var droppedLast: Bool?
    private(set) var sinkAliveBeforeDrop: Bool?
    private(set) var sinkAliveAtEndOfHold: Bool?
    /// What kind of round this was, for the case that mixes kinds in one batch.
    var tag = ""

    init(gated: Bool) {
        self.gate = gated ? DispatchSemaphore(value: 0) : nil
    }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    /// The clock at which the first call began, once it has.
    var firstBegan: UInt64? { calls.first?.began }

    func awaitFirstCall(timeout: TimeInterval) -> Bool {
        firstCallBegan.wait(timeout: .now() + timeout) == .success
    }

    func awaitFirstCallEnded(timeout: TimeInterval) -> Bool {
        let limit = probeNow() + UInt64(timeout * 1e9)
        while probeNow() < limit {
            if (calls.first?.ended ?? 0) != 0 { return true }
            Thread.sleep(forTimeInterval: 0.0005)
        }
        return false
    }

    func awaitCalls(_ count: Int, within seconds: TimeInterval) {
        let limit = probeNow() + UInt64(seconds * 1e9)
        while probeNow() < limit, calls.count < count { Thread.sleep(forTimeInterval: 0.0005) }
    }

    func write(_ writer: ProbeWriter) {
        writer.trigger()
        writesMade += 1
    }

    /// Builds the watcher and holds the weak references; watches nothing yet.
    func make() {
        let made = FolderWatcher { [self] _ in called() }
        watcher = made
        sink = made.sink
        only = made
    }

    func watch(_ folder: String) -> Bool {
        guard let made = only else { return false }
        let said = DispatchSemaphore(value: 0)
        let answer = ProbeFlag()
        made.watch([folder]) { ok in answer.set(ok); said.signal() }
        return said.wait(timeout: .now() + 5) == .success && answer.value
    }

    func start(on folder: String) -> Bool {
        make()
        return watch(folder)
    }

    private func called() {
        let began = probeNow()
        lock.lock()
        let position = recorded.count
        recorded.append(Call(began: began))
        lock.unlock()
        if position == 0 {
            firstCallBegan.signal()
            _ = gate?.wait(timeout: .now() + 20)
        }
        let ended = probeNow()
        lock.lock()
        recorded[position].ended = ended
        lock.unlock()
    }

    /// Gives up this object's reference to the watcher, on the calling thread;
    /// `droppedLast` says whether that was the last one.
    func drop() {
        sinkAliveBeforeDrop = sink != nil
        dropBegan = probeNow()
        only = nil
        dropReturned = probeNow()
        droppedLast = watcher == nil
    }

    func openGate() {
        gateOpened = probeNow()
        gate?.signal()
    }

    func noteTheSinkAtTheEndOfTheHold() { sinkAliveAtEndOfHold = sink != nil }

    /// Polls until the weak reference to the sink reads nil, for at most
    /// `seconds`; remembers the first clock at which it did.
    func awaitSinkGone(within seconds: TimeInterval) {
        let limit = probeNow() + UInt64(seconds * 1e9)
        while probeNow() < limit {
            if sink == nil { sinkGoneAt = probeNow(); return }
            Thread.sleep(forTimeInterval: 0.0005)
        }
        if sink == nil { sinkGoneAt = probeNow() }
    }

    /// Stops the stream without dropping the watcher.
    func stopOnly() { only?.stop() }

    /// For a round that was not dropped: stop it the way an owner does. Also
    /// opens the gate, so a held call never outlives the round.
    func stopAndRelease() {
        gate?.signal()
        only?.stop()
        only = nil
    }

    // Readings.

    var secondCallAfterGateMs: Double? {
        let c = calls
        return c.count >= 2 && gateOpened != 0 ? millis(gateOpened, c[1].began) : nil
    }

    var sinkGoneAfterDropMs: Double? { sinkGoneAt == 0 ? nil : millis(dropReturned, sinkGoneAt) }

    var sinkGoneAfterGateMs: Double? { sinkGoneAt == 0 || gateOpened == 0 ? nil : millis(gateOpened, sinkGoneAt) }

    var callsBeganAfterTheDrop: Int { calls.filter { $0.began >= dropBegan }.count }
}

// MARK: - the rounds (free functions: they run on threads of their own)

private func inParallel(_ count: Int, deadline: TimeInterval,
                        _ body: @escaping @Sendable (Int) -> ProbeRound?) -> [ProbeRound] {
    let group = DispatchGroup()
    let found = ProbeCollected<ProbeRound>()
    for i in 0..<count {
        group.enter()
        let thread = Thread {
            if let round = body(i) { found.add(round) }
            group.leave()
        }
        thread.start()
    }
    if group.wait(timeout: .now() + deadline) == .timedOut {
        XCTFail("not every round finished within \(Int(deadline)) s")
    }
    return found.all
}

private func folderAndWriter(_ i: Int, root: URL) -> (folder: String, writer: ProbeWriter) {
    let folder = root.appendingPathComponent("r\(i)-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("w.txt").path
    return (folder.path, ProbeWriter(file: file))
}

/// Where the last reference goes while the first call holds the queue.
private enum GatedKind: String, CaseIterable {
    /// Never: the round lets the second call come, as the control.
    case nothingDropped = "nothing dropped"
    /// After the second write's delivery is due, with the held call still keeping the queue.
    case droppedWhileTheDeliveryWaits = "dropped while the delivery waits"
    /// Before the second write is made, so its delivery reaches the queue after
    /// the drop has returned.
    case droppedBeforeTheDeliveryArrives = "dropped before the delivery arrives"
}

/// Two writes, the second 100 ms after the first call began; the first call
/// holds the queue until the gate is opened. The gate is opened 1.8 s after
/// the first call began, which is after the second write's delivery is due
/// however the stream is timed (a latency after the second write at the
/// longest), so the second call can begin as soon as the gate opens. `kind`
/// says where the last reference is dropped, if anywhere; the round then
/// watches for the sink to leave memory, or for the second call if nothing
/// was dropped.
private func gatedRound(_ i: Int, root: URL, kind: GatedKind) -> ProbeRound? {
    let (folder, writer) = folderAndWriter(i, root: root)
    defer { writer.finish() }
    let round = ProbeRound(gated: true)
    round.tag = kind.rawValue
    guard writer.started, round.start(on: folder) else {
        print("[setup failed] gated round \(i)")
        return nil
    }
    defer { round.stopAndRelease() }
    Thread.sleep(forTimeInterval: 0.005)
    round.write(writer)
    guard round.awaitFirstCall(timeout: 5), let first = round.firstBegan else { return round }
    if kind == .droppedBeforeTheDeliveryArrives {
        Thread.sleep(forTimeInterval: 0.05)
        round.drop()
        Thread.sleep(forTimeInterval: 0.05)
    } else {
        Thread.sleep(forTimeInterval: 0.1)
    }
    round.write(writer)
    wait(until: first + 1_800_000_000)
    if kind == .droppedWhileTheDeliveryWaits { round.drop() }
    round.openGate()
    if kind == .nothingDropped { round.awaitCalls(2, within: 1.0) } else { round.awaitSinkGone(within: 1.0) }
    Thread.sleep(forTimeInterval: 0.2)
    return round
}

/// What the stream was doing when the watcher was dropped.
private enum SinkShape: CaseIterable {
    case neverWatched
    case liveStream
    case liveStreamAfterADelivery
    case streamReplaced
    case streamStopped

    var label: String {
        switch self {
        case .neverWatched: "never watched"
        case .liveStream: "live stream"
        case .liveStreamAfterADelivery: "live stream, a delivery already made"
        case .streamReplaced: "stream replaced by a second watch"
        case .streamStopped: "stream stopped, then dropped"
        }
    }
}

/// One watcher in `shape`, dropped, and the time until its sink read nil.
private func sinkRound(_ i: Int, root: URL, shape: SinkShape) -> ProbeRound? {
    let (folder, writer) = folderAndWriter(i, root: root)
    defer { writer.finish() }
    let round = ProbeRound(gated: false)
    round.make()
    switch shape {
    case .neverWatched:
        break
    case .liveStream, .liveStreamAfterADelivery, .streamStopped:
        guard round.watch(folder) else { print("[setup failed] sink round \(i)"); return nil }
    case .streamReplaced:
        guard round.watch(folder), round.watch(folder) else { print("[setup failed] sink round \(i)"); return nil }
    }
    if shape == .liveStreamAfterADelivery {
        Thread.sleep(forTimeInterval: 0.005)
        round.write(writer)
        guard writer.started, round.awaitFirstCall(timeout: 5), round.awaitFirstCallEnded(timeout: 2) else {
            print("[no delivery] sink round \(i)")
            round.stopAndRelease()
            return nil
        }
    }
    if shape == .streamStopped { round.stopOnly() }
    round.drop()
    round.awaitSinkGone(within: 1.0)
    return round
}

/// The first call holds the queue until the gate is opened. The last reference
/// is dropped while it runs, `hold` seconds go by, and only then the gate opens.
private func inFlightRound(_ i: Int, root: URL, hold: TimeInterval) -> ProbeRound? {
    let (folder, writer) = folderAndWriter(i, root: root)
    defer { writer.finish() }
    let round = ProbeRound(gated: true)
    guard writer.started, round.start(on: folder) else {
        print("[setup failed] in-flight round \(i)")
        return nil
    }
    defer { round.stopAndRelease() }
    Thread.sleep(forTimeInterval: 0.005)
    round.write(writer)
    guard round.awaitFirstCall(timeout: 5) else { return round }
    Thread.sleep(forTimeInterval: 0.05)
    round.drop()
    Thread.sleep(forTimeInterval: hold)
    round.noteTheSinkAtTheEndOfTheHold()
    round.openGate()
    round.awaitSinkGone(within: 1.0)
    _ = round.awaitFirstCallEnded(timeout: 1)
    return round
}

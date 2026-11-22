import AppKit
import os

/// The icons one window draws, kept for as long as the window is open and not a moment longer.
///
/// Not `AppInfo.icon(forFile:)`, which is one cache for the whole process and never emptied: a grid of three hundred apps would stay in
/// memory after it was closed. This cache is the window state's own, bounded to what the live pages and an open folder's live pages
/// ask (`limits`), and goes with the state. Only a page that is live asks.
///
/// **Rendered once per (path, pixel side), off main.** `image(for:side:)` never draws: a hit is the one-representation image at that
/// side, a miss asks the private queue (`LaunchpadIconRender`) and answers the last image the path had at another size, scaled by the
/// view, or nothing (an empty slot of the same frame) until the exact one lands, when `onArrival` says to draw again, once per run-loop
/// turn however many landed. The key carries the pixels, so every distinct side (tile, quadrant, folder cell, cluster) is its own entry
/// and is drawn once however many views ask; a bitmap is `pixels² × 4` bytes and the cache is bound by that as well as by count.
///
/// **A redraw never evicts what it asked.** The bound is sized for what the live pages can ask at once, but a bound that is ever too
/// small must not make a loop: an arrival evicts only an entry not asked since the last `onArrival` was said, so each redraw's asks
/// stay until the next one, and what a redraw asks is drawn at most once more. (An `NSCache` evicts as it likes, which is how a page of
/// full folders drew icons, evicted them for the next ones, and asked again for ever.) A drawing that answers nothing is remembered as
/// failed until the next `invalidate`, and its slot stays empty, so no pass asks it again.
///
/// **A result may not outlive what asked for it.** `removeAll` (the window is down) and a new scale or grid bump `generation`, empty the
/// bookkeeping and cancel what has not started; a render already running finishes, and its result is dropped when the generation it was
/// asked under is no longer the current one: on the queue's thread after drawing (through `live`), and again on main (read there,
/// never captured: a payload is captured before the hop, a reading is taken inside it). The queue's operations hold the cache weakly,
/// so nothing here keeps the state alive.
@MainActor final class LaunchpadIcons {
    typealias Renderer = @Sendable (String, Int) -> CGImage?

    /// The empty image a slot has until its icon lands; the views take an optional and draw this for nil, so a frame never changes.
    static let empty = NSImage(size: .zero)

    /// What is drawn, by key: its use stamp is the `clock` at its last ask, and an entry stamped at or after `protectedFrom` was asked
    /// since the last redraw was said and is not evicted by an arrival.
    private struct Kept { let image: NSImage; let cost: Int; var used: Int }
    private var kept: [String: Kept] = [:]
    private var keptCost = 0
    private var clock = 0
    private var protectedFrom = 0
    private var limits: (count: Int, cost: Int)
    /// The largest image each path has had at any size, shown scaled until the exact size lands (any side's arrival fills it); bounded as the cache is.
    private let latest = NSCache<NSString, NSImage>()
    /// The keys whose drawing answered nothing: not asked again until the next `invalidate`.
    private var failed: Set<String> = []
    private let queue = OperationQueue()
    private let render: Renderer
    private(set) var scale: CGFloat
    private var generation = 0
    /// The generation as the queue's operations may read it from their own threads (`generation` is main's).
    private let live = OSAllocatedUnfairLock(initialState: 0)
    private var pending: Set<String> = []
    /// Asks made while a grid setting is being dragged: only those after the last change are drawn (`reconfigure`).
    private var held: [String: (path: String, pixels: Int)] = [:]
    private var holding: Task<Void, Never>?
    private var arrivalQueued = false
    private var waits: [Wait] = []
    /// Said, once per run-loop turn, when something new has landed: the window state redraws, and the views ask again and now hit.
    var onArrival: (() -> Void)?
    /// How many images have landed since this cache was made, for the tests.
    private(set) var rendered = 0

    /// What `warm` waits for: the keys still to land, and the one continuation to resume once, by the last of them or by the deadline.
    private final class Wait {
        var keys: Set<String>
        var landed = 0
        var timedOut = false
        var resume: CheckedContinuation<Int, Never>?
        let wanted: Int
        init(keys: Set<String>) { self.keys = keys; wanted = keys.count }
    }

    /// `side` is the grid's icon side in points, the largest a tile asks.
    init(capacity: Int, side: CGFloat, scale: CGFloat, render: Renderer? = nil) {
        self.scale = scale
        self.render = render ?? Self.system()
        limits = Self.limits(capacity: capacity, side: side, scale: scale)
        latest.countLimit = limits.count
        latest.totalCostLimit = limits.cost
        queue.maxConcurrentOperationCount = min(4, ProcessInfo.processInfo.activeProcessorCount)
        queue.qualityOfService = .userInitiated
    }

    /// The system's drawing, in one colour space made once: Display P3, which the icons are made in, so a wide colour is not clamped on the way in.
    private static func system() -> Renderer {
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return { path, pixels in LaunchpadIconRender.render(path: path, pixels: pixels, space: space) }
    }

    /// What the live pages can ask at once, from the geometry. Per cell of a page the most keys are a folder's nine minis, so a page asks
    /// at most `9 * capacity`; the live pages are the shown one and its two neighbours (`3 * 9 * capacity`), and an open folder's card
    /// asks one key per cell on its own three live pages (`3 * capacity`): `30 * capacity` keys. In bytes a cell is at most one tile's
    /// bitmap (nine minis, a large folder's twelve over its four cells, a category's eight over its four are each less), so the three
    /// pages and the card's three are at most `6 * capacity * pixels² * 4`. At 8 x 5 (capacity 40), icon 80 pt, 2x (160 px):
    /// 1200 keys and 6 * 40 * 160² * 4 = 24 576 000 bytes, 23.4 MiB. Eviction stays inside it unless the live pages ask more.
    static func limits(capacity: Int, side: CGFloat, scale: CGFloat) -> (count: Int, cost: Int) {
        let pixels = pixels(side: side, scale: scale), cells = max(1, capacity)
        return (30 * cells, 6 * cells * pixels * pixels * 4)
    }

    static func pixels(side: CGFloat, scale: CGFloat) -> Int {
        let wanted = (side * scale).rounded()
        return wanted.isFinite ? max(1, Int(min(wanted, 4096))) : 1
    }

    private func key(_ path: String, _ pixels: Int) -> String { "\(pixels)|\(path)" }

    /// The icon of `path` for a view `side` points across, or what it had before at another size, or nil. Never draws.
    func image(for path: String, side: CGFloat) -> NSImage? {
        let pixels = Self.pixels(side: side, scale: scale), key = key(path, pixels)
        clock += 1
        if var hit = kept[key] { hit.used = clock; kept[key] = hit; return hit.image }
        request(path: path, pixels: pixels, key: key)
        return latest.object(forKey: path as NSString)
    }

    /// Asks for each (path, side) and answers when they have landed (or could not be drawn), or when `deadline` ends the wait (a race, not a
    /// promise): how many of the ones asked for are drawn, how many were asked for (those not already drawn, nor failed), and whether the deadline
    /// ended the wait (a drawing that failed settles its key without it).
    func warm(_ asks: [(path: String, side: CGFloat)], deadline: Duration) async -> (drawn: Int, wanted: Int, timedOut: Bool) {
        var keys: Set<String> = []
        for (path, side) in asks {
            let pixels = Self.pixels(side: side, scale: scale), key = key(path, pixels)
            if kept[key] == nil, !failed.contains(key) { keys.insert(key); request(path: path, pixels: pixels, key: key) }
        }
        guard !keys.isEmpty else { return (0, 0, false) }
        let wait = Wait(keys: keys)
        let drawn = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            wait.resume = continuation
            waits.append(wait)
            Task { @MainActor [weak self, weak wait] in
                try? await Task.sleep(for: deadline)
                if let self, let wait { wait.timedOut = wait.resume != nil; self.end(wait) }
            }
        }
        return (drawn, wait.wanted, wait.timedOut)
    }

    private func end(_ wait: Wait) {
        waits.removeAll { $0 === wait }
        guard let resume = wait.resume else { return }
        wait.resume = nil
        resume.resume(returning: wait.landed)
    }

    private func request(path: String, pixels: Int, key: String) {
        guard !pending.contains(key), !failed.contains(key) else { return }
        if holding != nil { held[key] = (path, pixels); return }
        start(path: path, pixels: pixels, key: key)
    }

    private func start(path: String, pixels: Int, key: String) {
        guard pending.insert(key).inserted else { return }
        let asked = generation, live = live, render = render
        queue.addOperation { [weak self] in
            guard live.withLock({ $0 }) == asked else { return }
            let image = render(path, pixels)
            guard live.withLock({ $0 }) == asked else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.arrived(path: path, pixels: pixels, key: key, image: image, asked: asked) }
            }
        }
    }

    private func arrived(path: String, pixels: Int, key: String, image: CGImage?, asked: Int) {
        guard asked == generation else { return }
        pending.remove(key)
        guard let image else {
            failed.insert(key)
            settle(key, landed: false)
            return
        }
        let drawn = NSImage(cgImage: image, size: NSSize(width: CGFloat(pixels) / scale, height: CGFloat(pixels) / scale))
        let cost = pixels * pixels * 4
        clock += 1
        keptCost += cost - (kept[key]?.cost ?? 0)
        kept[key] = Kept(image: drawn, cost: cost, used: clock)
        while kept.count > limits.count || keptCost > limits.cost {
            let floor = protectedFrom
            guard let oldest = kept.lazy.filter({ $0.value.used < floor }).min(by: { $0.value.used < $1.value.used }) else { break }
            keptCost -= oldest.value.cost
            kept[oldest.key] = nil
        }
        if (latest.object(forKey: path as NSString)?.size.width ?? 0) < drawn.size.width { latest.setObject(drawn, forKey: path as NSString, cost: cost) }
        rendered += 1
        settle(key, landed: true)
        publish()
    }

    private func settle(_ key: String, landed: Bool) {
        for wait in waits where wait.keys.remove(key) != nil {
            if landed { wait.landed += 1 }
            if wait.keys.isEmpty { end(wait) }
        }
    }

    /// Says `onArrival` once per run-loop turn however many asked; what the redraw asks from then on is what an arrival may not evict.
    private func publish() {
        guard !arrivalQueued else { return }
        arrivalQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.arrivalQueued = false
                self.protectedFrom = self.clock + 1
                self.onArrival?()
            }
        }
    }

    /// The window has closed: nothing it drew stays, what has not started does not, and what is running lands nowhere.
    func removeAll() {
        invalidate()
        kept = [:]
        keptCost = 0
        latest.removeAllObjects()
        for wait in waits { end(wait) }
        onArrival = nil
    }

    /// A new grid or scale: the cache's bound follows the page. Images are keyed by their pixels, so what was drawn at another side stays
    /// until it falls out, shown scaled meanwhile; asks for the new sides wait ~80 ms after the last change, so dragging a grid setting
    /// draws the side it stopped on and not each one it passed, and what had been asked for an earlier side and not started is dropped.
    /// A new scale draws everything again at its own pixels. When the hold ends, a redraw is said (`onArrival`): what was asked before
    /// the change and dropped by it is asked again by the views, which no arrival would otherwise say.
    func reconfigure(capacity: Int, side: CGFloat, scale: CGFloat) {
        limits = Self.limits(capacity: capacity, side: side, scale: scale)
        latest.countLimit = limits.count
        latest.totalCostLimit = limits.cost
        invalidate()
        // An image keeps its point size, which is its pixels over the scale it was drawn for: another scale cannot reuse it.
        if scale != self.scale { kept = [:]; keptCost = 0 }
        self.scale = scale
        holding = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            holding = nil
            let wanted = held
            held = [:]
            for (key, ask) in wanted { start(path: ask.path, pixels: ask.pixels, key: key) }
            publish()
        }
    }

    /// What was asked under the old generation is cancelled, forgotten and, if it lands, dropped.
    private func invalidate() {
        holding?.cancel()
        holding = nil
        held = [:]
        queue.cancelAllOperations()
        generation += 1
        let now = generation
        live.withLock { $0 = now }
        pending.removeAll()
        failed.removeAll()
    }
}

import AppKit
import Foundation
import HelmRuntime
@preconcurrency import LocalAuthentication
import os

/// **The installed applications, read off three fixed folders.**
///
/// `/Applications`, `~/Applications`, `/System/Applications`, in that precedence. Safari is
/// not a fourth root: on this macOS `/Applications/Safari.app` is a symlink into
/// `/System/Cryptexes/App/System/Applications`, and a symlinked `.app` is accepted.
///
/// An entry with the extension `app` is an application and is never descended into; a plain,
/// non-symlink, non-hidden folder with no extension is descended into to `LaunchpadLimits.maxDepth` levels
/// (judged by name and one `lstat`, never by reading what is in it); symlinked folders are not followed.
/// One id found twice is one app: the earlier root wins, then the smallest path. A walk the
/// `LaunchpadLimits.maxApps` ceiling stopped, like a folder that would not open, is not `complete`.
/// Names are the one Finder shows: the bundle's localized display name in the person's language,
/// else `Info.plist` (display name, then bundle name), else the bundle's file name.
struct FileSystemAppCatalog: AppCatalogPort {
    private let roots: [URL]

    init(roots: [URL] = FileSystemAppCatalog.defaultRoots) { self.roots = roots }

    static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]

    private struct Found {
        let root: Int
        let app: CatalogApp
    }

    func read(reason: CatalogReadReason) -> CatalogReading {
        var found: [Found] = []
        var complete = true
        var noID = 0
        var capped = false
        for (index, root) in roots.enumerated() {
            walk(root, depth: 0, rootIndex: index, dated: Self.recordsDate(forRoot: root), into: &found, complete: &complete, noID: &noID, capped: &capped)
        }
        var best: [String: Found] = [:]
        var losers = 0
        for f in found {
            if let current = best[f.app.id] {
                losers += 1
                if (f.root, f.app.path) < (current.root, current.app.path) { best[f.app.id] = f }
            } else {
                best[f.app.id] = f
            }
        }
        let apps = best.values.map(\.app).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        HelmLog.shared.info(LaunchpadEngine.moduleID,
                            "read \(apps.count) apps (\(reason.rawValue)), \(losers) duplicate ids, \(noID) without an id, \(apps.filter { $0.added == nil }.count) without a date added"
                            + (complete ? "" : ", some folders would not open") + (capped ? ", stopped at the ceiling" : ""))
        return CatalogReading(apps: apps, complete: complete)
    }

    /// No date for the system's own folder: a macOS update adds every app there again, and they would all be "recent" for 30 days.
    static func recordsDate(forRoot root: URL) -> Bool { root.standardizedFileURL.path != "/System/Applications" }

    /// When Finder says the bundle was added to its folder (`ATTR_CMN_ADDEDTIME`, the attribute behind `addedToDirectoryDateKey`).
    /// nil for a symlinked bundle (Safari in `/Applications` is one: the link's date is not the app's) and for a date that would not
    /// read. One `getattrlist` per app: `resourceValues` costs more memory an app, and this makes no object.
    /// The length check below is a defensive guard no test reaches: the kernel always fills the `timespec` for a directory, and
    /// `getattrlist` has no fake.
    private static func dateAdded(_ url: URL) -> Date? {
        guard Self.isPlainFolder(url) else { return nil }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        // The answer is a length, then the time as a packed `timespec`.
        var answer = [UInt8](repeating: 0, count: 4 + MemoryLayout<timespec>.size)
        guard getattrlist(url.path, &request, &answer, answer.count, UInt32(FSOPT_NOFOLLOW)) == 0 else { return nil }
        // The leading length says how much of the buffer the system filled: no date unless the whole `timespec` is there.
        let length = answer.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard length >= 4 + UInt32(MemoryLayout<timespec>.size) else { return nil }
        let time = answer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: timespec.self) }
        guard time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    private func walk(_ dir: URL, depth: Int, rootIndex: Int, dated: Bool, into found: inout [Found],
                      complete: inout Bool, noID: inout Int, capped: inout Bool) {
        guard case .listed(let entries) = DirectoryListing.contents(of: dir) else { complete = false; return }
        for entry in entries {
            if found.count >= LaunchpadLimits.maxApps { capped = true; complete = false; return }
            let name = entry.lastPathComponent
            if entry.pathExtension == "app" {
                var read: CatalogApp?
                autoreleasepool { read = Self.app(at: entry) }
                if var app = read {
                    if dated { app.added = Self.dateAdded(entry) }
                    found.append(Found(root: rootIndex, app: app))
                } else {
                    noID += 1
                }
            } else if depth < LaunchpadLimits.maxDepth, !name.hasPrefix("."), entry.pathExtension.isEmpty,
                      Self.isPlainFolder(entry) {
                walk(entry, depth: depth + 1, rootIndex: rootIndex, dated: dated, into: &found,
                     complete: &complete, noID: &noID, capped: &capped)
            }
        }
    }

    private static func isPlainFolder(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// The bundle's `Info.plist`; nil for a missing, unparseable or oversize one.
    private static func infoPlist(at url: URL) -> [String: Any]? {
        PropertyListFile.infoPlist(ofBundleAt: url)
    }

    /// The bundle's `InfoPlist.strings` in the person's language, as Finder picks it; nil when it has none or none reads.
    private static func localizedInfo(at url: URL) -> [String: Any]? {
        let held = Bundle(url: url)?.localizations ?? []
        for code in Bundle.preferredLocalizations(from: held, forPreferences: nil) {
            let strings = url.appendingPathComponent("Contents/Resources/\(code).lproj/InfoPlist.strings").path
            if let found = PropertyListFile.dictionary(atPath: strings) { return found }
        }
        return nil
    }

    private static func bundleID(in dict: [String: Any]) -> String? {
        (dict["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : LaunchpadLimits.bounded($0) }
    }

    func bundleID(atPath path: String) -> String? {
        Self.infoPlist(at: URL(fileURLWithPath: path, isDirectory: true)).flatMap(Self.bundleID(in:))
    }

    private static func app(at url: URL) -> CatalogApp? {
        guard let dict = infoPlist(at: url), let id = bundleID(in: dict) else { return nil }
        func text(_ value: Any?) -> String? { (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let localized = localizedInfo(at: url)
        let name = text(localized?["CFBundleDisplayName"]) ?? text(localized?["CFBundleName"])
            ?? text(dict["CFBundleDisplayName"]) ?? text(dict["CFBundleName"])
            ?? url.deletingPathExtension().lastPathComponent
        return CatalogApp(id: id, name: LaunchpadLimits.bounded(name), path: url.path,
                          category: (dict["LSApplicationCategoryType"] as? String).flatMap { $0.isEmpty ? nil : LaunchpadLimits.bounded($0) })
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        CatalogWatch(roots: roots, onChange: onChange)
    }
}

/// The folders watched for as long as this object is held.
///
/// A separate type so that `deinit` is the whole of the lifetime: dropping the token
/// stops the stream, and nothing else has to remember to.
private final class CatalogWatch: @unchecked Sendable {
    private let watcher: FolderWatcher

    init(roots: [URL], onChange: @escaping @Sendable () -> Void) {
        watcher = FolderWatcher { paths in
            if CatalogChange.concerns(paths) { onChange() }
        }
        watcher.watch(roots.map(\.path)) { started in
            if !started {
                HelmLog.shared.warn(LaunchpadEngine.moduleID, "the installed apps cannot be watched — a change shows on the next read")
            }
        }
    }

    deinit { watcher.stop() }
}

/// Opens an application through LaunchServices, as the system does for a double-click.
///
/// A test process answers `false` and calls nothing: opening is a thing the owner's Mac would do.
struct SystemAppLauncher: AppLauncherPort {
    init() {}

    func open(_ url: URL) async -> Bool {
        guard !TestProcess.isRunning else { return false }
        return await Self.openOnMain(url)
    }

    @MainActor private static func openOnMain(_ url: URL) async -> Bool {
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }
}

/// Touch ID or the Mac's password through LocalAuthentication, asked with `deviceOwnerAuthentication`, so the system draws the
/// dialog and Helm sees only the outcome. Each ask has a fresh context whose reuse duration is 0: a recent unlock of the Mac
/// does not stand for this one.
///
/// Cancelling the asking task invalidates the context, which dismisses the dialog; a cancel that comes before the context is
/// stored answers `.cancelled` without showing one. A test process answers `.unavailable` and makes no context: asking the
/// owner for a fingerprint is a thing the owner's Mac would do.
public final class SystemLaunchpadAuth: LaunchpadAuthPort, @unchecked Sendable {
    public init() {}

    /// One ask's own cancel state, made inside `evaluate`: a cancel of an earlier ask never reaches a later one through the port.
    private final class Ask: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(uncheckedState: (cancelled: false, context: LAContext?.none))
        var cancelled: Bool { state.withLock { $0.cancelled } }
        /// False when the ask was cancelled before: the context is then not stored.
        func store(_ context: LAContext) -> Bool {
            state.withLock { state in
                if state.cancelled { return false }
                state.context = context
                return true
            }
        }
        func cancel() { state.withLock { state -> LAContext? in state.cancelled = true; return state.context }?.invalidate() }
    }

    public func evaluate(reason: String) async -> AuthOutcome {
        guard !TestProcess.isRunning else { return .unavailable }
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        let ask = Ask()
        return await withTaskCancellationHandler {
            if !ask.store(context) { return .cancelled }
            let can = await offTheCooperativePool {
                var error: NSError?
                return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            }
            guard can else { return ask.cancelled ? .cancelled : .unavailable }
            if ask.cancelled { return .cancelled }
            let outcome: AuthOutcome = await withCheckedContinuation { continuation in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
                    continuation.resume(returning: ok ? .success : Self.outcome(of: error))
                }
            }
            return ask.cancelled && outcome == .success ? .cancelled : outcome
        } onCancel: {
            ask.cancel()
        }
    }

    private static func outcome(of error: Error?) -> AuthOutcome {
        switch (error as? LAError)?.code {
        case .authenticationFailed: .failed
        case .userCancel, .systemCancel, .appCancel: .cancelled
        default: .unavailable
        }
    }
}

/// The system's pinch gesture settings, read from the two trackpad domains (built-in and Bluetooth), where the keys are
/// `TrackpadFourFingerPinchGesture` and `TrackpadFiveFingerPinchGesture` (2 when on, as read on macOS 27; 0 is taken as off).
/// Nothing here writes a key: Helm tells the person and sends them to System Settings.
struct SystemTrackpadPreferences: SystemPinchPort {
    init() {}

    private static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    private static let keys = ["TrackpadFourFingerPinchGesture", "TrackpadFiveFingerPinchGesture"]

    func read() -> SystemPinch {
        let values = Self.domains.flatMap { domain in
            Self.keys.compactMap { (CFPreferencesCopyAppValue($0 as CFString, domain as CFString) as? NSNumber)?.intValue }
        }
        if values.isEmpty { return .unreadable }
        return values.contains { $0 != 0 } ? .on : .off
    }
}

/// The trackpads' fingers through MultitouchSupport, a private framework with no header: it is `dlopen`ed and its symbols
/// `dlsym`ed (as `DisplayCorners` reaches `CGSetLocalEventsSuppressionInterval`), so a macOS that moved it is `.frameworkMissing`
/// and never a crash. The record layout below is what the framework has used since it was first reverse-engineered; every
/// frame goes through `TouchFrame`'s checks and `FrameTrust` stands the watch down when they fail in a row.
///
/// The framework's callback carries no context, so the one live port is found through `route`. A test process answers
/// `.noTrackpad` and calls nothing: watching the owner's trackpad is a thing the owner's Mac would do.
/// Devices are restarted when the Mac wakes (a pad may have gone and come back), and stopped by `stop()`; its owner stops it.
final class MultitouchSupportPort: TrackpadTouchPort, @unchecked Sendable {
    init() {}

    private typealias Device = UnsafeMutableRawPointer
    private typealias Callback = @convention(c) (Device?, UnsafeRawPointer?, Int32, Double, Int32) -> Void
    private struct Symbols {
        let createList: @convention(c) () -> Unmanaged<CFArray>?
        let register: @convention(c) (Device, Callback) -> Void
        let unregister: @convention(c) (Device, Callback) -> Void
        let start: @convention(c) (Device, Int32) -> Int32
        let stop: @convention(c) (Device) -> Int32
    }

    /// The bytes of one finger's record, the offsets of the fields read, and the size of one record.
    private enum Record {
        static let stride = 96
        static let state = 20
        static let positionX = 32
        static let positionY = 36
    }

    private static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private static let route = NSLock()
    nonisolated(unsafe) private static var live: MultitouchSupportPort?

    private let lock = NSLock()
    private var symbols: Symbols?
    private var list: CFArray?
    private var devices: [Device] = []
    private var onFrame: (@Sendable (TouchFrame) -> Void)?
    private var onStandDown: (@Sendable () -> Void)?
    private var trust: [FrameTrust] = []
    private var standingDown = false
    /// Guarded by `lock`: `start` and `stop` may be called from different threads.
    private var wake: NSObjectProtocol?

    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void, onStandDown: @escaping @Sendable () -> Void) -> TouchWatchStart {
        guard !TestProcess.isRunning else { return .noTrackpad }
        stop()
        lock.withLock { self.onFrame = onFrame; self.onStandDown = onStandDown; standingDown = false }
        let result = startDevices()
        if case .watching = result {
            Self.route.withLock { Self.live = self }
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let wanted = { self.lock.withLock { self.onFrame != nil } }
                guard wanted() else { return }
                stopDevices()
                guard wanted() else { return }
                let again = startDevices()
                if !wanted() { stopDevices(); return }
                HelmLog.shared.info(LaunchpadEngine.moduleID, "pinch: the Mac woke, trackpads \(again == .noTrackpad ? "gone" : "watched again")")
            }
            lock.withLock { wake = observer }
        } else {
            lock.withLock { self.onFrame = nil; self.onStandDown = nil }
        }
        return result
    }

    func stop() {
        Self.route.withLock { if Self.live === self { Self.live = nil } }
        if let wake = lock.withLock({ () -> NSObjectProtocol? in defer { self.wake = nil }; return self.wake }) {
            NSWorkspace.shared.notificationCenter.removeObserver(wake)
        }
        stopDevices()
        lock.withLock { onFrame = nil; onStandDown = nil }
    }

    private func load() -> Symbols? {
        if let symbols = lock.withLock({ self.symbols }) { return symbols }
        guard let handle = dlopen(Self.path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as _: T.Type) -> T? { dlsym(handle, name).map { unsafeBitCast($0, to: T.self) } }
        guard let createList = symbol("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
              let register = symbol("MTRegisterContactFrameCallback", as: (@convention(c) (Device, Callback) -> Void).self),
              let unregister = symbol("MTUnregisterContactFrameCallback", as: (@convention(c) (Device, Callback) -> Void).self),
              let start = symbol("MTDeviceStart", as: (@convention(c) (Device, Int32) -> Int32).self),
              let stop = symbol("MTDeviceStop", as: (@convention(c) (Device) -> Int32).self)
        else { return nil }
        let found = Symbols(createList: createList, register: register, unregister: unregister, start: start, stop: stop)
        lock.withLock { symbols = found }
        return found
    }

    private func startDevices() -> TouchWatchStart {
        guard let symbols = load() else { return .frameworkMissing }
        guard let array = symbols.createList()?.takeRetainedValue() else { return .noTrackpad }
        let count = min(CFArrayGetCount(array), TouchFrame.maxDevices)
        let found = (0..<count).compactMap { CFArrayGetValueAtIndex(array, $0).map { Device(mutating: $0) } }
        guard !found.isEmpty else { return .noTrackpad }
        lock.withLock { list = array; devices = found; trust = Array(repeating: FrameTrust(), count: found.count) }
        for device in found {
            symbols.register(device, Self.callback)
            _ = symbols.start(device, 0)
        }
        return .watching(devices: found.count)
    }

    private func stopDevices() {
        let (symbols, held, array) = lock.withLock { () -> (Symbols?, [Device], CFArray?) in
            defer { devices = []; list = nil }
            return (self.symbols, devices, list)
        }
        guard let symbols else { return }
        // The devices belong to the list: it is kept until every one is stopped and its callback taken away.
        withExtendedLifetime(array) {
            for device in held {
                _ = symbols.stop(device)
                symbols.unregister(device, Self.callback)
            }
        }
    }

    /// The framework's thread. Reads the records in place, and keeps nothing of the memory it was handed.
    private static let callback: Callback = { device, touches, count, timestamp, _ in
        guard let device, let touches else { return }
        route.lock()
        let port = live
        route.unlock()
        port?.receive(device: device, touches: touches, count: Int(count), time: timestamp)
    }

    private func receive(device: Device, touches: UnsafeRawPointer, count: Int, time: Double) {
        let (index, deliver, standDown) = lock.withLock { () -> (Int?, (@Sendable (TouchFrame) -> Void)?, (@Sendable () -> Void)?) in
            (devices.firstIndex(of: device), onFrame, onStandDown)
        }
        guard let index, let deliver, !lock.withLock({ standingDown }) else { return }
        let frame = TouchFrame(device: index, time: time, count: count) { i in
            let record = touches + i * Record.stride
            return (Double(record.loadUnaligned(fromByteOffset: Record.positionX, as: Float.self)),
                    Double(record.loadUnaligned(fromByteOffset: Record.positionY, as: Float.self)),
                    Int(record.loadUnaligned(fromByteOffset: Record.state, as: Int32.self)))
        }
        let reached = lock.withLock { () -> Bool in
            guard index < trust.count else { return false }
            let reached = trust[index].note(accepted: frame != nil)
            if reached { standingDown = true }
            return reached
        }
        if let frame { deliver(frame) }
        if reached { standDown?() }
    }
}

import AppKit
import CoreGraphics
import HelmRuntime
import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - Shell

/// Kept as a name; the body is `HelmProcess`, shared by every module.
enum Shell {
    static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, stdout: String) {
        let result = HelmProcess.run(launchPath, arguments)
        return (result.status, result.output)
    }

}

// MARK: - IOKitSleepAssertions

public final class IOKitSleepAssertions: SleepAssertions {
    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var hasSystemAssertion = false
    private var hasDisplayAssertion = false

    public init() {}

    public func preventSleep(display: Bool) {
        if !hasSystemAssertion {
            var assertionID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleSystemSleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Helm: keep the Mac awake" as CFString,
                &assertionID
            )
            if result == kIOReturnSuccess {
                systemAssertionID = assertionID
                hasSystemAssertion = true
            }
        }

        if display, !hasDisplayAssertion {
            var assertionID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Helm: keep the display on" as CFString,
                &assertionID
            )
            if result == kIOReturnSuccess {
                displayAssertionID = assertionID
                hasDisplayAssertion = true
            }
        }
    }

    public func release() {
        if hasSystemAssertion {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
            hasSystemAssertion = false
        }
        if hasDisplayAssertion {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
            hasDisplayAssertion = false
        }
    }
}

// MARK: - CGDisplayInfo

public final class CGDisplayInfo: DisplayInfoPort {
    public init() {}

    public func builtInFlags() -> [Bool] {
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let result = CGGetOnlineDisplayList(maxDisplays, &displayIDs, &displayCount)
        guard result == .success else { return [] }

        return (0..<Int(displayCount)).map { CGDisplayIsBuiltin(displayIDs[$0]) != 0 }
    }
}

// MARK: - IOPSPowerInfo

public final class IOPSPowerInfo: PowerInfoPort {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (@Sendable () -> Void)?

    public init() {}

    public func snapshot() -> (onBattery: Bool, percent: Int)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, firstSource)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        let onBattery = state == kIOPSBatteryPowerValue

        // "I don't know" must not arrive as 0%. BatteryGuard reads a low
        // reading as a critical battery and ends the session, so an incomplete
        // IOKit dictionary used to stop Keep Awake for no reason at all.
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        let percent = Int((Double(current) / Double(max)) * 100.0)

        return (onBattery: onBattery, percent: percent)
    }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let port = Unmanaged<IOPSPowerInfo>.fromOpaque(context).takeUnretainedValue()
            port.onChange?()
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    /// Removed *and* invalidated. Removing takes it off this run loop;
    /// invalidating stops the source firing at all, which is what matters if a
    /// callback is already scheduled — the context it would resolve is `self`,
    /// and `self` is about to go.
    public func stopObserving() {
        guard let source = runLoopSource else { return }
        runLoopSource = nil
        onChange = nil
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        CFRunLoopSourceInvalidate(source)
    }

    /// The backstop. `deactivate` is the ordinary route and covers the module
    /// being switched off; this covers every other way the port can be let go.
    deinit { stopObserving() }
}

// MARK: - ScreenParamsObserver

public final class ScreenParamsObserver: DisplayObserverPort {
    public init() {}

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange()
        }
    }
}

// MARK: - WorkspaceAppPort

public final class WorkspaceAppPort: AppRunningPort {
    /// Held so the observers can be taken back out. Without this, switching
    /// the module off and on stacked another pair each time — the same defect
    /// `LayoutEngine.deactivate` documents.
    private var tokens: [NSObjectProtocol] = []

    public init() {}

    deinit {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    /// Through `RunningApps` for the same reason the VPN port is: this one is
    /// only ever reached from the main thread today, and "only ever, today" is
    /// exactly what was true of the other one.
    public func runningBundleIDs() -> Set<String> { RunningApps.shared.bundleIDs() }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = [NSWorkspace.didLaunchApplicationNotification,
                  NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                RunningApps.shared.refreshOnMain(then: onChange)
            }
        }
    }
}

// MARK: - CGEventPointer

public final class CGEventPointer: PointerPort {
    public init() {}

    public func location() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    public func move(to p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    public func displayBounds(containing p: CGPoint) -> CGRect? {
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let result = CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount)
        guard result == .success else { return nil }

        for index in 0..<Int(displayCount) {
            let bounds = CGDisplayBounds(displayIDs[index])
            if bounds.contains(p) {
                return bounds
            }
        }
        return nil
    }
}

// MARK: - DispatchClock

/// Token whose lifetime controls the scheduled work item: dropping it (or letting it
/// deinit) cancels the pending block, matching the engine's "release the AnyObject to
/// cancel" convention used elsewhere (see expiryToken/jiggleToken/batteryToken).
private final class DispatchWorkItemToken {
    private let item: DispatchWorkItem

    init(item: DispatchWorkItem) {
        self.item = item
    }

    deinit {
        item.cancel()
    }
}

public final class DispatchClock: Clock {
    public init() {}

    public func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: item)
        return DispatchWorkItemToken(item: item)
    }

    public func now() -> Date {
        Date()
    }
}

// MARK: - PmsetClamshellPort

public final class PmsetClamshellPort: ClamshellPort {
    private static let sudoersPath = "/etc/sudoers.d/helm-keepawake"
    private static let pmsetPath = "/usr/bin/pmset"
    private static let sudoPath = "/usr/bin/sudo"

    public init() {}

    public func pmsetReport() -> String {
        Shell.run(Self.pmsetPath, ["-g"]).stdout
    }

    public func setDisableSleep(_ on: Bool) -> Bool {
        let flag = on ? "1" : "0"
        let result = Shell.run(Self.sudoPath, ["-n", Self.pmsetPath, "disablesleep", flag])
        return result.status == 0
    }

    /// Existence, not contents: the file is installed 0440 root:wheel, so
    /// reading it as the user always fails. Answering "not installed" every time
    /// meant the admin prompt came back every session, and the removal added
    /// alongside it could never run at all.
    public func isSudoersInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.sudoersPath)
    }

    public func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let user = NSUserName()
            guard AccountName.isPlausible(user) else {
                HelmLog.shared.warn("keepawake", "refusing sudoers rule for an implausible account name")
                done(false)
                return
            }
            let rule = "\(user) ALL=(root) NOPASSWD: \(Self.pmsetPath) disablesleep 1, "
                     + "\(Self.pmsetPath) disablesleep 0\n"
            // The rule is written from Swift and only its *path* is handed to the
            // privileged shell: nothing derived from the account name is ever
            // quoted into a command line. The staging file is in this user's
            // private temporary directory, not /tmp, so no one else can swap it.
            // A fresh directory per attempt, not a fixed name. The privileged
            // read happens after the password prompt, so with a predictable
            // path anything already running as this user has an unbounded
            // window to rewrite the rule it is about to install as root.
            // $TMPDIR is 0700, which stops other users; this stops the rest.
            let stagingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("helm-sudoers-\(UUID().uuidString)")
            guard (try? FileManager.default.createDirectory(
                at: stagingDirectory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])) != nil else {
                done(false)
                return
            }
            defer { try? FileManager.default.removeItem(at: stagingDirectory) }
            let staged = stagingDirectory.appendingPathComponent("helm-keepawake.sudoers")
            guard (try? rule.write(to: staged, atomically: true, encoding: .utf8)) != nil else {
                done(false)
                return
            }
            defer { try? FileManager.default.removeItem(at: staged) }
            // visudo is the check that a syntax error cannot reach sudoers.d;
            // install puts it in place with the ownership and mode sudo demands.
            let shellCommand = "/usr/sbin/visudo -cf '\(staged.path)' "
                             + "&& /usr/bin/install -m 440 -o root -g wheel "
                             + "'\(staged.path)' \(Self.sudoersPath)"
            let script = "do shell script \"\(shellCommand)\" with administrator privileges"

            let result = Shell.run("/usr/bin/osascript", ["-e", script])
            done(result.status == 0)
        }
    }

    /// Takes the rule back out. A permanent grant of passwordless root for a
    /// setting the user has switched off is a grant no one asked to keep — and
    /// Helm's predecessor left one behind on this very machine.
    public func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.isSudoersInstalled() else { done(true); return }
            let script = "do shell script \"/bin/rm -f \(Self.sudoersPath)\" "
                       + "with administrator privileges"
            let result = Shell.run("/usr/bin/osascript", ["-e", script])
            done(result.status == 0)
        }
    }
}

// MARK: - Factory

/// Convenience bundle of all production ports so the module wiring (host app) can
/// construct one object and hand each port to `KeepAwakeEngine`'s initializer.
public struct KeepAwakeSystemPorts {
    public let assertions = IOKitSleepAssertions()
    public let displayInfo = CGDisplayInfo()
    public let displayObserver = ScreenParamsObserver()
    public let power = IOPSPowerInfo()
    public let apps = WorkspaceAppPort()
    public let pointer = CGEventPointer()
    public let clamshell = PmsetClamshellPort()
    public let clock = DispatchClock()

    public init() {}
}

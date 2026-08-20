import AppKit
import CoreGraphics
import HelmRuntime
import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - IOKitSleepAssertions

public final class IOKitSleepAssertions: SleepAssertions {
    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var hasSystemAssertion = false
    private var hasDisplayAssertion = false

    public init() {}

    /// The backstop, for the same reason `IOPSPowerInfo` below has one and
    /// `CGKeyTap` now does: `deactivate()` is the ordinary route and covers the
    /// module being switched off, and it is not the only way this object is let
    /// go. An assertion nobody gives back is held until the process exits — so
    /// dropping the engine any other way left a Mac that would not sleep, with
    /// the settings page saying Keep Awake was off.
    deinit { release() }

    /// - Returns: whether everything asked for is now held. The `IOReturn` was
    ///   read only to decide whether to keep the id, and thrown away as an
    ///   *answer*: a refusal here is a Mac that sleeps while every surface says
    ///   Helm is holding it awake.
    @discardableResult
    public func preventSleep(display: Bool) -> Bool {
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
        // **The call makes the world match its argument.** It used to only ever
        // add: `display: false` created nothing and released nothing, so an
        // assertion taken when the setting was on stayed up after it went off,
        // and the display never slept. Nothing was broken by that only because
        // `reconcileActiveSettings` releases everything first and re-applies —
        // a pair somebody has to remember to balance, in the module whose worst
        // failure is a Mac that will not sleep.
        if !display, hasDisplayAssertion {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
            hasDisplayAssertion = false
        }
        // Everything that was asked for, not «something went up»: with the
        // display setting on, a system assertion alone is a screen that goes
        // dark on a Mac being held awake, which is not what the person switched
        // on.
        return hasSystemAssertion && (!display || hasDisplayAssertion)
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

    /// The reading itself moved to `PowerSource` in `HelmRuntime` when
    /// background scans needed it too — a second IOKit read written in the
    /// coordinator is the duplication that target exists to stop.
    ///
    /// This port stays. It is what lets Keep Awake's tests hand the engine a
    /// battery that does whatever the test needs, and the notification half
    /// below has no equivalent in `PowerSource`: a scan asks once a minute and
    /// has nothing to subscribe to.
    ///
    /// Nil still means "IOKit would not answer", and the battery guard still
    /// reads that as no reading at all rather than as a flat battery.
    public func snapshot() -> (onBattery: Bool, percent: Int)? {
        guard let reading = PowerSource.current() else { return nil }
        return (onBattery: reading.onBattery, percent: reading.percent)
    }

    /// The other question, which `snapshot()` cannot answer — the protocol has
    /// why. An independent read rather than a fold of the battery reading: this
    /// used to be `PowerSource.isOnMains`, whose nil-means-mains fold belongs to
    /// the background scan and was silently deciding this module's questions too.
    public func supply() -> PowerSource.Supply? { PowerSource.supply() }

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
    /// Held so it can be taken back out — the same reason `WorkspaceAppPort`
    /// twenty lines below holds its own, and for the same defect: every enable
    /// of the module left another block registered for the life of the
    /// process. `[weak self]` is not the answer here, because the block
    /// captures the caller's closure and not this object, so nothing decayed;
    /// the observers simply accumulated and the display callback ran once per
    /// enable, quietly.
    private var token: NSObjectProtocol?

    public init() {}

    deinit { stopObserving() }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange()
        }
    }

    public func stopObserving() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
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
    private static let sudoersPath = SudoersRule.installedPath
    private static let pmsetPath = SudoersRule.pmsetPath
    private static let sudoPath = "/usr/bin/sudo"

    public init() {}

    public func pmsetReport() -> String {
        HelmProcess.run(Self.pmsetPath, ["-g"]).output
    }

    public func setDisableSleep(_ on: Bool) -> Bool {
        let flag = on ? "1" : "0"
        let result = HelmProcess.run(Self.sudoPath, ["-n", Self.pmsetPath, "disablesleep", flag])
        return result.status == 0
    }

    /// Existence, not contents: the file is installed 0440 root:wheel, so
    /// reading it as the user always fails. Answering "not installed" every time
    /// meant the admin prompt came back every session, and the removal added
    /// alongside it could never run at all.
    public func isSudoersInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.sudoersPath)
    }

    /// Asks sudo, not the filesystem. `-n` fails rather than prompting, and
    /// `disablesleep 0` is the half of the grant that is safe to spend on a
    /// question: it is what «restore sleep» does anyway, and it is idempotent.
    public func canDisableSleepWithoutPassword() -> Bool {
        HelmProcess.run(Self.sudoPath, ["-n", Self.pmsetPath, "disablesleep", "0"]).status == 0
    }

    public func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let user = NSUserName()
            guard AccountName.isPlausible(user) else {
                HelmLog.shared.warn(KeepAwakeEngine.moduleID, "refusing sudoers rule for an implausible account name")
                done(false)
                return
            }
            // The rule text goes to root, never a path root should read it from.
            // Staging it in $TMPDIR and passing the path meant root installed
            // whatever was at that path at the moment `install` ran, and the
            // path stood in `ps auxww` for the whole life of the password
            // prompt (`SudoersRule` has the rest). Everything now happens
            // inside root-owned /etc/sudoers.d.
            let result = HelmProcess.run("/usr/bin/osascript", ["-e", SudoersRule.installScript(user: user)])
            done(result.status == 0)
        }
    }

    /// Takes the rule back out. A permanent grant of passwordless root for a
    /// setting the user has switched off is a grant no one asked to keep — and
    /// Helm's predecessor left one behind on this very machine.
    public func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.isSudoersInstalled() else { done(true); return }
            let result = HelmProcess.run("/usr/bin/osascript", ["-e", SudoersRule.removeScript()])
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
    /// Where the battery veto's one notification goes. The log area is the
    /// module's id — `KeepAwakeEngine.moduleID`, the same constant every
    /// `HelmLog` call in this target reads, so the Journal files these lines
    /// with the rest of the module's.
    ///
    /// Its `init` touches nothing — `UNUserNotificationCenter.current()` is
    /// reached inside each method, and would end a whole test run if it were
    /// reached here.
    public let notices = SystemAutomationNotice(area: KeepAwakeEngine.moduleID)

    public init() {}
}

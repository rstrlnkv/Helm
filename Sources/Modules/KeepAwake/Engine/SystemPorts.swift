import AppKit
import CoreGraphics
import HelmRuntime
import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - IOKitSleepAssertions

final class IOKitSleepAssertions: SleepAssertions {
    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var hasSystemAssertion = false
    private var hasDisplayAssertion = false

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
    func preventSleep(display: Bool) -> Bool {
        if !hasSystemAssertion, let id = take("PreventUserIdleSystemSleep", "Helm: keep the Mac awake") {
            systemAssertionID = id
            hasSystemAssertion = true
        }

        if display, !hasDisplayAssertion,
           let id = take("PreventUserIdleDisplaySleep", "Helm: keep the display on") {
            displayAssertionID = id
            hasDisplayAssertion = true
        }
        // **The call makes the world match its argument.** It used to only ever
        // add: `display: false` created nothing and released nothing, so an
        // assertion taken when the setting was on stayed up after it went off,
        // and the display never slept. Nothing was broken by that only because
        // `reconcileActiveSettings` releases everything first and re-applies —
        // a pair somebody has to remember to balance, in the module whose worst
        // failure is a Mac that will not sleep.
        if !display, hasDisplayAssertion {
            give(&displayAssertionID)
            hasDisplayAssertion = false
        }
        // Everything that was asked for, not «something went up»: with the
        // display setting on, a system assertion alone is a screen that goes
        // dark on a Mac being held awake, which is not what the person switched
        // on.
        return hasSystemAssertion && (!display || hasDisplayAssertion)
    }

    func release() {
        if hasSystemAssertion {
            give(&systemAssertionID)
            hasSystemAssertion = false
        }
        if hasDisplayAssertion {
            give(&displayAssertionID)
            hasDisplayAssertion = false
        }
    }

    /// Create one assertion of `type`; nil if IOKit refuses.
    private func take(_ type: String, _ name: String) -> IOPMAssertionID? {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 name as CFString, &assertionID)
        return result == kIOReturnSuccess ? assertionID : nil
    }

    /// Release the assertion and zero its id.
    private func give(_ id: inout IOPMAssertionID) {
        IOPMAssertionRelease(id)
        id = 0
    }
}

// MARK: - displayIDs

/// Up to 16 display ids from one of CoreGraphics' list functions (online or
/// active), or nil when it fails.
private func displayIDs(
    _ list: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
) -> [CGDirectDisplayID]? {
    let maxDisplays: UInt32 = 16
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    var count: UInt32 = 0
    guard list(maxDisplays, &ids, &count) == .success else { return nil }
    return Array(ids.prefix(Int(count)))
}

// MARK: - CGDisplayInfo

final class CGDisplayInfo: DisplayInfoPort {
    func builtInFlags() -> [Bool] {
        (displayIDs(CGGetOnlineDisplayList) ?? []).map { CGDisplayIsBuiltin($0) != 0 }
    }
}

// MARK: - MacLidInfo

final class MacLidInfo: LidInfoPort {
    func hasLid() -> Bool { MacHardware.hasLid }
    func hasBattery() -> Bool { MacHardware.hasBattery }
}

// MARK: - IOPSPowerInfo

final class IOPSPowerInfo: PowerInfoPort {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (@Sendable () -> Void)?

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
    func snapshot() -> (onBattery: Bool, percent: Int)? {
        guard let reading = PowerSource.current() else { return nil }
        return (onBattery: reading.onBattery, percent: reading.percent)
    }

    /// The other question, which `snapshot()` cannot answer — the protocol has
    /// why. An independent read rather than a fold of the battery reading: this
    /// used to be `PowerSource.isOnMains`, whose nil-means-mains fold belongs to
    /// the background scan and was silently deciding this module's questions too.
    func supply() -> PowerSource.Supply? { PowerSource.supply() }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
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
    func stopObserving() {
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

final class ScreenParamsObserver: DisplayObserverPort {
    /// Held so it can be taken back out — the same reason `WorkspaceAppPort`
    /// twenty lines below holds its own, and for the same defect: every enable
    /// of the module left another block registered for the life of the
    /// process. `[weak self]` is not the answer here, because the block
    /// captures the caller's closure and not this object, so nothing decayed;
    /// the observers simply accumulated and the display callback ran once per
    /// enable, quietly.
    private var token: NSObjectProtocol?

    deinit { stopObserving() }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange()
        }
    }

    func stopObserving() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}

// MARK: - WorkspaceAppPort

final class WorkspaceAppPort: AppRunningPort {
    /// Held so the observers can be taken back out. Without this, switching
    /// the module off and on stacked another pair each time — the same defect
    /// `LayoutEngine.deactivate` documents.
    private(set) var tokens: [NSObjectProtocol] = []

    deinit { stopObserving() }

    /// Through `RunningApps` for the same reason the VPN port is: this one is
    /// only ever reached from the main thread today, and "only ever, today" is
    /// exactly what was true of the other one.
    func runningBundleIDs() -> Set<String> { RunningApps.shared.bundleIDs() }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = [NSWorkspace.didLaunchApplicationNotification,
                  NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                RunningApps.shared.refreshOnMain(then: onChange)
            }
        }
    }

    func stopObserving() {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens = []
    }
}

// MARK: - CGEventPointer

final class CGEventPointer: PointerPort {
    func location() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    func move(to p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func displayBounds(containing p: CGPoint) -> CGRect? {
        for id in displayIDs(CGGetActiveDisplayList) ?? [] {
            let bounds = CGDisplayBounds(id)
            if bounds.contains(p) {
                return bounds
            }
        }
        return nil
    }
}

// MARK: - DispatchClock

final class DispatchClock: Clock {
    func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject {
        DelayedWork.schedule(on: .main, after: after, block)
    }

    func now() -> Date {
        Date()
    }
}

// MARK: - PmsetClamshellPort

final class PmsetClamshellPort: ClamshellPort {
    private static let pmsetPath = SudoersRule.pmsetPath
    private static let sudoPath = "/usr/bin/sudo"

    private let sudoersPath: String
    private let privileged: @Sendable (String) -> PrivilegedOutcome
    private let pmset: @Sendable () -> HelmProcess.Result

    /// The two arguments are the seam a test reads the port through: which
    /// command each half sends to root and how the outcome is read cannot be
    /// seen from outside otherwise, and swapping them stayed green.
    init(sudoersPath: String = SudoersRule.installedPath,
                privileged: @escaping @Sendable (String) -> PrivilegedOutcome = { PrivilegedRun.run($0) },
                pmset: @escaping @Sendable () -> HelmProcess.Result = { HelmProcess.run(PmsetClamshellPort.pmsetPath, ["-g"]) }) {
        self.sudoersPath = sudoersPath
        self.privileged = privileged
        self.pmset = pmset
    }

    func pmsetReport() -> String? {
        let result = pmset()
        return result.status == 0 ? result.output : nil
    }

    /// The words come from `SudoersRule`, because the rule has to spell the same
    /// ones: `sudo` matches a command spec argument for argument, so two
    /// spellings of this call are a name only one side ever changes — and the
    /// drift is an error nowhere, it is a call that quietly starts asking for a
    /// password again.
    func setDisableSleep(_ on: Bool) -> Bool {
        withoutPassword(SudoersRule.disableSleepArguments(on: on)) == 0
    }

    /// `sudo -n` — it fails rather than prompting, which is what makes every one
    /// of these safe to run with nobody watching. Every call this port makes
    /// against the grant goes through here, so the flag cannot be left off at
    /// one site: without it the command waits on a password prompt in a child
    /// process no window belongs to.
    private func withoutPassword(_ arguments: [String]) -> Int32 {
        HelmProcess.run(Self.sudoPath, ["-n"] + arguments).status
    }

    /// Existence, not contents: the file is installed 0440 root:wheel, so
    /// reading it as the user always fails. Answering "not installed" every time
    /// meant the admin prompt came back every session, and the removal added
    /// alongside it could never run at all.
    func isSudoersInstalled() -> Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// Asks sudo, not the filesystem. `-n` fails rather than prompting, and
    /// `disablesleep 0` is the half of the grant that is safe to spend on a
    /// question: it is what «restore sleep» does anyway, and it is idempotent.
    func canDisableSleepWithoutPassword() -> Bool {
        withoutPassword(SudoersRule.disableSleepArguments(on: false)) == 0
    }

    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        let privileged = privileged
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
            done(privileged(SudoersRule.installCommand(user: user)) == .done)
        }
    }

    /// Takes the rule back out with the rule's own grant. A permanent grant of
    /// passwordless root for a setting the user has switched off is a grant no
    /// one asked to keep — and Helm's predecessor left one behind on this very
    /// machine.
    ///
    /// **The verdict is the second `fileExists`, not sudo's exit status.** The
    /// question is whether the file is gone, and a reading taken before the act
    /// cannot answer it.
    func removeSudoersWithoutPassword() -> Bool {
        guard isSudoersInstalled() else { return true }
        _ = withoutPassword(SudoersRule.removeArguments)
        return !isSudoersInstalled()
    }

    /// The withdrawal for a rule that cannot make it itself: one from before the
    /// `rm` line existed, or one somebody else wrote. This is the one that puts
    /// the administrator dialog on screen, so only a gesture may reach it.
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        let privileged = privileged, sudoersPath = sudoersPath
        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.fileExists(atPath: sudoersPath) else { done(true); return }
            done(privileged(SudoersRule.removeCommand()) == .done)
        }
    }
}

// MARK: - Factory

/// Convenience bundle of all production ports so the module wiring (host app) can
/// construct one object and hand each port to `KeepAwakeEngine`'s initializer.
public struct KeepAwakeSystemPorts {
    public let assertions: SleepAssertions = IOKitSleepAssertions()
    public let displayInfo: DisplayInfoPort = CGDisplayInfo()
    public let lidInfo: LidInfoPort = MacLidInfo()
    public let displayObserver: DisplayObserverPort = ScreenParamsObserver()
    public let power: PowerInfoPort = IOPSPowerInfo()
    public let apps: AppRunningPort = WorkspaceAppPort()
    public let pointer: PointerPort = CGEventPointer()
    public let clamshell: ClamshellPort = PmsetClamshellPort()
    public let clock: Clock = DispatchClock()
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

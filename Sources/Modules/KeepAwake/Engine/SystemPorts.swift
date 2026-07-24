import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - Shell

/// Small Process wrapper: runs a binary, waits, and returns exit status + captured stdout.
enum Shell {
    static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        process.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
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

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 0
        let percent = max > 0 ? Int((Double(current) / Double(max)) * 100.0) : 0

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
    public init() {}

    public func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in onChange() }

        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in onChange() }
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

    public func isSudoersInstalled() -> Bool {
        guard let contents = try? String(contentsOfFile: Self.sudoersPath, encoding: .utf8) else {
            return false
        }
        return contents.contains("pmset disablesleep")
    }

    public func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let user = NSUserName()
            let rule = "\(user) ALL=(root) NOPASSWD: \(Self.pmsetPath) disablesleep 1, \(Self.pmsetPath) disablesleep 0"
            // Escape for embedding inside the AppleScript double-quoted shell command string.
            let escapedRule = rule.replacingOccurrences(of: "\\", with: "\\\\\\\\")
                .replacingOccurrences(of: "\"", with: "\\\\\\\"")
            let shellCommand = "echo \\\"\(escapedRule)\\\" > \(Self.sudoersPath) && chmod 440 \(Self.sudoersPath)"
            let script = "do shell script \"\(shellCommand)\" with administrator privileges"

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

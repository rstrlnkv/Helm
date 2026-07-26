import CoreGraphics
import Foundation

public protocol SleepAssertions: AnyObject {   // IOKit
    func preventSleep(display: Bool)
    func release()
}

public protocol DisplayInfoPort: AnyObject { func builtInFlags() -> [Bool] }

public protocol PowerInfoPort: AnyObject {
    func snapshot() -> (onBattery: Bool, percent: Int)?
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
}

public protocol DisplayObserverPort: AnyObject { func startObserving(_ onChange: @escaping @Sendable () -> Void) }

public protocol AppRunningPort: AnyObject {
    func runningBundleIDs() -> Set<String>
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
}

public protocol PointerPort: AnyObject {
    func location() -> CGPoint?
    func move(to: CGPoint)
    func displayBounds(containing: CGPoint) -> CGRect?
}

public protocol ClamshellPort: AnyObject {
    func isSudoersInstalled() -> Bool
    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void)   // admin prompt once
    /// Takes the rule back out when the feature is switched off.
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void)
    func setDisableSleep(_ on: Bool) -> Bool                // pmset (passwordless)
    func pmsetReport() -> String
}

public protocol Clock: AnyObject {
    func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject
    func now() -> Date
}

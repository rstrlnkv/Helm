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
    /// Every observer this module starts has to be stoppable, because the
    /// module can be switched off: the engine is dropped, the port goes with
    /// it, and anything still holding a pointer to the port is holding freed
    /// memory.
    ///
    /// This used to say `NotificationCenter` observers were exempt because the
    /// centre keeps its own tokens. It keeps them; it does not remove them.
    /// `WorkspaceAppPort` had already learned that and holds its tokens with a
    /// comment saying why, while `ScreenParamsObserver` took the exemption at
    /// face value and stacked another observer on every enable. There is no
    /// exemption: the centre's token is the thing you have to keep in order to
    /// take the observer back out.
    func stopObserving()
}

public protocol DisplayObserverPort: AnyObject {
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

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

import CoreGraphics
import Foundation
import HelmRuntime

public protocol SleepAssertions: AnyObject {   // IOKit
    /// Whether the Mac is now being held awake — **everything that was asked
    /// for**, so `display: true` answers no if only the system half went up.
    ///
    /// It answered `Void`, and `IOPMAssertionCreateWithName`'s `IOReturn` was
    /// read for one thing only: whether to keep the id. So a refused assertion
    /// left the engine setting `isActive`, writing «holding sleep» and lighting
    /// the menu bar for a Mac that then slept on schedule — the same «a refusal
    /// that is not a success» the clamshell half of this module was corrected
    /// for, on the port that could not even say it. A state a port has no word
    /// for is a state no fake can stand in and no test can be written about.
    @discardableResult
    func preventSleep(display: Bool) -> Bool
    func release()
}

public protocol DisplayInfoPort: AnyObject { func builtInFlags() -> [Bool] }

public protocol PowerInfoPort: AnyObject {
    func snapshot() -> (onBattery: Bool, percent: Int)?
    /// Which supply is running the Mac, which is **not** derivable from
    /// `snapshot()` — that is nil both for a Mac with no battery and for an
    /// incomplete IOKit dictionary, and reading the two as one thing left the
    /// power rule dead on every desktop. `PowerSource.supply()` has the rest.
    ///
    /// **Three answers, because the system has three.** It used to be a `Bool`
    /// folding «I don't know» into `true`, which is how a power source nothing
    /// could read came to *start* holding a Mac awake; this module folds that
    /// third answer to «not on mains», because letting the Mac sleep is its safe
    /// failure. The battery guard still reads `snapshot()`, where nil correctly
    /// means «no reading, do not end the session».
    func supply() -> PowerSource.Supply?
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
    /// Whether `pmset disablesleep` can actually be run without a password.
    ///
    /// Not the same question as «is our file there», and the difference was
    /// measured on the machine this was written on: `/etc/sudoers.d` held a
    /// `vorssaint-clamshell` from a predecessor whose contents are this app's
    /// rule character for character, under another name. So the file check
    /// answered no while the capability was granted — Helm asked for a password
    /// to install what already existed — and after removal it answered no again
    /// while any process running as this user still had passwordless
    /// `pmset disablesleep`. A revocation that revokes nothing is worse than
    /// none, because it is reported as done.
    func canDisableSleepWithoutPassword() -> Bool
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

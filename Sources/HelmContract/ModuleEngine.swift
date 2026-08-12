public protocol ModuleEngine: AnyObject {
    func activate()
    /// **Somebody switched this module off, and is still at the screen.**
    ///
    /// Called by the host from the person's own switch and from nowhere else —
    /// never from quitting, which is `deactivate()` alone. The distinction is not
    /// tidiness: `applicationWillTerminate` calls `deactivate()` on every live
    /// engine, so anything there that needs an answer from a person is a dialog
    /// raised on behalf of an app that is already gone. Keep Awake shipped
    /// exactly that once — an administrator password prompt at quit, for a
    /// `/etc/sudoers.d` rule it was trying to take back out — and the rule then
    /// had to be left behind on *every* route out, including the one where
    /// somebody had just said they did not want the feature.
    ///
    /// So: put work that needs the person here, and work that must happen however
    /// the process ends in `deactivate()`. Defaulted, because most engines have
    /// nothing to say to the difference.
    func willDisable()
    func deactivate()
    /// Module-specific commands are sent through the typed façade over this
    /// transport (LocalTransport in-process, XPCTransport out-of-process).
    var transport: EngineTransport { get }
}

public extension ModuleEngine {
    func willDisable() {}
}

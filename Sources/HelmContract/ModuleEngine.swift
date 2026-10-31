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
    /// **This engine stands in for the module without being it.** The host then
    /// refuses to switch the module off and refuses «Reset all settings»: it would
    /// write the real `enabled` flag and ask this engine to give back what the real
    /// one never took, so the next ordinary launch would find the module off and
    /// nothing to recover. Defaulted: only a stand-in says yes.
    var standsIn: Bool { get }
    func deactivate()
    /// **How many models are listening to this engine right now.** Needed by the
    /// host test that holds an `any ModuleEngine` and cannot see the engine's
    /// own `EngineNews<…>`. Defaulted to 0, so that test's assert of 1 stays red
    /// on a module that forgets to answer.
    var subscriberCount: Int { get }
}

public extension ModuleEngine {
    func willDisable() {}
    var standsIn: Bool { false }
    var subscriberCount: Int { 0 }
}

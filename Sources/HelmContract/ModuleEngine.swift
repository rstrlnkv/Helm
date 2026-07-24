public protocol ModuleEngine: AnyObject {
    func activate()
    func deactivate()
    /// Module-specific commands are sent through the typed façade over this
    /// transport (LocalTransport in-process, XPCTransport out-of-process).
    var transport: EngineTransport { get }
}

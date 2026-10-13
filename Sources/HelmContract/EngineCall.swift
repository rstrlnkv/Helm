/// One command of a module's own enum, with the types that cross the wire for it.
///
/// The wire is a name and bytes, so nothing on it says what the bytes are: an
/// arm can decode a payload as one type while the caller sends another, and a
/// reply can be read as a type the engine never encoded. A call says it once.
/// Its place is beside the enum, in the engine, and whatever is handed the call
/// takes its types from that one value:
///
///     static let loadKey = EngineCall<HostsCommand, KeyLoad, KeyOutcome>(command: .agentLoad)
///
/// **The call is keyed by the case; it does not replace the enum.** A command
/// stays a case of the module's own enum, and a handler still switches over
/// those cases with no `default` arm (ARCHITECTURE.md § The boundaries says
/// why). The call only adds, to one case, what the enum could not say.
///
/// **`Payload` and `Reply` appear in no stored property.** They are there for
/// the compiler: the `EngineReply` overloads that take the call take the reply
/// as `Reply` and return the payload as `Payload?`, so a reply Swift cannot
/// convert to `Reply` does not compile. Both must be `Codable` because one end
/// encodes what the other end decodes.
///
/// A struct in this target, not in `HelmRuntime`: it describes the wire and
/// holds nothing that logs; the overloads that log are `EngineReply`'s.
public struct EngineCall<Command: RawRepresentable & Sendable, Payload: Codable, Reply: Codable>: Sendable
where Command.RawValue == String {

    public let command: Command

    /// Spelled out because the memberwise initialiser this struct would get
    /// without it is internal, though the struct is public, and a call is
    /// declared outside this target.
    public init(command: Command) { self.command = command }
}

/// A value a test hands to another thread on purpose, whose type is not
/// `Sendable` only because nobody declared it so (a store, a Homebrew rig).
/// Not a way to share state mutated without a lock; `Locked` is that.
public struct Shared<Value>: @unchecked Sendable {
    public let value: Value

    public init(_ value: Value) { self.value = value }
}

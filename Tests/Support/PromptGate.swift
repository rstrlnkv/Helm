import Foundation

/// A system prompt held open until the test lets it answer.
///
/// A fake that finishes instantly makes a test of a wait vacuous, and the
/// instant worth reaching in a notification channel is between reading the
/// permission and posting: macOS's prompt can stand for minutes, and whatever
/// wanted to speak may be switched off meanwhile. `FakeAutomationNotice`'s
/// `whileAsking` closure waits on this gate.
///
/// An actor rather than a lock: every caller is already `async`, and the two
/// waits have to suspend rather than block, or the test's own thread is the one
/// holding the prompt up.
public actor PromptGate {
    private var isOpen = false
    private var arrived = false
    private var waitingForOpen: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Called from inside the fake's prompt: records that the prompt is up, then
    /// waits for the test to open the gate.
    public func arrive() async {
        arrived = true
        guard !isOpen else { return }
        await withCheckedContinuation { waitingForOpen.append($0) }
    }

    /// Waits until the prompt is actually up.
    ///
    /// Bounded, because a red must fail rather than hang: with the channel not
    /// wired the prompt never comes. The caller asserts that it arrived.
    public func reached(within seconds: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !arrived, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// The person answered. Everything waiting inside the prompt goes on.
    public func open() {
        isOpen = true
        for continuation in waitingForOpen { continuation.resume() }
        waitingForOpen = []
    }
}

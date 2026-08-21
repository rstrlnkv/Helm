import Foundation

/// A system prompt held open until the test lets it answer.
///
/// **A fake that finishes instantly makes a test of a wait vacuous** — the
/// subject is over before the code under test is reached — and the one instant
/// worth reaching in a notification channel is between reading the permission
/// and posting: macOS's prompt can stand on screen for minutes, and whatever
/// wanted to speak may be switched off in that time. `FakeAutomationNotice`
/// takes a `whileAsking` closure for exactly this; the gate is what the closure
/// waits on.
///
/// Written twice in one change — once to cancel a task from inside the prompt
/// and once to switch a module off while it stood — before it moved here.
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
    /// wired the prompt never comes, and a wait with no deadline turns a failing
    /// test into a run nobody can read. The caller asserts that it arrived —
    /// silence here would make every later assertion a claim about a system that
    /// never got there.
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

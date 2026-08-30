import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// A local fake rather than the shared one, because this test also counts how
/// often the engine asks the expensive question: `emitState` asks `isSecure()`
/// exactly once, so the count of those calls is the count of emissions — the
/// difference between «the page is told at the edges» and «the page is told on
/// every keystroke of the password».
private final class CountingSecure: SecureContextPort, @unchecked Sendable {
    var secure = false
    var secureChecks = 0
    func isSecureInput() -> Bool { secure }
    func isSecure() -> Bool { secureChecks += 1; return secure }
    func frontmostBundleID() -> String { "com.apple.Notes" }
}

/// «Paused» on the page is a live fact, not a snapshot. `suspended` used to be
/// computed only inside `emitState()`, and the secure branch of `handle()`
/// returned before any emit — so while a person actually typed a password the
/// page said nothing, and once something else emitted a suspended state it held
/// it until the next conversion. The engine already knows the episode's edges:
/// it clears the buffer on them.
final class TheSuspensionIsAFactNotASnapshotTests: XCTestCase {

    func testEnteringAndLeavingSecureInputBothReachThePage() async {
        let secure = CountingSecure()
        let tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: FakeTyping(), sources: FakeSources(),
            translation: FakeTranslation(table: [:]), spell: FakeSpell(valid: []),
            secure: secure, automatic: true)
        engine.activate()

        secure.secure = true
        tap.type("h")
        let paused = await latestLayoutState(engine)
        XCTAssertEqual(paused?.suspended, true, """
            the first secure keystroke is the edge of the episode, and the page \
            was not told: while the person actually types a password, the module \
            is silent about the very pause that explains its silence.
            """)

        let emitsAtEntry = secure.secureChecks
        tap.type("unter2")
        XCTAssertEqual(secure.secureChecks, emitsAtEntry, """
            six more keystrokes of the same password are not six more emissions: \
            the page is told at the edges, and `isSecure()` reaches the \
            accessibility server, which must not be paid per key.
            """)

        secure.secure = false
        tap.type("x")
        let resumed = await latestLayoutState(engine)
        XCTAssertEqual(resumed?.suspended, false, """
            the dialog is gone and the page still says «Paused»: a snapshot \
            taken at the last conversion, held until the next one, standing in \
            for a fact the engine already noticed changing.
            """)
        engine.deactivate()
    }
}

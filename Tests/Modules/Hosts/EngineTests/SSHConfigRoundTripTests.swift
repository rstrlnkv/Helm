import XCTest
@testable import Module_Hosts_Engine

/// `render(parse(x)) == x`, byte for byte, over what an `~/.ssh/config` turns
/// out to be in the wild — and it is a wilder file than `/etc/hosts`. It is
/// hand-maintained by people who care about it, it is very often a symlink into
/// a dotfiles repository, and half of what is in it is directives this module
/// has no opinion about.
///
/// **Byte equality alone cannot fail here**, which is the lesson
/// `HostsRoundTripTests` records one file over: a parser that reads nothing and
/// keeps every line verbatim reproduces every case below exactly. So each case
/// also says how many hosts and how many known fields it holds, and a parser
/// that stopped reading fails on the counts before the bytes.
final class SSHConfigRoundTripTests: XCTestCase {

    /// The shape most people's file is: two blocks, aligned with four spaces,
    /// a comment above each.
    private let ordinary = """
    # work
    Host build
        HostName build.internal.example
        User rstrlnkv
        Port 2222
        IdentityFile ~/.ssh/id_ed25519

    # a box that moved
    Host attic
        HostName 192.0.2.31
        User root

    """

    /// `Match`, `Include` and directives this module does not know. All of it
    /// has to survive: Helm edits four fields and is a faithful copier of
    /// everything else.
    private let withMatchAndInclude = """
    Include ~/.ssh/config.d/*.conf

    Host *
        ServerAliveInterval 60
        AddKeysToAgent yes
        UseKeychain yes

    Match host build exec "test -n \\"$WORK\\""
        ForwardAgent yes
        HostName build.vpn.example

    Host gate
        HostName gate.example
        ProxyJump none
        User rstrlnkv

    """

    /// Tabs, `=` separators, mixed case keywords and no trailing newline —
    /// each of them legal, and each of them a way to normalise a file nobody
    /// asked to have normalised.
    private let oddButLegal = "host\tOLD\n\tHostName\t=\told.example\n\tuser\troot"

    /// CRLF throughout. `components(separatedBy:)` throws the ending away,
    /// which is how a CRLF file comes back as LF and every line in it reads as
    /// changed.
    private let crlf = "Host win\r\n    HostName win.example\r\n    User admin\r\n"

    /// A file that is nothing but comments and blank lines — no host at all.
    private let noHosts = "# nothing here yet\n\n#\tnot even a Host line\n"

    /// **Compares the bytes, because `XCTAssertEqual` on two `String`s does
    /// not**: Swift's `==` is canonical equivalence, so a parser that
    /// re-normalised what it read would pass while rewriting every decomposed
    /// name in somebody's file. The same reader `HostsRoundTripTests` uses, for
    /// the same reason.
    private func assertRoundTrips(_ text: String, _ what: String,
                                  hosts expectedHosts: Int, fields expectedFields: Int,
                                  editable expectedEditable: Int? = nil,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let document = SSHConfigFile.parse(text)
        XCTAssertEqual(document.hosts.count, expectedHosts,
                       "\(what): host lines read", file: file, line: line)
        XCTAssertEqual(document.fields.count, expectedFields,
                       "\(what): known fields read", file: file, line: line)
        // **Read, and belonging to a host** are two counts, and the difference
        // is the `Match` rule: a `HostName` inside a `Match` block is a field
        // this parser can see and a field no table may offer to edit, because
        // the block it is in applies on a condition the table cannot show.
        if let expectedEditable {
            XCTAssertEqual(document.fields.filter { $0.host != nil }.count, expectedEditable,
                           "\(what): fields belonging to a host block",
                           file: file, line: line)
        }
        let rendered = SSHConfigFile.render(document)
        XCTAssertEqual(Array(rendered.utf8), Array(text.utf8),
                       "\(what): rendered bytes differ from what was parsed",
                       file: file, line: line)
    }

    func testAnOrdinaryConfigSurvives() {
        assertRoundTrips(ordinary, "two blocks", hosts: 2, fields: 6, editable: 6)
    }

    func testMatchIncludeAndUnknownDirectivesSurvive() {
        // `Match` is not a host line: its patterns are a different grammar, and
        // a table that offered to edit `HostName` inside one would be offering
        // to edit a block whose condition it cannot show.
        // Two `Host` lines, not three: `Match` is not one of them. Three known
        // fields are read — `HostName` under the `Match`, then `HostName` and
        // `User` under `Host gate` — and only the last two belong to a block.
        assertRoundTrips(withMatchAndInclude, "match and include",
                         hosts: 2, fields: 3, editable: 2)
    }

    func testTabsEqualsSignsAndMixedCaseSurvive() {
        // Three hosts' worth of ways to write the same thing, and no trailing
        // newline — a file that gains one has been rewritten.
        assertRoundTrips(oddButLegal, "odd but legal", hosts: 1, fields: 2)
    }

    func testACRLFFileIsNotQuietlyConvertedToLF() {
        assertRoundTrips(crlf, "CRLF", hosts: 1, fields: 2)
    }

    func testAFileWithNoHostsIsStillItself() {
        assertRoundTrips(noHosts, "no hosts", hosts: 0, fields: 0)
    }

    /// The empty file is the one every parser gets wrong in the same way, by
    /// answering with a newline nobody typed.
    func testTheEmptyFileStaysEmpty() {
        assertRoundTrips("", "empty", hosts: 0, fields: 0)
    }
}

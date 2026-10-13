import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// **The software-name redaction and the refusal line it feeds, at the inputs
/// `APathWhoseLeafIsANameTests` did not feed in.** A leaf with two dots, an
/// extension in capitals, a bundle id that ends in a word the extension list
/// also holds, an id of two words or of four, a bundle whose name has a dot or a
/// hyphen in it, and an app whose name happens to be a piece of the line Helm
/// composes in place of macOS's sentence.
///
/// Every line-reading case asserts that its line was written before asserting
/// what the line carries or lacks: the log is off in a test process, and an
/// absence proves nothing about a line that was never there.
final class RedactSoftwareLeavesNobodyFedTests: XCTestCase {

    /// One per test, so a line another case — or another run — wrote cannot
    /// answer for this one.
    private let module = "redact-leaves-\(UUID().uuidString.prefix(8))"

    /// A parent nobody creates: the trashing closure throws before anything is
    /// touched, and the ancestry read is stubbed, so the paths need not exist.
    private let parent = NSTemporaryDirectory() + "helm-redact-leaves-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == module }.map(\.message)
    }

    /// Runs one path through the shared loop with macOS refusing it as told,
    /// and returns the reason the batch reported plus the one line it logged.
    private func refuse(_ path: String, domain: String, code: Int, saying said: String,
                        file: StaticString = #filePath, line: UInt = #line)
        -> (reason: TrashFailure.Reason?, line: String?) {
        HelmLog.shared.clearTail()
        let result = HelmTrash.remove(
            allowed: [path], module: module, leaf: .softwareName,
            ancestry: { _ in nil },
            trashing: { _ in
                throw NSError(domain: domain, code: code,
                              userInfo: [NSLocalizedDescriptionKey: said])
            })
        let lines = logged.filter { $0.hasPrefix("trash refused ") }
        XCTAssertEqual(lines.count, 1, "precondition: exactly one refusal line: \(logged)",
                       file: file, line: line)
        return (result.refused.first?.reason, lines.first)
    }

    // MARK: - The leaf

    /// Two dots, neither of them a known type at the end: the whole leaf is the
    /// name. `deletingPathExtension` read `Foo.app.zip` as a stem `Foo.app` and
    /// an extension `zip`, which tags a different string.
    func testALeafWhoseLastSuffixIsUnknownIsTaggedWhole() {
        let home = "/Users/x"
        XCTAssertEqual(Redact.path("/Users/x/Downloads/Foo.app.zip", leaf: .softwareName, home: home),
                       "~/Downloads/" + Redact.app("Foo.app.zip"))
        XCTAssertEqual(Redact.path("/Users/x/Library/Containers/com.acme.Secret",
                                   leaf: .softwareName, home: home),
                       "~/Library/Containers/" + Redact.app("com.acme.Secret"))
    }

    /// A known type in another case is still a known type, and it is kept as
    /// spelled; the stem in front of it is what is tagged.
    func testAKnownExtensionInAnyCaseKeepsItsSpellingAndTagsTheStem() {
        let home = "/Users/x"
        XCTAssertEqual(Redact.path("/Applications/Foo.APP", leaf: .softwareName, home: home),
                       "/Applications/" + Redact.app("Foo") + ".APP")
        XCTAssertEqual(Redact.path("/Users/x/Library/Saved Application State/com.acme.Secret.SAVEDSTATE",
                                   leaf: .softwareName, home: home),
                       "~/Library/Saved Application State/" + Redact.app("com.acme.Secret") + ".SAVEDSTATE")
    }

    /// **One app, one tag across its leftovers** — the property a tag exists
    /// for: «the same one as three lines up?». A container named by the id and
    /// a preferences file named by the id plus `.plist` are the same app.
    func testOneAppWearsOneTagAcrossItsLeftovers() {
        let home = "/Users/x"
        let id = "com.acme.SecretTool"
        let leaves = ["Library/Containers/\(id)", "Library/Caches/\(id)",
                      "Library/Application Support/\(id)", "Library/HTTPStorages/\(id)",
                      "Library/Preferences/\(id).plist",
                      "Library/Saved Application State/\(id).savedState",
                      "Library/HTTPStorages/\(id).binarycookies"]
        for leaf in leaves {
            let shown = Redact.path("\(home)/\(leaf)", leaf: .softwareName, home: home)
            XCTAssertTrue((shown as NSString).lastPathComponent.hasPrefix(Redact.app(id)),
                          "«\(leaf)» is not tagged as the app «\(id)» is: \(shown)")
            XCTAssertFalse(shown.contains("SecretTool"), "the product's name survived: \(shown)")
        }
    }

    /// **The same property for an id that ends in a word the extension list
    /// holds.** Read as `com.acme` plus `.log`, `com.acme.log`'s container would
    /// wear a different tag from its preferences file, `com.acme.log` plus
    /// `.plist` — and the container's would be the vendor's, shared with every
    /// other app of that vendor whose id ends in a listed word.
    func testAnIDEndingInAListedWordWearsOneTagAcrossItsLeftovers() {
        let home = "/Users/x"
        for id in ["com.acme.log", "com.acme.db", "com.acme.app"] {
            let container = Redact.path("\(home)/Library/Containers/\(id)", leaf: .softwareName, home: home)
            let prefs = Redact.path("\(home)/Library/Preferences/\(id).plist", leaf: .softwareName, home: home)
            XCTAssertTrue((prefs as NSString).lastPathComponent.hasPrefix(Redact.app(id)),
                          "precondition: the plist carries the id's tag: \(prefs)")
            XCTAssertTrue((container as NSString).lastPathComponent.hasPrefix(Redact.app(id)),
                          "«\(id)»: the container and the plist wear different tags — "
                          + "\(container) against \(prefs)")
        }
    }

    // MARK: - The ids and bundles at the inputs of the folder rule

    private let userHome = "/Users/x"

    /// The last component of a path as a log line spells it, for a path under
    /// the user's home.
    private func shownLeaf(_ relative: String) -> String {
        (Redact.path("\(userHome)/\(relative)", leaf: .softwareName, home: userHome) as NSString)
            .lastPathComponent
    }

    /// The extensions the rule reads as a type, taken from the list the rule
    /// itself holds rather than from a copy of it here, so a word added to that
    /// list is fed to every row that calls this. Each word is then checked against what
    /// the rule does with it: behind a three-word name it must stay in clear and
    /// leave the rest tagged. A scan that read nothing, or a word the rule does
    /// not act on, fails here and not as a row that has nothing to loop over.
    private func listedWords() throws -> [String] {
        let source = try RepoSource.text(of: "Sources/HelmRuntime/Redact.swift")
        let opening = "knownExtensions: Set<String> = ["
        guard let start = source.range(of: opening),
              let end = source[start.upperBound...].range(of: "]") else {
            XCTFail("the list of extensions was not found in Redact.swift")
            return []
        }
        let words = source[start.upperBound..<end.lowerBound]
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        XCTAssertGreaterThanOrEqual(words.count, 15, "the scan read too few words: \(words)")
        for anchor in ["app", "plist", "log", "db"] {
            XCTAssertTrue(words.contains(anchor), "the scan did not read «\(anchor)»: \(words)")
        }
        for word in words {
            XCTAssertEqual(shownLeaf("Library/Foo/com.acme.tool.\(word)"),
                           Redact.app("com.acme.tool") + "." + word,
                           "«\(word)» was read from the list but the rule does not treat it as a type")
        }
        return words
    }

    /// **Every word the rule reads as a type, as the last word of an id.** The
    /// folders of that id are named by it, whole: one tag, the same one on every
    /// kind of folder, and not the vendor's — two ids of one vendor must not
    /// wear one tag, or a reader of the log takes two apps for one.
    func testEveryListedWordAsAnIDsLastWordIsTaggedWholeAcrossItsFolders() throws {
        let words = try listedWords()
        var containerLeaves: [String] = []
        for word in words {
            let id = "com.acme.\(word)"
            for folder in ["Containers", "Caches", "Application Support", "HTTPStorages"] {
                // `HTTPStorages/com.acme.binarycookies` is the cookie jar of `com.acme` as
                // much as the folder of the id `com.acme.binarycookies`; no string decides
                // it, and the rule reads it as the cookie jar.
                if folder == "HTTPStorages" && word == "binarycookies" { continue }
                let shown = shownLeaf("Library/\(folder)/\(id)")
                XCTAssertNotEqual(shown, id, "precondition: «\(folder)/\(id)» was redacted at all")
                XCTAssertEqual(shown, Redact.app(id),
                               "«\(folder)/\(id)» is not tagged as the id is: \(shown)")
                XCTAssertFalse(shown.contains("acme"), "the vendor survived: \(shown)")
                XCTAssertFalse(shown.hasSuffix(".\(word)"), "the last word survived: \(shown)")
            }
            containerLeaves.append(shownLeaf("Library/Containers/\(id)"))
        }
        XCTAssertEqual(Set(containerLeaves).count, words.count,
                       "ids of one vendor share a tag: \(containerLeaves)")
    }

    /// **The same ids under the other suffixes a leftover of an id wears.** A
    /// preferences file, a saved state and a cookie jar are the id plus a type;
    /// the type stays as spelled and the id in front is the one tag its folders
    /// wear.
    func testEveryListedWordAsAnIDsLastWordWearsItsTagUnderEachSuffix() throws {
        let words = try listedWords()
        for word in words {
            let id = "com.acme.\(word)"
            for (folder, suffix) in [("Preferences", "plist"), ("Saved Application State", "savedState"),
                                     ("HTTPStorages", "binarycookies"), ("Preferences", "PLIST")] {
                let shown = shownLeaf("Library/\(folder)/\(id).\(suffix)")
                XCTAssertNotEqual(shown, "\(id).\(suffix)", "precondition: «\(id).\(suffix)» was redacted at all")
                XCTAssertEqual(shown, Redact.app(id) + "." + suffix,
                               "«\(id).\(suffix)» is not the id's tag and its type: \(shown)")
                XCTAssertEqual((shown as NSString).deletingPathExtension, shownLeaf("Library/Containers/\(id)"),
                               "«\(id).\(suffix)» and the id's container wear different tags")
                XCTAssertFalse(shown.contains("acme"), "the vendor survived: \(shown)")
            }
        }
    }

    /// **The word in capitals.** A type is a type in any case, and an id is an id
    /// in any case: `com.acme.LOG` is one tag, in its folder and in the file
    /// that carries a type after it.
    func testAnIDEndingInAListedWordInCapitalsWearsOneTag() throws {
        let words = try listedWords()
        for word in words {
            for cased in [word.uppercased(), word.capitalized] {
                let id = "com.acme.\(cased)"
                let container = shownLeaf("Library/Containers/\(id)")
                XCTAssertNotEqual(container, id, "precondition: «\(id)» was redacted at all")
                XCTAssertEqual(container, Redact.app(id), "«\(id)» is not tagged whole: \(container)")
                for suffix in ["plist", "PLIST", "savedState"] {
                    let shown = shownLeaf("Library/Preferences/\(id).\(suffix)")
                    XCTAssertEqual(shown, Redact.app(id) + "." + suffix,
                                   "«\(id).\(suffix)» is not the id's tag and its type: \(shown)")
                }
                XCTAssertFalse(container.lowercased().contains("acme"), "the vendor survived: \(container)")
            }
        }
    }

    /// **A bundle named `Acme.app` and the container of the id `com.acme.app`.**
    /// Both end in a listed word, and the rule does not tell the two apart by the
    /// leaf: the folder it sits in says which it is, `Applications` for a bundle that
    /// is its name and a type, `Containers` for an id. What holds either way is that
    /// neither names anybody and neither wears the vendor's tag, which every id of
    /// that vendor would share.
    func testABundleAndTheContainerOfAnIDSpelledLikeItAreBothHidden() {
        let bundle = shownLeaf("Applications/Acme.app")
        let container = shownLeaf("Library/Containers/com.acme.app")
        XCTAssertNotEqual(bundle, "Acme.app", "precondition: the bundle was redacted at all")
        XCTAssertNotEqual(container, "com.acme.app", "precondition: the container was redacted at all")
        XCTAssertEqual(bundle, Redact.app("Acme") + ".app", "the bundle is its name's tag and its type: \(bundle)")
        XCTAssertEqual(container, Redact.app("com.acme.app"), "the container is the id's tag: \(container)")
        for shown in [bundle, container] {
            XCTAssertFalse(shown.lowercased().contains("acme"), "the name survived: \(shown)")
            XCTAssertFalse(shown.hasPrefix(Redact.app("com.acme")), "the vendor's tag was worn: \(shown)")
        }
        XCTAssertNotEqual(container, shownLeaf("Library/Containers/com.acme.db"),
                          "two ids of one vendor wear one tag")
    }

    /// **A sentence that quotes a leftover reads as the path spells it.** The
    /// tag the sentence gets and the tag the path gets come from one reading of
    /// the leaf, so a line that quotes `com.acme.log` and a line that names the
    /// folder show the same word — for every listed word, in either case, and for
    /// the leaf with each suffix. Each leaf is quoted under both readings: under `Containers`,
    /// where a leaf with a listed extension is read whole, and under `Applications`
    /// and `Preferences`, which are not folders of the table, where it is read as
    /// a name and a type and the type stays in clear. Both readings are checked to
    /// have happened, so a row that drifted to one of them would say so.
    func testASentenceQuotingALeafGetsTheTagThePathGets() throws {
        let words = try listedWords()
        var leaves = ["Acme.app", "Zebra-Tool.APP", "com.acme.Secret.plist"]
        for word in words {
            for cased in [word, word.uppercased()] {
                let id = "com.acme.\(cased)"
                leaves += [id, id + ".plist", id + ".savedState", id + ".binarycookies"]
            }
        }
        XCTAssertTrue(shownLeaf("Applications/Acme.app").hasSuffix(".app"),
                      "precondition: outside the table the type stays in clear")
        XCTAssertFalse(shownLeaf("Library/Containers/Acme.app").hasSuffix(".app"),
                       "precondition: inside the table the leaf is read whole")
        for folder in ["Library/Containers", "Applications", "Library/Preferences"] {
            for leaf in leaves {
                let path = "\(userHome)/\(folder)/\(leaf)"
                let said = Redact.naming("cannot open \(leaf) now", software: path, leaf: .softwareName)
                XCTAssertNotEqual(said, "cannot open \(leaf) now",
                                  "precondition: «\(folder)/\(leaf)» was replaced at all")
                XCTAssertEqual(said, "cannot open \(shownLeaf("\(folder)/\(leaf)")) now",
                               "the sentence and the path spell «\(folder)/\(leaf)» differently")
            }
        }
    }

    // MARK: - The ids, the bundles and the folders the rule reads

    /// A path written out in full, as a log line spells it for the user's home.
    private func shown(_ path: String) -> String {
        Redact.path(path, leaf: .softwareName, home: userHome)
    }

    /// **An id of four words.** `Plugin` is a listed word in another case; the
    /// container of the id is the id whole, and its preferences file is the same
    /// tag with the type after it, so the two read as one app.
    func testAFourWordIDAndItsPreferencesWearOneTag() {
        let id = "com.acme.tool.Plugin"
        XCTAssertEqual(shownLeaf("Library/Containers/\(id)"), Redact.app(id))
        XCTAssertEqual(shownLeaf("Library/Preferences/\(id).plist"), Redact.app(id) + ".plist")
        XCTAssertFalse(shownLeaf("Library/Containers/\(id)").lowercased().contains("acme"))
    }

    /// **An id of two words.** A leftover the uninstaller looks for under the name
    /// `X.Y` itself, or under `X.Y` and one type, wears the tag of `X.Y`: the
    /// folders, the preferences file, the saved state, and the cookie jar both in
    /// `HTTPStorages` and in `Cookies`. What its globs match around the id
    /// (`Containers/X.Y.helper`, `Preferences/ByHost/X.Y.<host>.plist`) is another
    /// name and wears that name's tag.
    func testATwoWordIDWearsOneTagAcrossItsLeftovers() {
        let id = "X.Y"
        for folder in ["Containers", "Caches", "Application Support", "Group Containers", "Logs",
                       "WebKit", "Application Scripts", "HTTPStorages"] {
            XCTAssertEqual(shownLeaf("Library/\(folder)/\(id)"), Redact.app(id), "«\(folder)/\(id)»")
        }
        for (folder, suffix) in [("Preferences", "plist"), ("Saved Application State", "savedState"),
                                 ("HTTPStorages", "binarycookies"), ("Cookies", "binarycookies")] {
            XCTAssertEqual(shownLeaf("Library/\(folder)/\(id).\(suffix)"), Redact.app(id) + "." + suffix,
                           "«\(folder)/\(id).\(suffix)»")
        }
    }

    /// **A bundle whose name has a dot or a hyphen in it.** `/Applications/zoom.us.app`
    /// is the name `zoom.us` and the type `.app`; the folders the same app keeps in
    /// `Application Support` and `Logs` are named `zoom.us`, and all three wear one
    /// tag. The same holds with a hyphen, with a dot and a hyphen, with a space, and
    /// with a name in another script. Nothing of the name stays in clear.
    func testADottedBundleWearsTheTagOfTheFoldersNamedLikeIt() {
        for name in ["zoom.us", "Xcode-15.2", "Acme-Pro.Beta", "Xcode 15.2", "Кот.Пёс"] {
            let bundle = shown("/Applications/\(name).app")
            XCTAssertEqual(bundle, "/Applications/" + Redact.app(name) + ".app", "«\(name).app»")
            XCTAssertEqual(shown("\(userHome)/Library/Application Support/\(name)"),
                           "~/Library/Application Support/" + Redact.app(name), "«\(name)» in Application Support")
            XCTAssertEqual(shown("\(userHome)/Library/Logs/\(name)"),
                           "~/Library/Logs/" + Redact.app(name), "«\(name)» in Logs")
            XCTAssertFalse(bundle.contains(name), "the name survived: \(bundle)")
        }
    }

    /// **A vendor with a hyphen.** `com.my-corp.log` ends in a listed word; its
    /// container is the id whole and its preferences file the same tag with
    /// `.plist`, and the hyphen makes no difference to either.
    func testAHyphenatedVendorsContainerMatchesItsPreferences() {
        let id = "com.my-corp.log"
        XCTAssertEqual(shownLeaf("Library/Containers/\(id)"), Redact.app(id))
        XCTAssertEqual(shownLeaf("Library/Preferences/\(id).plist"), Redact.app(id) + ".plist")
        XCTAssertFalse(shownLeaf("Library/Containers/\(id)").contains("corp"))
    }

    /// **An id that repeats a listed word, and the vendor's own.**
    /// `Preferences/com.acme.plist` belongs to the id `com.acme`, whose container
    /// wears the same tag; `Containers/com.acme.log.log` belongs to the id
    /// `com.acme.log.log`, whose preferences file wears the same tag, and that tag
    /// is not the vendor's.
    func testAnIDWhoseLastWordRepeatsAListedWordWearsItsOwnTag() {
        XCTAssertEqual(shownLeaf("Library/Preferences/com.acme.plist"), Redact.app("com.acme") + ".plist")
        XCTAssertEqual(shownLeaf("Library/Containers/com.acme"), Redact.app("com.acme"))
        XCTAssertEqual(shownLeaf("Library/Containers/com.acme.log.log"), Redact.app("com.acme.log.log"))
        XCTAssertEqual(shownLeaf("Library/Preferences/com.acme.log.log.plist"),
                       Redact.app("com.acme.log.log") + ".plist")
        XCTAssertNotEqual(shownLeaf("Library/Containers/com.acme.log.log"),
                          shownLeaf("Library/Containers/com.acme"), "two ids of one vendor wear one tag")
    }

    /// **The one leaf no string decides.** `HTTPStorages/com.acme.binarycookies`
    /// is the folder of the id `com.acme.binarycookies` as much as the cookie jar
    /// of `com.acme`. This row pins what the code answers, not what the file is:
    /// the cookie jar, with its type in clear, in either case of the type. In the
    /// other folders of the table the same leaf is the id whole.
    func testTheLeafThatIsBothAFolderAndACookieJarIsReadAsTheCookieJar() {
        XCTAssertEqual(shownLeaf("Library/HTTPStorages/com.acme.binarycookies"),
                       Redact.app("com.acme") + ".binarycookies")
        XCTAssertEqual(shownLeaf("Library/HTTPStorages/com.acme.BinaryCookies"),
                       Redact.app("com.acme") + ".BinaryCookies")
        XCTAssertEqual(shownLeaf("Library/Containers/com.acme.binarycookies"),
                       Redact.app("com.acme.binarycookies"))
    }

    /// **Outside a library the folder's name decides nothing.** `Caches` under
    /// `/Applications` is a folder that holds a bundle, and the bundle is a name
    /// and a type. The same holds for a table folder whose parent is not named
    /// `Library` exactly as spelled, and for a leaf one level below a table
    /// folder; a `Library` further down the path reads its own table folders.
    func testAFolderOfTheTableOutsideALibraryReadsTheLeafAsANameAndAType() {
        XCTAssertEqual(shown("/Applications/Caches/Tool.app"), "/Applications/Caches/" + Redact.app("Tool") + ".app")
        XCTAssertEqual(shownLeaf("Stuff/Caches/com.acme.log"), Redact.app("com.acme") + ".log")
        XCTAssertEqual(shownLeaf("library/Caches/com.acme.log"), Redact.app("com.acme") + ".log")
        XCTAssertEqual(shownLeaf("Library/Containers/com.acme.Data/com.acme.log"), Redact.app("com.acme") + ".log")
        XCTAssertEqual(shownLeaf("Library/Containers/com.acme/Data/Library/Caches/com.acme.log"),
                       Redact.app("com.acme.log"))
    }

    /// **A cost the rule names.** A bundle that lies directly in one of the
    /// folders of the table is read whole, its type not in clear — but still a tag,
    /// and still not the vendor's.
    func testABundleDirectlyInAFolderOfTheTableIsTaggedWhole() {
        XCTAssertEqual(shownLeaf("Library/Containers/Acme.app"), Redact.app("Acme.app"))
        XCTAssertEqual(shownLeaf("Library/Application Support/Acme.app"), Redact.app("Acme.app"))
    }

    /// **The system's library and the data volume's spelling of the user's.** The
    /// rule reads the two folders above the leaf and never the home, so the
    /// library at the root of the disk and the one reached through
    /// `/System/Volumes/Data` are read as the user's own is.
    func testTheSystemLibraryAndTheDataVolumeSpellingReadTheSameWay() {
        XCTAssertEqual(shown("/Library/Application Support/com.acme.db"),
                       "/Library/Application Support/" + Redact.app("com.acme.db"))
        XCTAssertEqual(shown("/System/Volumes/Data/Users/x/Library/Caches/com.acme.log"),
                       "~/Library/Caches/" + Redact.app("com.acme.log"))
        XCTAssertEqual(shown("/System/Volumes/Data/Users/x/Applications/Acme.app"),
                       "~/Applications/" + Redact.app("Acme") + ".app")
    }

    /// **A sentence that quotes a bundle with a dot and a hyphen in its name.** The
    /// name is replaced wherever the sentence quotes it, whether it quotes the
    /// name alone or the bundle with its type.
    func testASentenceQuotingADottedBundleReplacesItsName() {
        let path = "/Applications/Xcode-15.2.app"
        let alone = Redact.naming("“Xcode-15.2” could not be moved", software: path, leaf: .softwareName)
        XCTAssertEqual(alone, "“" + Redact.app("Xcode-15.2") + "” could not be moved")
        let whole = Redact.naming("cannot open Xcode-15.2.app now", software: path, leaf: .softwareName)
        XCTAssertEqual(whole, "cannot open " + Redact.app("Xcode-15.2") + ".app now")
        XCTAssertFalse(alone.contains("Xcode") || whole.contains("Xcode"))
    }

    // MARK: - The folders the uninstaller's matcher names

    /// A folder of a library and the one suffix an id wears in it, read off a line
    /// of the matcher; `nil` where the line appends no suffix to the id.
    private struct MatcherFolder: Hashable {
        let folder: String
        let suffix: String?
    }

    /// Reads every line of `source` that builds a candidate from a folder of a
    /// library (`add(u("<folder>"…`), taking the suffix the line appends to the
    /// id (`….<suffix>")`) if it appends one. A glob line is read as its first
    /// folder and its suffix; the leaf it matches may sit one folder deeper
    /// (`Preferences/ByHost`), which the scan does not follow. Returns what was
    /// read, how many lines, and for each folder and suffix the disagreement
    /// between what the redaction shows for `Library/<folder>/com.acme.log` (with
    /// the suffix after it) and the id's own tag.
    private func readMatcher(_ source: String) throws -> (read: [MatcherFolder], lines: Int, disagreements: [String]) {
        let folderPattern = try NSRegularExpression(pattern: #"add\(u\("([^"]+)""#)
        let suffixPattern = try NSRegularExpression(pattern: #"\.(\w+)"\)"#)
        func capture(_ pattern: NSRegularExpression, in line: String) -> String? {
            let whole = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: whole),
                  let range = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[range])
        }
        var read: [MatcherFolder] = []
        var lines = 0
        for line in source.components(separatedBy: "\n") {
            guard let folder = capture(folderPattern, in: line) else { continue }
            lines += 1
            let entry = MatcherFolder(folder: folder, suffix: capture(suffixPattern, in: line))
            if !read.contains(entry) { read.append(entry) }
        }
        var disagreements: [String] = []
        for entry in read {
            let expected = Redact.app("com.acme.log") + (entry.suffix.map { "." + $0 } ?? "")
            let leaf = "com.acme.log" + (entry.suffix.map { "." + $0 } ?? "")
            let got = shownLeaf("Library/\(entry.folder)/\(leaf)")
            if got != expected { disagreements.append("\(entry.folder)/\(leaf) shows \(got)") }
        }
        return (read, lines, disagreements)
    }

    /// **Every folder the matcher builds a leftover in shows the id's own tag.**
    /// The matcher's source is read, not a copy of its folders: a folder that the
    /// matcher names by a bare id and the table of the redaction lacks would show
    /// the tag of `com.acme` and the type `.log` for the id `com.acme.log`, and the
    /// id would wear two tags. The scan is checked to have read the folders and
    /// suffixes the rule's cells depend on before anything is said about what they
    /// show.
    func testEveryFolderTheMatcherNamesShowsTheIDsOwnTag() throws {
        let source = try RepoSource.text(of: "Sources/Modules/Uninstaller/Engine/Logic/LeftoverMatcher.swift")
        let (read, lines, disagreements) = try readMatcher(source)
        XCTAssertGreaterThanOrEqual(lines, 15, "the scan read too few lines of the matcher: \(lines)")
        for (folder, suffix) in [("Containers", nil), ("Group Containers", nil), ("HTTPStorages", nil),
                                 ("HTTPStorages", "binarycookies"), ("Preferences", "plist"),
                                 ("Saved Application State", "savedState"), ("Cookies", "binarycookies")] as [(String, String?)] {
            XCTAssertTrue(read.contains(MatcherFolder(folder: folder, suffix: suffix)),
                          "the scan did not read «\(folder)» with suffix \(suffix ?? "none"): \(read)")
        }
        XCTAssertEqual(disagreements, [], "a folder of the matcher shows another tag than the id's")
    }

    /// **The matcher guard can fail.** A matcher that named a folder by a bare id
    /// which the table lacks, and one that appended a suffix the rule does not read
    /// as a type, are each reported; the folders the table holds are not.
    func testTheMatcherGuardNamesAFolderTheTableLacks() throws {
        let clean = try readMatcher(#"add(u("Caches", id), .caches)"#)
        XCTAssertEqual(clean.read, [MatcherFolder(folder: "Caches", suffix: nil)], "precondition: the line was read")
        XCTAssertEqual(clean.disagreements, [])
        let bare = try readMatcher(#"add(u("Mail", id), .mail)"#)
        XCTAssertEqual(bare.read, [MatcherFolder(folder: "Mail", suffix: nil)], "precondition: the line was read")
        XCTAssertEqual(bare.disagreements.count, 1, "a bare folder the table lacks went unreported")
        let suffixed = try readMatcher(#"add(u("Mail", "\(id).mbox"), .mail)"#)
        XCTAssertEqual(suffixed.read, [MatcherFolder(folder: "Mail", suffix: "mbox")], "precondition: the line was read")
        XCTAssertEqual(suffixed.disagreements.count, 1, "a suffix the rule does not know went unreported")
    }

    /// **The team-prefixed folder.** A group container is named `<team>.<id>`; the
    /// leaf is the whole name, tagged as one, however the id ends.
    func testAGroupContainerNamedByATeamAndAnIDEndingInAListedWordIsTaggedWhole() {
        XCTAssertEqual(shownLeaf("Library/Group Containers/ABCDE12345.com.acme.log"),
                       Redact.app("ABCDE12345.com.acme.log"))
    }

    /// **The floor is on the name.** Four characters of it are replaced in a
    /// sentence and three are not, whatever the extension after them adds.
    func testASentenceKeepsAThreeCharacterNameAndReplacesAFourCharacterOne() {
        let three = Redact.naming("open Abc now", software: "\(userHome)/Applications/Abc.app", leaf: .softwareName)
        let four = Redact.naming("open Abcd now", software: "\(userHome)/Applications/Abcd.app", leaf: .softwareName)
        XCTAssertEqual(four, "open " + Redact.app("Abcd") + " now", "a name of four characters is replaced")
        XCTAssertEqual(three, "open Abc now", "a name of three characters is left in a sentence")
    }

    // MARK: - The line Helm composes instead of macOS's sentence

    /// **Each code is logged with the reason the batch returned**, and the
    /// system's sentence — which quotes the software — is not.
    func testEachCodeIsLoggedWithTheReasonTheBatchReturned() {
        let stem = "Zq\(UUID().uuidString.prefix(6))"
        let cases: [(path: String, domain: String, code: Int, reason: TrashFailure.Reason)] = [
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 513, .noPermission),
            ("\(parent)/Library/Containers/com.acme.\(stem)", NSCocoaErrorDomain, 513, .needsFullDiskAccess),
            ("\(parent)/Library/Group Containers/ABCDE12345.com.acme.\(stem)", NSCocoaErrorDomain, 513,
             .needsFullDiskAccess),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, NSFileNoSuchFileError, .missing),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 257, .systemRefused),
            ("\(parent)/\(stem).app", NSPOSIXErrorDomain, Int(EPERM), .systemRefused),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 642, .readOnlyVolume),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 640, .diskFull),
        ]
        for c in cases {
            let said = "“\(stem)” couldn’t be moved to the trash because you don’t have "
                + "permission to access it."
            let (reason, line) = refuse(c.path, domain: c.domain, code: c.code, saying: said)
            XCTAssertEqual(reason, c.reason, "\(c.domain) \(c.code) at \(c.path)")
            guard let line else { continue }
            XCTAssertTrue(line.hasSuffix(": \(c.domain) \(c.code), \(c.reason.rawValue)"),
                          "the line does not carry the domain, the code and the reason: \(line)")
            XCTAssertFalse(line.contains(stem), "the software's name reached the log: \(line)")
            XCTAssertFalse(line.contains("couldn’t be moved"), "macOS's sentence reached the log: \(line)")
        }
    }

    /// **An app whose name is a piece of the composed verdict.** The verdict is
    /// Helm's own text — a domain, a code, a reason — and cannot quote the
    /// software, so the software's name does not touch it. Passed through
    /// `Redact.naming`, which replaces the stem wherever it occurs, `Cocoa.app`
    /// would turn the domain into `NSapp#…ErrorDomain` and `missing.app` would
    /// replace the reason outright; and because the surrounding text is a known
    /// constant the tag could be read back: the redaction itself would spell the
    /// name it was hiding.
    func testTheVerdictIsNotRewrittenByTheSoftwaresName() {
        let cases: [(stem: String, code: Int, reason: TrashFailure.Reason)] = [
            ("Cocoa", 513, .noPermission),
            ("Error", 513, .noPermission),
            ("Permission", 513, .noPermission),
            ("missing", NSFileNoSuchFileError, .missing),
        ]
        for c in cases {
            let (reason, line) = refuse("\(parent)/\(c.stem).app", domain: NSCocoaErrorDomain,
                                        code: c.code, saying: "irrelevant")
            XCTAssertEqual(reason, c.reason, "precondition: \(c.stem).app classified")
            guard let line else { continue }
            XCTAssertTrue(line.hasSuffix(": \(NSCocoaErrorDomain) \(c.code), \(c.reason.rawValue)"),
                          "«\(c.stem).app» rewrote the verdict: \(line)")
        }
    }
}

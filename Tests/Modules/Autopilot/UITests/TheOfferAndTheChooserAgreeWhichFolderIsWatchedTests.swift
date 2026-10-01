import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// Two answers to «is this the folder already watched»: `PresetOffer.offered`
/// asks `WatchScope.sameFolder`, and the chooser in a preset's sheet asks the
/// view model's own `watchedFolder(at:)` (reached here through `draftFolder`).
/// Where they disagree, the offer calls a folder new that the chooser joins to
/// the stored one, or the other way round — a second `WatchedFolder` for one
/// directory, swept at once on Done.
///
/// Every input is on disk in a scratch home, and each is asked of both.
@MainActor
final class TheOfferAndTheChooserAgreeWhichFolderIsWatchedTests: XCTestCase {

    private var home: URL!

    private func stand() throws {
        home = scratchDirectory("offer-and-chooser")
        let fm = FileManager.default
        for sub in ["Downloads", "Pictures"] {
            try fm.createDirectory(at: home.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(at: home.appendingPathComponent("DL"),
                                  withDestinationURL: home.appendingPathComponent("Downloads"))
        try fm.createSymbolicLink(at: home.appendingPathComponent("DL2"),
                                  withDestinationURL: home.appendingPathComponent("DL"))
        try fm.createSymbolicLink(atPath: home.appendingPathComponent("DLrel").path,
                                  withDestinationPath: "Downloads")
        // A link whose target is not there yet: the watched folder was renamed
        // away, and a link of another name still points at the old one.
        try fm.createSymbolicLink(at: home.appendingPathComponent("GoneLink"),
                                  withDestinationURL: home.appendingPathComponent("Gone"))
    }

    private func verdicts(watched: String, candidate: String) async
        -> (offer: Bool, chooser: Bool?) {
        let folder = WatchedFolder(id: "w", path: watched)
        let model = AutopilotViewModel(
            vm: ModuleViewModel(transport: AutopilotWire(folders: [folder])),
            presetFolders: FakePresetFolders(home: home.path), home: home.path)
        await model.load()
        let chosen = model.draftFolder(at: candidate)
        return (WatchScope.sameFolder(watched, candidate), chosen.map { $0.id == folder.id })
    }

    func testBothAnswerAlikeForEverySpellingOfAnExistingFolder() async throws {
        try stand()
        let h = home.path, downloads = h + "/Downloads"
        var candidates = [
            downloads, downloads + "/", h + "/DL", h + "/DL2", h + "/DLrel", h + "/downloads",
            h + "/DOWNLOADS", h + "/Pictures/../Downloads", h + "/./Downloads",
            h + "/Pictures", h + "/downloads/../Pictures",
        ]
        if h.hasPrefix("/var/") {
            candidates += ["/private" + downloads, "/private" + h + "/dl"]
        }
        var sameCount = 0
        for candidate in candidates {
            let (offer, chooser) = await verdicts(watched: downloads, candidate: candidate)
            XCTAssertNotNil(chooser, "precondition: the gate allows \(candidate)")
            XCTAssertEqual(offer, chooser, "\(candidate): offer says \(offer), chooser \(String(describing: chooser))")
            if offer { sameCount += 1 }
        }
        // The subject happened: most of these *are* Downloads, and two are not.
        XCTAssertEqual(sameCount, candidates.count - 2, "the inputs stopped exercising «same»")
    }

    /// The watched spelling is the unusual one and the candidate the plain one —
    /// the order the offer actually meets them in: the store holds whatever was
    /// chosen, the port hands `~/Downloads`.
    func testBothAnswerAlikeWhenTheStoredSpellingIsTheOddOne() async throws {
        try stand()
        let h = home.path, downloads = h + "/Downloads"
        var stored = [h + "/DL", h + "/downloads", downloads + "/", h + "/DLrel"]
        if h.hasPrefix("/var/") { stored.append("/private" + downloads) }
        for watched in stored {
            let (offer, chooser) = await verdicts(watched: watched, candidate: downloads)
            XCTAssertEqual(offer, true, "\(watched): the offer calls Downloads new")
            XCTAssertEqual(chooser, true, "\(watched): the chooser calls Downloads new")
        }
    }

    /// A watched folder that is not there — renamed away, or on a disk not yet
    /// mounted — reached under another case, the `/private` spelling, a
    /// trailing slash, a `..` detour, and a folder that is there holding a leaf
    /// that is not. Neither side can ask the disk about the missing part, so
    /// both must fall back on the same reading of the spelling.
    func testBothAnswerAlikeForEverySpellingOfAFolderThatIsNotThere() async throws {
        try stand()
        let h = home.path
        let pairs: [(watched: String, candidate: String)] = {
            var list = [
                (h + "/Gone", h + "/gone"),
                (h + "/Gone", h + "/GONE"),
                (h + "/Gone", h + "/Gone/"),
                (h + "/Gone", h + "/Pictures/../Gone"),
                (h + "/Downloads/New", h + "/downloads/New"),
                (h + "/Downloads/New", h + "/DL/New"),
                (h + "/Gone", h + "/Elsewhere"),
            ]
            if h.hasPrefix("/var/") {
                list += [("/private" + h + "/Gone", h + "/Gone"),
                         (h + "/Gone", "/private" + h + "/gone"),
                         ("/private" + h + "/Downloads/New", h + "/downloads/New")]
            }
            return list
        }()
        var disagreements: [String] = []
        var same = 0
        for (watched, candidate) in pairs {
            let (offer, chooser) = await verdicts(watched: watched, candidate: candidate)
            XCTAssertNotNil(chooser, "precondition: the gate allows \(candidate)")
            if offer != chooser {
                disagreements.append("\(watched) vs \(candidate): offer \(offer), chooser \(String(describing: chooser))")
            }
            if offer { same += 1 }
        }
        XCTAssertEqual(disagreements, [], "one folder, two answers")
        // The subject happened: the offer called at least the trivially equal
        // spellings the same, so the loop above compared something.
        XCTAssertGreaterThanOrEqual(same, 3, "the inputs stopped exercising «same»")
    }

    /// A watched folder that is not there, and a link to it that points at
    /// nothing. The chooser follows the dangling link (`followingEveryLink`),
    /// the offer does not (`WatchScope.canonical` treats a missing target as a
    /// missing tail and keeps the link's own name).
    func testBothAnswerAlikeForADanglingLinkToAWatchedFolderThatIsGone() async throws {
        try stand()
        let gone = home.path + "/Gone"
        let (offer, chooser) = await verdicts(watched: gone, candidate: home.path + "/GoneLink")
        XCTAssertNotNil(chooser, "precondition: the gate allows the dangling link")
        XCTAssertEqual(offer, chooser,
                       "offer: \(offer), chooser: \(String(describing: chooser)) — one folder, two answers")
    }
}

import XCTest
@testable import HelmRuntime

/// `UpdateVersion.isNewer` is the only thing standing between a user and a
/// silent downgrade: `UpdateCheck.evaluateList` feeds it to `max(by:)`, and
/// `max(by:)` trusts the predicate to be a strict weak ordering. If it is not,
/// the "newest" release depends on the order GitHub happened to return, which
/// is creation date — not version.
final class UpdateOrderingTests: XCTestCase {

    /// Helm's real published tags, oldest first, including the dev prerelease
    /// that preceded 0.7.0 and the one running now.
    private let history = ["v0.2.0", "v0.3.0", "v0.4.0", "v0.5.0", "v0.5.1",
                           "v0.6.0", "v0.6.1", "v0.7.0-dev.20", "v0.7.0",
                           "v0.7.1-dev.9"]

    /// Nothing is newer than itself. A release that outranks itself makes an
    /// up-to-date app offer to reinstall the build it is already running.
    func testNoTagIsNewerThanItself() {
        for tag in history { XCTAssertFalse(UpdateVersion.isNewer(tag, than: tag), tag) }
    }

    /// Antisymmetry. Both directions true would make `max(by:)`'s answer depend
    /// on where the element sat in the array.
    func testTheOrderingIsAntisymmetric() {
        for a in history {
            for b in history where a != b {
                XCTAssertFalse(UpdateVersion.isNewer(a, than: b) && UpdateVersion.isNewer(b, than: a),
                               "\(a) and \(b) are each newer than the other")
            }
        }
    }

    /// Transitivity, over every ordered triple of the real history.
    func testTheOrderingIsTransitive() {
        for a in history {
            for b in history where UpdateVersion.isNewer(b, than: a) {
                for c in history where UpdateVersion.isNewer(c, than: b) {
                    XCTAssertTrue(UpdateVersion.isNewer(c, than: a), "\(a) < \(b) < \(c) broke")
                }
            }
        }
    }

    /// The release history sorts back into release order. This is the assertion
    /// the other three exist to protect: `v0.7.0-dev.20` below `v0.7.0`,
    /// `v0.7.0` below `v0.7.1-dev.9`, and `v0.5.1` above `v0.5.0`.
    func testSortingTheRealHistoryReproducesReleaseOrder() {
        let shuffledButFixed = [history[7], history[2], history[9], history[0],
                                history[5], history[8], history[1], history[6],
                                history[4], history[3]]
        let sorted = shuffledButFixed.sorted { UpdateVersion.isNewer($1, than: $0) }
        XCTAssertEqual(sorted, history)
    }

    /// Dev ordinals are numbers, not text: dev.9 must sit below dev.10 and
    /// dev.20, which string comparison would get backwards. Helm has already
    /// shipped a dev.20.
    func testDevOrdinalsCompareAsNumbers() {
        let devs = (1...25).map { "v0.7.1-dev.\($0)" }
        // A fixed seed, not `shuffled()`: a different permutation on every run
        // is a different test on every run, which is how a green suite hides a
        // bug that only one arrangement reaches.
        var rng = SeededGenerator(seed: 0x48_65_6C_6D)
        let sorted = devs.shuffled(using: &rng).sorted { UpdateVersion.isNewer($1, than: $0) }
        XCTAssertEqual(sorted, devs)
    }
}

/// Splitmix64, so the shuffle above is the same shuffle on every machine.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The list endpoint returns releases newest-*created* first, which is not the
/// same as newest-versioned: a hotfix cut on an old branch, or a re-published
/// release, lands at the top with an older tag.
final class UpdateListOrderTests: XCTestCase {
    private func release(_ tag: String, prerelease: Bool = true) -> String {
        """
        {"tag_name":"\(tag)","html_url":"https://x/\(tag)","body":"n",
         "prerelease":\(prerelease),"draft":false,
         "assets":[{"name":"Helm.zip","browser_download_url":"https://x/\(tag).zip"}]}
        """
    }

    /// The same three releases in all six orders must give the same answer.
    func testTheAnswerDoesNotDependOnTheOrderGitHubReturns() {
        let tags = ["v0.7.1-dev.9", "v0.7.0", "v0.6.1"]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            let json = "[" + order.map { release(tags[$0]) }.joined(separator: ",") + "]"
            let outcome = UpdateCheck.evaluateList(statusCode: 200, data: Data(json.utf8),
                                                   currentVersion: "0.6.1", channel: .dev)
            guard case .available(let r) = outcome else { return XCTFail("order \(order): \(outcome)") }
            XCTAssertEqual(r.version, "v0.7.1-dev.9", "order \(order)")
        }
    }

    /// A dev user must never be walked backwards onto a stable release older
    /// than the prerelease they are running.
    func testAStableReleaseOlderThanTheRunningPrereleaseIsNotOffered() {
        let json = "[" + release("v0.7.0", prerelease: false) + "," + release("v0.7.0-dev.20") + "]"
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200, data: Data(json.utf8),
                                                currentVersion: "0.7.1-dev.9", channel: .dev),
                       .upToDate)
    }

    /// …and the stable channel, reading the same list, must not be offered the
    /// prerelease even when it is the highest version present.
    func testStableIsNotOfferedThePrereleaseEvenWhenItIsHighest() {
        let json = "[" + release("v0.8.0-dev.1") + "," + release("v0.7.0", prerelease: false) + "]"
        let outcome = UpdateCheck.evaluateList(statusCode: 200, data: Data(json.utf8),
                                               currentVersion: "0.6.1", channel: .beta)
        guard case .available(let r) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(r.version, "v0.7.0")
    }
}

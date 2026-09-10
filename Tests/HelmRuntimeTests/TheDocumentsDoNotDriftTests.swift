import HelmTestSupport
import XCTest

/// Two documents may not quietly become two copies of one paragraph.
///
/// **Why this is a test.** The standing documents were audited by hand on
/// 2026-08-25 and the audit found four contradictions — a heading against its
/// own body, a digest rule naming one of the two scripts that print it, a
/// public module table nine rows long over a registry of ten, a rule told three
/// times in three sets of facts. Every one of them began as a paragraph written
/// twice. Nothing in the tree could see that: `DocumentsNameTheTreeTests` reads
/// *names*, and a copy that drifts keeps every name it started with.
///
/// **The threshold is measured, not chosen.** Over the four core documents —
/// `CLAUDE.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `README.md` — 70 block pairs
/// share any six-word run at all, none of them byte-identical, and the loudest
/// is `ARCHITECTURE.md` ↔ `README.md` at Jaccard 0.048, three times under
/// `floor`. The bimodal distribution this comment once described — a cluster
/// at 1.00 and then nothing until 0.28 — belonged to a corpus that also read
/// eight crew briefs sharing one read-only paragraph byte for byte; the briefs
/// moved to a sibling repository on 2026-09-06 and took that cluster with
/// them, so `floor` now sits above every pair this corpus actually produces
/// rather than in a gap between two of them.
///
/// **The threshold is not what makes this fail; the inventory is.** A number
/// alone would be the hazard the documents name — «a threshold set above every
/// real case». `known` records today's pairs with the reason each is allowed,
/// and it is checked in both directions: a pair that is not recorded fails, and
/// a recorded pair that has gone fails too, so the list cannot fill with
/// ghosts — even though, over these four documents, `known` is empty.
final class TheDocumentsDoNotDriftTests: XCTestCase {

    /// Every prose block of this length or longer is compared. Below it a block
    /// is a sentence, and two sentences sharing six words is ordinary English.
    private static let shortestBlock = 160

    /// Six-word shingles: long enough that shared vocabulary does not register,
    /// short enough that a lightly edited copy still does.
    private static let shingle = 6

    /// Below this, the pair is two people writing about one subject. Above it,
    /// in this corpus, the pair has always been one paragraph written twice.
    private static let floor = 0.15

    /// The four core documents of the standard, and nothing else. The crew's
    /// briefs are **not** here and cannot be: they live in a sibling repository
    /// behind the `.claude/agents` link, which is not a repo-relative path, and
    /// which today points at a directory holding one `.gitkeep`. Reading them
    /// from here was the defect this list carried, not a feature it lost.
    private static let documents: [String] = [
        "CLAUDE.md", "ARCHITECTURE.md", "CHANGELOG.md", "README.md",
    ]

    /// The least of its own characters the reader must keep of each document.
    ///
    /// **A fraction, not a block count, because a fraction does not go stale.**
    /// A count is a fact about how much prose somebody wrote this month; a
    /// fraction is a fact about the reader, which is the thing that breaks. The
    /// file's own comment says as much about the number it replaced: one that
    /// has to be re-derived every time the crew changes is not asserting
    /// anything. README constrains this floor, being short and half headings.
    private static let leastKept = 0.20

    /// Pairs that are allowed to look alike, and why — **empty, and measured
    /// so.** It held two entries and neither was true: one named two briefs of
    /// a crew that moved to a sibling repository, and the other recorded a
    /// resemblance between `ARCHITECTURE.md` and `CLAUDE.md` that the standard
    /// then removed on purpose, by writing one as description and the other as
    /// command. Over the four core documents, 70 pairs share any six-word run
    /// at all and the loudest is 0.048 — three times under `floor`.
    ///
    /// It is checked in both directions and stays that way: an unrecorded pair
    /// fails, and a recorded pair that has gone fails too, so the list cannot
    /// fill with ghosts. **While it is empty,
    /// `testNothingRecordedHasSinceBeenFixed` has no subject** — that is the
    /// honest state of an empty allowance list, not a check gone quiet, and it
    /// goes live again with the first entry anybody adds.
    private static let known: [Pair: (count: Int, reason: String)] = [:]

    struct Pair: Hashable {
        let a: String, b: String
        init(_ x: String, _ y: String) {
            let (p, q) = (Self.leaf(x), Self.leaf(y))
            (a, b) = p <= q ? (p, q) : (q, p)
        }
        private static func leaf(_ s: String) -> String {
            s.split(separator: "/").last.map(String.init) ?? s
        }
        var described: String { "\(a) ↔ \(b)" }
    }

    // MARK: - Reading

    private struct Block {
        let document: String
        let text: String
        let shingles: Set<Int>
    }

    private func corpus() throws -> [Block] {
        let root = RepoSource.root
        let present = Self.documents.filter {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        // **None of them is a question about the checkout; some of them is a
        // defect.** The skip this family is allowed asks the first question.
        // It does not get to skip a *part* of the list: that is how
        // `VERSIONING.md` sat here named and absent while `CHANGELOG.md` went
        // unread.
        try XCTSkipIf(present.isEmpty, "the standing documents are not in this checkout")
        for name in Self.documents where !present.contains(name) {
            XCTFail("""
                `\(name)` is on this guard's list and not beside `Package.swift`. Either it \
                moved and the list is stale, or it was deleted and the list is a claim about a \
                document that no longer exists — both were true here.
                """)
        }

        var out: [Block] = []
        for path in present {
            guard let text = try? String(contentsOf: root.appendingPathComponent(path),
                                         encoding: .utf8) else {
                XCTFail("`\(path)` is on disk and could not be read as UTF-8")
                continue
            }
            for block in Self.blocks(of: text) {
                let shingles = Self.shingles(of: block)
                if !shingles.isEmpty {
                    out.append(Block(document: path, text: block, shingles: shingles))
                }
            }
        }
        return out
    }

    /// Prose blocks only. Code fences carry commands that are *supposed* to be
    /// identical wherever they appear; tables, headings and block quotes are
    /// not prose and match each other on punctuation.
    private static func blocks(of text: String) -> [String] {
        var stripped = ""
        var inFence = false
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            stripped += (inFence ? "" : line) + "\n"
        }
        return stripped.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= shortestBlock
                      && !$0.hasPrefix("|") && !$0.hasPrefix("#") && !$0.hasPrefix(">") }
    }

    private static func shingles(of block: String) -> Set<Int> {
        let words = block.lowercased()
            .split(whereSeparator: { !($0.isLetter && $0.isASCII) && !$0.isNumber && $0 != "'" })
            .map(String.init)
        guard words.count >= shingle else { return [] }
        var out = Set<Int>()
        for i in 0...(words.count - shingle) {
            out.insert(words[i..<(i + shingle)].joined(separator: " ").hashValue)
        }
        return out
    }

    // MARK: - The guards

    func testTheCorpusIsRealBeforeAnythingIsConcludedFromIt() throws {
        let blocks = try corpus()

        // The floor is what a whole document leaving looks like. It was `> 300`,
        // derived over a corpus that included eight briefs, and could not be met
        // again. `shortestBlock` raised to 500 gives 124 blocks and to 1000
        // gives 32 — both below this.
        XCTAssertGreaterThan(blocks.count, 150,
                             "only \(blocks.count) prose blocks — the reader stopped seeing most of the documents")

        // The total cannot ask whether each file was read: ARCHITECTURE.md is
        // most of it, so the other three could vanish and the floor would hold.
        for name in Self.documents {
            guard let text = try? String(
                contentsOf: RepoSource.root.appendingPathComponent(name), encoding: .utf8)
            else { continue }   // absence and unreadability already failed in `corpus()`
            let kept = blocks.filter { $0.document == name }
            XCTAssertFalse(kept.isEmpty, """
                \(name) produced no prose block at all. It was named, it is on disk, and the \
                reader saw none of it — every verdict below is over the wrong text.
                """)
            let ratio = Double(kept.reduce(0) { $0 + $1.text.count }) / Double(max(text.count, 1))
            XCTAssertGreaterThan(ratio, Self.leastKept, """
                \(name): the reader kept \(Int(ratio * 100))% of its \(text.count) characters \
                and the floor is \(Int(Self.leastKept * 100))%. It is being judged on a \
                fraction of itself.
                """)
        }
    }

    func testNoDocumentHasQuietlyBecomeACopyOfAnother() throws {
        let found = pairs(in: try corpus())
            .filter { $0.similarity >= Self.floor }

        var counted: [Pair: Int] = [:]
        for pair in found { counted[pair.key, default: 0] += 1 }

        for (key, n) in counted.sorted(by: { $0.key.described < $1.key.described }) {
            guard let record = Self.known[key] else {
                let worst = found.filter { $0.key == key }.max { $0.similarity < $1.similarity }!
                XCTFail("""
                    \(key.described) at \(String(format: "%.2f", worst.similarity)) — a paragraph \
                    that now reads like one next door. Either point at the one copy instead of \
                    restating it, or add the pair to `known` with the reason it must be said twice.
                    The block begins: «\(worst.excerpt)»
                    """)
                continue
            }
            XCTAssertEqual(n, record.count, """
                \(key.described): \(n) similar block pairs, \(record.count) recorded. \
                These two files were already allowed to resemble each other for one reason \
                («\(record.reason)»); a second resemblance is not covered by it.
                """)
        }
    }

    /// A recorded pair that has gone is a note about a duplication somebody
    /// already removed, and leaving it lets the list fill with ghosts until it
    /// permits more than the tree contains.
    func testNothingRecordedHasSinceBeenFixed() throws {
        let found = Set(pairs(in: try corpus())
            .filter { $0.similarity >= Self.floor }
            .map(\.key))
        for key in Self.known.keys where !found.contains(key) {
            XCTFail("\(key.described) no longer resemble each other — delete the entry from `known`")
        }
    }

    // MARK: - Comparing

    private struct Found {
        let key: Pair; let similarity: Double; let excerpt: String
    }

    private func pairs(in blocks: [Block]) -> [Found] {
        var out: [Found] = []
        for i in blocks.indices {
            for j in blocks.index(after: i)..<blocks.endIndex {
                let (x, y) = (blocks[i], blocks[j])
                guard x.document != y.document else { continue }
                let shared = x.shingles.intersection(y.shingles).count
                guard shared > 0 else { continue }
                let union = x.shingles.count + y.shingles.count - shared
                let similarity = Double(shared) / Double(union)
                out.append(Found(key: Pair(x.document, y.document),
                                 similarity: similarity,
                                 excerpt: String(x.text.prefix(72))
                                     .replacingOccurrences(of: "\n", with: " ")))
            }
        }
        return out
    }
}

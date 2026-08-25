import HelmTestSupport
import XCTest

/// Said once because eight entries below share it.
private let templateReason =
    "the template describes the machine-boundary paragraph each read-only brief must carry; the resemblance is the template doing its job"

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
/// **The threshold is measured, not chosen.** Over the standing documents and
/// the crew's briefs the similarity distribution is bimodal: 84 pairs at
/// Jaccard 1.00 — the read-only scope paragraph, byte for byte across eight
/// briefs, which `check-in-step.sh` already counts — and then nothing at all
/// until 0.28. `floor` sits at 0.15, below every real pair and above the noise.
///
/// **The threshold is not what makes this fail; the inventory is.** A number
/// alone would be the hazard the documents name — «a threshold set above every
/// real case». `known` records today's pairs with the reason each is allowed,
/// and it is checked in both directions: a pair that is not recorded fails, and
/// a recorded pair that has gone fails too, so the list cannot fill with ghosts.
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

    /// The documents this guard reads. The crew's own README is **not** here:
    /// it lives in a sibling repository, is not reachable by a repo-relative
    /// path from a worktree, and `check-in-step.sh` already owns it — the same
    /// boundary the documents' own contracts now state.
    private static let documents: [String] = [
        "CLAUDE.md", "ARCHITECTURE.md", "VERSIONING.md", "README.md",
        "docs/crew/BRIEF-TEMPLATE.md",
    ]

    /// Pairs that are allowed to look alike, and why. Keyed by the two file
    /// names in sorted order; the value is how many block pairs that file pair
    /// is expected to produce, so one more is a failure even between two files
    /// already on the list.
    private static let known: [Pair: (count: Int, reason: String)] = [
        Pair("ARCHITECTURE.md", "CLAUDE.md"):
            (1, "the Completeness rule and the evidence under it: the contracts put the rule in CLAUDE.md and the account in ARCHITECTURE.md, and the rule restates enough of it to stand alone"),
        Pair("ARCHITECTURE.md", "helm-animator.md"):
            (1, "the third law of motion, kept as a checklist line in the brief after the two long copies were cut on 2026-08-25"),
        Pair("helm-architect.md", "helm-product.md"):
            (1, "the opening paragraph describing the app, carried by both judging roles"),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-a11y.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-architect.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-localizer.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-locator.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-product.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-security.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-ui-designer.md"): (1, templateReason),
        Pair("docs/crew/BRIEF-TEMPLATE.md", "helm-ux-designer.md"): (1, templateReason),
    ]

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
        /// A brief lives under `.claude/agents`. It matters here because
        /// `check-in-step.sh` owns byte-identical text *between briefs* and
        /// nothing else — see `isCheckInSteps`.
        let isBrief: Bool
    }

    private func corpus() throws -> [Block] {
        let root = RepoSource.root
        var paths = Self.documents
        let briefs = (try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent(".claude/agents").path)) ?? []
        paths += briefs.filter { $0.hasPrefix("helm-") && $0.hasSuffix(".md") }
                       .sorted().map { ".claude/agents/\($0)" }

        // **The skip asks about the disk, and the assertion asks about the
        // reader.** These are two questions and the first version folded them
        // into one: it skipped when the *corpus* came out thin, so raising
        // `shortestBlock` until the reader saw nothing produced
        // «3 tests skipped and 0 failures» — a suite passing, in a check
        // written to stop exactly that. An absent submodule is a fact about the
        // checkout; a thin corpus over documents that are present is a broken
        // reader, and it is not allowed to look like one.
        let present = paths.filter {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        try XCTSkipIf(present.count < 3, "the standing documents are not in this checkout")

        var out: [Block] = []
        for path in present {
            guard let text = try? String(contentsOf: root.appendingPathComponent(path),
                                         encoding: .utf8) else { continue }
            let name = path.split(separator: "/").last.map(String.init) ?? path
            for block in Self.blocks(of: text) {
                let s = Self.shingles(of: block)
                if !s.isEmpty {
                    out.append(Block(document: name, text: block, shingles: s,
                                     isBrief: path.hasPrefix(".claude/agents/")))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(Set(out.map(\.document)).count, present.count - 1, """
            \(present.count) documents on disk but only \(Set(out.map(\.document)).count) \
            produced any prose. The reader stopped seeing them; every verdict below \
            would be over a corpus that is not the documents.
            """)
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
        XCTAssertGreaterThan(blocks.count, 300,
                             "only \(blocks.count) prose blocks — the reader stopped seeing most of the documents")
        let exact = pairs(in: blocks).filter { $0.similarity >= 0.999 }
        XCTAssertGreaterThan(exact.count, 50, """
            \(exact.count) byte-identical cross-document pairs. The read-only scope paragraph \
            is one text across eight briefs, so this corpus should be full of them; that it is \
            not means the briefs were not read, and every verdict below is over the wrong text.
            """)
    }

    func testNoDocumentHasQuietlyBecomeACopyOfAnother() throws {
        let found = pairs(in: try corpus())
            .filter { $0.similarity >= Self.floor && !$0.isCheckInSteps }

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
            .filter { $0.similarity >= Self.floor && !$0.isCheckInSteps }
            .map(\.key))
        for key in Self.known.keys where !found.contains(key) {
            XCTFail("\(key.described) no longer resemble each other — delete the entry from `known`")
        }
    }

    // MARK: - Comparing

    private struct Found {
        let key: Pair; let similarity: Double; let excerpt: String
        /// Byte-identical, and between two briefs: the read-only scope
        /// paragraph, which `check-in-step.sh` counts. **Only that.** An exact
        /// copy anywhere else is the worst case of what this guard is for, and
        /// excluding every exact copy is how the first version of this test
        /// passed with a whole paragraph of `ARCHITECTURE.md` pasted into
        /// `VERSIONING.md` — found by mutation on 2026-08-25, which is why the
        /// exemption is a boundary now and not a number.
        let isCheckInSteps: Bool
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
                                     .replacingOccurrences(of: "\n", with: " "),
                                 isCheckInSteps: similarity >= 0.999 && x.isBrief && y.isBrief))
            }
        }
        return out
    }
}

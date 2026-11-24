import Foundation

/// A rule the stored record holds and this build cannot decode — one a newer
/// Helm wrote, or one nobody can read any more. Kept as the bytes it was, so a
/// save puts it back where it was.
public struct UnappliedRule: Equatable, Sendable {
    public let folderID: String
    /// Its place in the folder's rule list as stored.
    public let index: Int
    /// A lenient read of `name` alone, for the page; nil when even that fails.
    public let name: String?
    let raw: Data
    /// The `path` of the removed folder that holds it, for the page; nil when it
    /// sits in a live folder, and for a removed one whose stub names no path.
    public var removedFolderPath: String? = nil
}

/// A folder the person removed that still held an unapplied rule, kept in the
/// record as an object marked `"helmRemovedFolder": true` with its `id`, `path`
/// and the raw rules, so a newer Helm finds them. Never watched; its rules are
/// drawn apart on the page, never applied.
struct RemovedFolder: Equatable, Sendable {
    let id: String
    /// The folder before it in the record, nil when it was first, so a save
    /// writes it back in the place it was read from.
    let after: String?
    let raw: Data
}

/// What a decoded folder or rule looked like in the record, so that one nobody
/// changed goes back as the bytes it came from and one that was changed keeps
/// the members this build does not know.
struct KeptBytes<Value: Equatable & Sendable>: Equatable, Sendable {
    let raw: Data
    /// The element as this build read it: the comparison that says whether
    /// anyone changed it since. Not its encoding, because `JSONEncoder` writes
    /// the members of an object in a different order on every call.
    let value: Value
    /// Every `"key":value` member whose key is not one of the type's own.
    let unknown: [Data]
    /// A folder's `path`, for the stub it may become.
    var path: String? = nil
}

struct RuleAt: Hashable, Sendable {
    let folder: String
    let rule: String
}

struct KeptMembers: Equatable, Sendable {
    var folders: [String: KeptBytes<WatchedFolder>] = [:]
    var rules: [RuleAt: KeptBytes<Rule>] = [:]

    var holdsUnknown: Bool {
        folders.values.contains { !$0.unknown.isEmpty } || rules.values.contains { !$0.unknown.isEmpty }
    }
}

/// The sealed rule list read rule by rule and written back without losing what
/// this build could not read. Pure: bytes in, bytes out. See `SealedRules`.
///
/// **Why not one `JSONDecoder().decode([WatchedFolder].self)`.** One rule a newer
/// Helm wrote (an unknown condition case) would fail the whole decode, and the
/// next save would write the list back without it. Here each rule is decoded alone.
enum StoredRuleSet {
    enum Reading: Equatable {
        /// The record cannot be parsed by this build: the scanner fails, the top
        /// level is not an array, an element is not an object, or a folder's own
        /// fields do not decode.
        case unreadable
        case read(folders: [WatchedFolder], unapplied: [UnappliedRule],
                  stubs: [RemovedFolder], extras: KeptMembers)
    }

    private static let stubMarker = "helmRemovedFolder"
    private static let folderKeys: Set<String> = ["id", "path", "enabled", "rules", "depth"]
    private static let ruleKeys: Set<String> = ["id", "name", "enabled", "match", "conditions", "action"]

    private struct Head: Decodable {
        let id: String
        let path: String
        let enabled: Bool
        let depth: Int
    }

    private struct Name: Decodable { let name: String? }

    static func read(_ data: Data) -> Reading {
        // Invalid UTF-8 is not text: refused here, so no string is cut mid-sequence.
        guard String(data: data, encoding: .utf8) != nil else { return .unreadable }
        let b = [UInt8](data)
        guard let elements = JSONScan.elements(in: b, 0..<b.count) else { return .unreadable }
        var folders: [WatchedFolder] = []
        var unapplied: [UnappliedRule] = []
        var stubs: [RemovedFolder] = []
        var extras = KeptMembers()
        for range in elements {
            guard let members = JSONScan.members(in: b, range) else { return .unreadable }
            let raw = Data(b[range])
            let rulesValue = members.first { $0.key == "rules" }?.value
            let ruleRanges = rulesValue.map { JSONScan.elements(in: b, $0) } ?? nil
            if let marker = members.first(where: { $0.key == stubMarker }), Data(b[marker.value]) == Data("true".utf8) {
                let id = members.first { $0.key == "id" }
                    .flatMap { try? JSONDecoder().decode(String.self, from: Data(b[$0.value])) } ?? ""
                stubs.append(RemovedFolder(id: id, after: folders.last?.id, raw: raw))
                let path = members.first { $0.key == "path" }
                    .flatMap { try? JSONDecoder().decode(String.self, from: Data(b[$0.value])) }
                for (index, r) in (ruleRanges ?? []).enumerated() {
                    unapplied.append(UnappliedRule(folderID: id, index: index, name: name(Data(b[r])),
                                                   raw: Data(b[r]), removedFolderPath: path))
                }
                continue
            }
            guard let head = try? JSONDecoder().decode(Head.self, from: raw), let ruleRanges else { return .unreadable }
            var rules: [Rule] = []
            var ruleBytes: [(raw: Data, unknown: [Data])] = []
            for (index, r) in ruleRanges.enumerated() {
                let bytes = Data(b[r])
                if let rule = try? JSONDecoder().decode(Rule.self, from: bytes) {
                    rules.append(rule)
                    ruleBytes.append((bytes, unknown(b, r, ruleKeys)))
                } else {
                    unapplied.append(UnappliedRule(folderID: head.id, index: index, name: name(bytes), raw: bytes))
                }
            }
            let folder = WatchedFolder(id: head.id, path: head.path, enabled: head.enabled,
                                       rules: rules, depth: head.depth).storable
            for (rule, kept) in zip(folder.rules, ruleBytes) {
                extras.rules[RuleAt(folder: folder.id, rule: rule.id)] =
                    KeptBytes(raw: kept.raw, value: rule, unknown: kept.unknown)
            }
            extras.folders[folder.id] = KeptBytes(raw: raw, value: folder,
                                                  unknown: unknown(b, range, folderKeys), path: folder.path)
            folders.append(folder)
        }
        return .read(folders: folders, unapplied: unapplied, stubs: stubs, extras: extras)
    }

    /// The record for `folders`, with what was kept put back. Nil only when
    /// encoding fails. With nothing kept it is what `JSONEncoder` makes of the
    /// folders, which is the format every deployed Mac holds.
    static func compose(_ folders: [WatchedFolder], unapplied: [UnappliedRule] = [],
                        stubs: [RemovedFolder] = [], extras: KeptMembers = KeptMembers()) -> Data? {
        let stored = folders.map(\.storable)
        guard !unapplied.isEmpty || !stubs.isEmpty || extras.holdsUnknown else {
            return try? JSONEncoder().encode(stored)
        }
        let encoder = JSONEncoder()
        let present = Set(stored.map(\.id))
        let stubIDs = Set(stubs.map(\.id))
        func stubsAfter(_ id: String?) -> [Data] { stubs.filter { $0.after == id }.map(\.raw) }
        do {
            var items = stubsAfter(nil)
            for folder in stored {
                items.append(try element(folder, unapplied: unapplied.filter { $0.folderID == folder.id }, extras))
                items += stubsAfter(folder.id)
            }
            items += stubs.filter { $0.after.map { !present.contains($0) } ?? false }.map(\.raw)
            // A removed folder whose rules this build could not read: kept as a stub.
            var orphans: [String: [Data]] = [:]
            var order: [String] = []
            for rule in unapplied where !present.contains(rule.folderID) && !stubIDs.contains(rule.folderID) {
                if orphans[rule.folderID] == nil { order.append(rule.folderID) }
                orphans[rule.folderID, default: []].append(rule.raw)
            }
            for id in order {
                let path = String(data: try encoder.encode(extras.folders[id]?.path ?? ""), encoding: .utf8) ?? "\"\""
                let rules = Data("[".utf8) + Data(orphans[id]!.joined(separator: Data(",".utf8))) + Data("]".utf8)
                items.append(Data("{\"id\":".utf8) + (try encoder.encode(id)) + Data(",\"path\":\(path),\"rules\":".utf8)
                             + rules + Data(",\"\(stubMarker)\":true}".utf8))
            }
            return Data("[".utf8) + Data(items.joined(separator: Data(",".utf8))) + Data("]".utf8)
        } catch {
            return nil
        }
    }

    private static func element(_ folder: WatchedFolder, unapplied: [UnappliedRule],
                                _ extras: KeptMembers) throws -> Data {
        let encoder = JSONEncoder()
        let kept = extras.folders[folder.id]
        if let kept, kept.value == folder { return kept.raw }
        var rules = try folder.rules.map { try element($0, in: folder.id, extras) }
        for rule in unapplied.sorted(by: { $0.index < $1.index }) {
            rules.insert(rule.raw, at: min(rule.index, rules.count))
        }
        let members: [Data] = [
            Data("\"id\":".utf8) + (try encoder.encode(folder.id)),
            Data("\"path\":".utf8) + (try encoder.encode(folder.path)),
            Data("\"enabled\":".utf8) + (try encoder.encode(folder.enabled)),
            Data("\"rules\":[".utf8) + Data(rules.joined(separator: Data(",".utf8))) + Data("]".utf8),
            Data("\"depth\":".utf8) + (try encoder.encode(folder.depth)),
        ] + (kept?.unknown ?? [])
        return Data("{".utf8) + Data(members.joined(separator: Data(",".utf8))) + Data("}".utf8)
    }

    private static func element(_ rule: Rule, in folder: String, _ extras: KeptMembers) throws -> Data {
        let encoded = try JSONEncoder().encode(rule)
        guard let kept = extras.rules[RuleAt(folder: folder, rule: rule.id)] else { return encoded }
        if kept.value == rule { return kept.raw }
        guard !kept.unknown.isEmpty else { return encoded }
        return encoded.dropLast() + Data(",".utf8) + Data(kept.unknown.joined(separator: Data(",".utf8))) + Data("}".utf8)
    }

    private static func name(_ bytes: Data) -> String? {
        (try? JSONDecoder().decode(Name.self, from: bytes))?.name
    }

    private static func unknown(_ b: [UInt8], _ range: Range<Int>, _ known: Set<String>) -> [Data] {
        (JSONScan.members(in: b, range) ?? []).filter { !known.contains($0.key) }.map { Data(b[$0.pair]) }
    }
}

/// Byte ranges of the elements of a JSON array and the members of a JSON
/// object, found without decoding. Iterative, aware of strings and escapes,
/// bounded by nothing but the size of the bytes and a nesting depth of 64 (the
/// deployed format nests about 8). Nil on anything malformed; never traps.
enum JSONScan {
    static let depthBound = 64

    typealias Member = (key: String, pair: Range<Int>, value: Range<Int>)

    static func elements(in b: [UInt8], _ r: Range<Int>) -> [Range<Int>]? {
        var i = r.lowerBound
        let end = r.upperBound
        skip(b, &i, end)
        guard i < end, b[i] == 0x5B else { return nil }
        i += 1
        var out: [Range<Int>] = []
        skip(b, &i, end)
        if i < end, b[i] == 0x5D {
            i += 1
        } else {
            while true {
                skip(b, &i, end)
                guard let e = value(b, i, end) else { return nil }
                out.append(i..<e)
                i = e
                skip(b, &i, end)
                guard i < end else { return nil }
                if b[i] == 0x2C { i += 1; continue }
                guard b[i] == 0x5D else { return nil }
                i += 1
                break
            }
        }
        skip(b, &i, end)
        return i == end ? out : nil
    }

    static func members(in b: [UInt8], _ r: Range<Int>) -> [Member]? {
        var i = r.lowerBound
        let end = r.upperBound
        skip(b, &i, end)
        guard i < end, b[i] == 0x7B else { return nil }
        i += 1
        var out: [Member] = []
        skip(b, &i, end)
        if i < end, b[i] == 0x7D {
            i += 1
        } else {
            while true {
                skip(b, &i, end)
                let start = i
                guard let k = string(b, i, end),
                      let key = try? JSONDecoder().decode(String.self, from: Data(b[i..<k])) else { return nil }
                i = k
                guard colon(b, &i, end) else { return nil }
                skip(b, &i, end)
                guard let e = value(b, i, end) else { return nil }
                out.append((key, start..<e, i..<e))
                i = e
                skip(b, &i, end)
                guard i < end else { return nil }
                if b[i] == 0x2C { i += 1; continue }
                guard b[i] == 0x7D else { return nil }
                i += 1
                break
            }
        }
        skip(b, &i, end)
        return i == end ? out : nil
    }

    private static func skip(_ b: [UInt8], _ i: inout Int, _ end: Int) {
        while i < end, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D { i += 1 }
    }

    private static func colon(_ b: [UInt8], _ i: inout Int, _ end: Int) -> Bool {
        skip(b, &i, end)
        guard i < end, b[i] == 0x3A else { return false }
        i += 1
        return true
    }

    /// The end of the string that opens at `i`.
    private static func string(_ b: [UInt8], _ start: Int, _ end: Int) -> Int? {
        guard start < end, b[start] == 0x22 else { return nil }
        var i = start + 1
        while i < end {
            let c = b[i]
            if c < 0x20 { return nil }
            if c == 0x22 { return i + 1 }
            if c == 0x5C {
                i += 1
                guard i < end else { return nil }
                switch b[i] {
                case 0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74: break
                case 0x75:
                    guard i + 4 < end, b[(i + 1)...(i + 4)].allSatisfy({ isHex($0) }) else { return nil }
                    i += 4
                default: return nil
                }
            }
            i += 1
        }
        return nil
    }

    private static func isHex(_ c: UInt8) -> Bool {
        (0x30...0x39).contains(c) || (0x41...0x46).contains(c) || (0x61...0x66).contains(c)
    }

    /// A number, `true`, `false` or `null`, ending at a delimiter.
    private static func token(_ b: [UInt8], _ start: Int, _ end: Int) -> Int? {
        var i = start
        while i < end, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D, 0x3A, 0x22, 0x5B, 0x7B].contains(b[i]) { i += 1 }
        let text = b[start..<i]
        if text.elementsEqual("true".utf8) || text.elementsEqual("false".utf8) || text.elementsEqual("null".utf8) {
            return i
        }
        return isNumber(text) ? i : nil
    }

    private static func isNumber(_ t: ArraySlice<UInt8>) -> Bool {
        var i = t.startIndex
        let end = t.endIndex
        func digits() -> Int {
            let from = i
            while i < end, (0x30...0x39).contains(t[i]) { i += 1 }
            return i - from
        }
        if i < end, t[i] == 0x2D { i += 1 }
        guard i < end else { return false }
        if t[i] == 0x30 { i += 1 } else if digits() == 0 { return false }
        if i < end, t[i] == 0x2E { i += 1; if digits() == 0 { return false } }
        if i < end, t[i] == 0x65 || t[i] == 0x45 {
            i += 1
            if i < end, t[i] == 0x2B || t[i] == 0x2D { i += 1 }
            if digits() == 0 { return false }
        }
        return i == end
    }

    /// The end of the value that begins at `start`, whose container sits at depth 1.
    private static func value(_ b: [UInt8], _ start: Int, _ end: Int) -> Int? {
        var stack: [UInt8] = []
        var i = start
        while true {
            skip(b, &i, end)
            guard i < end else { return nil }
            switch b[i] {
            case 0x22:
                guard let e = string(b, i, end) else { return nil }
                i = e
            case 0x5B, 0x7B:
                stack.append(b[i])
                guard stack.count + 1 <= depthBound else { return nil }
                i += 1
                skip(b, &i, end)
                guard i < end else { return nil }
                if b[i] == (stack.last == 0x5B ? 0x5D : 0x7D) {
                    stack.removeLast()
                    i += 1
                } else {
                    if stack.last == 0x7B {
                        guard let e = string(b, i, end), colon(b, &i, end, after: e) else { return nil }
                    }
                    continue
                }
            default:
                guard let e = token(b, i, end) else { return nil }
                i = e
            }
            while let top = stack.last {
                skip(b, &i, end)
                guard i < end else { return nil }
                if b[i] == 0x2C {
                    i += 1
                    if top == 0x7B {
                        skip(b, &i, end)
                        guard let e = string(b, i, end), colon(b, &i, end, after: e) else { return nil }
                    }
                    break
                }
                guard b[i] == (top == 0x5B ? 0x5D : 0x7D) else { return nil }
                stack.removeLast()
                i += 1
            }
            if stack.isEmpty { return i }
        }
    }

    private static func colon(_ b: [UInt8], _ i: inout Int, _ end: Int, after keyEnd: Int) -> Bool {
        i = keyEnd
        return colon(b, &i, end)
    }
}

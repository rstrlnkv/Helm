import Foundation
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A stored rule record planted and sealed the way Helm seals it, so a test can
/// give the engine bytes of any shape. Shared by the tests of what the engine
/// does with a record it reads (`AnOldRuleSetReadsAsItDid`, `ARuleFromANewerHelm`,
/// `AnUnreadableRuleSet`).
final class ASealedRecordBench {
    let backing = InMemoryKeyValueStore()
    let namespace = "autopilot.test.\(UUID().uuidString)"
    let home: String
    private(set) var keys = TestRuleKey(established: true)
    private(set) var sequence = TestRuleSequence()

    init(home: String) { self.home = home }

    var payloadKey: String { "module.\(namespace).folders" }
    var macKey: String { "module.\(namespace).\(RuleSeal.storeKey)" }
    var seqKey: String { "module.\(namespace).\(RuleSeal.sequenceKey)" }

    var payload: Data? { backing.raw[payloadKey] as? Data }

    /// What the plist holds about the rules, to compare before and after.
    var stored: [String] {
        [payload.map { String(decoding: $0, as: UTF8.self) } ?? "-",
         "\(backing.raw[macKey] ?? "-")", "\(backing.raw[seqKey] ?? "-")", "\(sequence.mark.map(String.init) ?? "-")"]
    }

    func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home, keys: keys, sequence: sequence)
    }

    /// `text` as the payload, sealed at `seq`, on a Mac that has sealed before.
    /// A seq of 0 is a rule set written before there were numbers: no number in
    /// the plist, nothing in the mark.
    func plant(_ text: String, seq: UInt64) {
        let data = Data(text.utf8)
        backing.raw[payloadKey] = data
        backing.raw[macKey] = RuleSeal.mac(for: data, seq: seq, key: TestRuleKey.material)
        if seq > 0 { backing.raw[seqKey] = Int(seq) }
        keys = TestRuleKey(established: true)
        sequence = TestRuleSequence(at: seq > 0 ? seq : nil)
    }

    /// `text` as the payload with no seal: what a Mac holds from before sealing.
    func plantUnsealed(_ text: String) {
        backing.raw[payloadKey] = Data(text.utf8)
        keys = TestRuleKey()
        sequence = TestRuleSequence()
    }

    static func rule(_ id: String, extra: String = "") -> String {
        #"{"id":"\#(id)","name":"n\#(id)","enabled":true,"match":"all","conditions":[{"tag":{"_0":"x"}}],"action":{"trash":{}}\#(extra)}"#
    }

    static func folder(_ id: String, rules: [String], extra: String = "") -> String {
        #"{"id":"\#(id)","path":"/p/\#(id)","enabled":true,"rules":[\#(rules.joined(separator: ","))],"depth":1\#(extra)}"#
    }
}

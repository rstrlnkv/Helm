public enum ActiveCondition: Hashable, Sendable { case manual, timer, externalDisplay, power, app }

public enum Conditions {
    public struct Inputs: Equatable, Sendable {
        public var manual = false
        public var timerRunning = false
        public var externalDisplay = false
        public var onPower = false
        public var appRunning = false
        public var suppressed = false   // manual-off while an auto condition holds
        public init() {}
    }
    public struct Result: Equatable, Sendable {
        public var isActive: Bool
        public var conditions: Set<ActiveCondition>
        public static let inactive = Result(isActive: false, conditions: [])
    }
    public static func resolve(_ i: Inputs) -> Result {
        if i.manual || i.timerRunning {
            var c: Set<ActiveCondition> = []
            if i.manual { c.insert(.manual) }; if i.timerRunning { c.insert(.timer) }
            if i.externalDisplay { c.insert(.externalDisplay) }
            if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
            return Result(isActive: true, conditions: c)
        }
        if i.suppressed { return .inactive }
        var c: Set<ActiveCondition> = []
        if i.externalDisplay { c.insert(.externalDisplay) }
        if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
        return Result(isActive: !c.isEmpty, conditions: c)
    }
}

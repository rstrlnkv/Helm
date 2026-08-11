enum BatteryGuard {
    /// Deactivate when guard on, on battery, and at/below threshold.
    static func shouldDeactivate(enabled: Bool, isOnBattery: Bool,
                                 percent: Int, threshold: Int) -> Bool {
        enabled && isOnBattery && percent <= threshold
    }
}

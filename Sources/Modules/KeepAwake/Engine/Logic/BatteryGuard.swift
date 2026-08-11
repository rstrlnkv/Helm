enum BatteryGuard {
    /// Deactivate when guard on, on battery, and at/below threshold.
    static func shouldDeactivate(enabled: Bool, isOnBattery: Bool,
                                 percent: Int, threshold: Int) -> Bool {
        enabled && isOnBattery && percent <= threshold
    }

    /// The same question with **no reading at all**, which `IOPSCopyPowerSourcesInfo`
    /// gives for two different reasons: a Mac with no battery, and a dictionary
    /// that came back incomplete on a Mac that has one.
    ///
    /// So the mains reading decides it, exactly as it does for `powerCondition`
    /// and the app rules — both of which were dead on every desktop while nil was
    /// read as one thing. Not plugged in and no reading is battery power with an
    /// unknown charge, and letting the Mac sleep is this module's safe failure;
    /// plugged in, there is no battery to run out and the guard has nothing to
    /// say. Answering «no veto» to both left the only thing that ever ends an
    /// unattended session switched off whenever the dictionary was short.
    ///
    /// `enabled` is asked here as it is above: a person who switched the floor off
    /// did not ask for it back on the strength of a failed read.
    static func shouldDeactivateWithNoReading(enabled: Bool, isOnMains: Bool) -> Bool {
        enabled && !isOnMains
    }
}

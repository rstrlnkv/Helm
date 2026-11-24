public enum ModulePermission: String, Codable, Sendable, CaseIterable {
    case accessibility, screenRecording, adminHelper  // adminHelper = sudoers/pmset
    /// Reading protected folders and removing app containers. A module that
    /// needs it declares it, or the audit after an update cannot ask about it.
    case fullDisk
}

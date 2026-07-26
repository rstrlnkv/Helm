public enum ModulePermission: String, Codable, Sendable, CaseIterable {
    case accessibility, screenRecording, adminHelper  // adminHelper = sudoers/pmset
    /// Reading protected folders and removing app containers. Three modules
    /// need it and none of them declared it, which is why the audit after an
    /// update only ever asked about half of what had stopped working.
    case fullDisk
}

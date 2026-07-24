public enum ModulePermission: String, Codable, Sendable, CaseIterable {
    case accessibility, screenRecording, adminHelper  // adminHelper = sudoers/pmset
}

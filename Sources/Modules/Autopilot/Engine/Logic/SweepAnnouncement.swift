/// Which sweep says something in the log, and what.
///
/// Two triggers share `sweep` and must not share its voice. The hourly
/// sentinel over a folder where nothing happened stays silent — 24 lines a day
/// about nothing drown the trail the log exists to be — and a person's Run now
/// is always answered, because a manual run that found nothing to do and a
/// manual run that never started are otherwise the same silence. One condition,
/// held here rather than spelled at each call site, so the two paths cannot
/// drift into agreeing.
enum SweepAnnouncement {

    /// The log line for a finished sweep, or `nil` for the silence the hourly
    /// sentinel owes an idle folder. `manual` is the trigger: a command is
    /// always answered, and the answer says it was a command — an hourly line
    /// and a pressed one land in the same log.
    static func line(for report: SweepReport, manual: Bool) -> String? {
        // Over all three counts, not `acted` alone: a refusal or a failure is
        // work the unattended path owes a line about even when nothing moved.
        let worked = report.acted + report.refused + report.failed > 0
        guard manual || worked else { return nil }
        let counts = "swept \(report.examined), acted \(report.acted), "
            + "refused \(report.refused), failed \(report.failed)"
        return manual ? "run now: " + counts : counts
    }
}

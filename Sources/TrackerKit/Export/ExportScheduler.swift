import Foundation
import UserNotifications

/// Schedules the weekly nudge that starts an export.
///
/// ## Why a notification and not a send
/// iOS does not let an app send email or SMS unattended. There is no background
/// API for it, and anything that claims otherwise is routing through a server.
/// So the honest design is: the library schedules a **repeating local
/// notification**, and tapping it opens the app with a composer already filled in
/// with the report. The user taps send. One tap, no infrastructure, nothing
/// silently failing in the background.
///
/// If you later want true unattended delivery, the seam is ``ProgressReport`` —
/// it is `Sendable` and format-agnostic, so a server-side sender consumes the
/// same struct these renderers do.
public enum ExportScheduler {

    /// Notification category, so a host app can attach custom actions.
    public static let categoryIdentifier = "TRACKERKIT_EXPORT"
    /// Action that opens straight into the composer.
    public static let sendActionIdentifier = "TRACKERKIT_EXPORT_SEND"
    /// Action that pushes the reminder out a day.
    public static let snoozeActionIdentifier = "TRACKERKIT_EXPORT_SNOOZE"

    // MARK: Authorization

    /// Asks for notification permission. Returns whether it was granted.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Registers the export category and its actions. Call once at launch.
    public static func registerCategory() {
        let send = UNNotificationAction(
            identifier: sendActionIdentifier,
            title: "Review & send",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "Tomorrow",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [send, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: Scheduling

    /// Schedules (or reschedules) the weekly reminder for one export schedule.
    ///
    /// Disabled schedules are cancelled rather than scheduled, so calling this
    /// after any edit is always the right move.
    public static func schedule(_ schedule: ExportSchedule, profileName: String) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [schedule.notificationIdentifier])

        guard schedule.isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(profileName)'s weekly progress"
        content.body = recipientLine(for: schedule)
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "trackerkit.scheduleID": schedule.id.uuidString,
            "trackerkit.profileID": schedule.profileID.uuidString,
            "trackerkit.channel": schedule.channel.rawValue,
            "trackerkit.format": schedule.format.rawValue,
            "trackerkit.lookbackDays": schedule.lookbackDays,
            // Carries the saved report through to the tap, so the composer opens
            // with every choice already made rather than a blank form.
            "trackerkit.reportDefinitionID": schedule.reportDefinitionID?.uuidString ?? ""
        ]

        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        // A weekday on a daily trigger would fire once a week, and a weekday on
        // a monthly one is a different date every month. Only set what the
        // frequency actually means.
        switch schedule.frequency {
        case .daily: break
        case .weekly: components.weekday = schedule.weekday
        case .monthly: components.day = 1
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: schedule.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }

    /// Reschedules every schedule for a profile in one pass.
    public static func syncAll(_ schedules: [ExportSchedule], profileName: String) async {
        for schedule in schedules {
            try? await self.schedule(schedule, profileName: profileName)
        }
    }

    public static func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Identifiers of every export reminder currently scheduled — used by the
    /// settings screen to show what is actually pending rather than what we think is.
    public static func pendingExportIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current()
            .pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("trackerkit.export.") }
    }

    /// The next fire date for a schedule, for display in settings.
    public static func nextFireDate(for schedule: ExportSchedule, calendar: Calendar = .current) -> Date? {
        guard schedule.isEnabled else { return nil }
        var components = DateComponents()
        components.weekday = schedule.weekday
        components.hour = schedule.hour
        components.minute = schedule.minute
        return calendar.nextDate(
            after: .now,
            matching: components,
            matchingPolicy: .nextTime
        )
    }

    /// Pushes one reminder out by a day without disturbing the weekly repeat.
    public static func snooze(_ schedule: ExportSchedule, profileName: String, by days: Int = 1) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(profileName)'s weekly progress"
        content.body = "Snoozed — ready when you are."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "trackerkit.scheduleID": schedule.id.uuidString,
            "trackerkit.profileID": schedule.profileID.uuidString
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(days) * 86_400,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "\(schedule.notificationIdentifier).snooze",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    // MARK: Helpers

    private static func recipientLine(for schedule: ExportSchedule) -> String {
        switch schedule.channel {
        case .shareSheet:
            return "Tap to review this week's report and share it."
        case .email where schedule.recipients.isEmpty,
             .message where schedule.recipients.isEmpty:
            return "Tap to review this week's report and send it."
        case .email:
            return "Tap to review and email \(joined(schedule.recipients))."
        case .message:
            return "Tap to review and text \(joined(schedule.recipients))."
        }
    }

    private static func joined(_ recipients: [String]) -> String {
        switch recipients.count {
        case 0: return "your recipients"
        case 1: return recipients[0]
        case 2: return "\(recipients[0]) and \(recipients[1])"
        default: return "\(recipients[0]) and \(recipients.count - 1) others"
        }
    }
}

// MARK: - ExportRequest

/// Everything a composer needs, decoded from a tapped notification.
///
/// The app delegate hands the notification's `userInfo` here, gets back a request,
/// and presents the matching composer.
public struct ExportRequest: Sendable, Hashable, Identifiable {
    public let scheduleID: UUID?
    public let profileID: UUID
    public let channel: ExportChannel
    public let format: ReportFormat
    public let lookbackDays: Int

    public var id: String { "\(profileID.uuidString)-\(scheduleID?.uuidString ?? "adhoc")" }

    public init(
        scheduleID: UUID? = nil,
        profileID: UUID,
        channel: ExportChannel = .email,
        format: ReportFormat = .html,
        lookbackDays: Int = 7
    ) {
        self.scheduleID = scheduleID
        self.profileID = profileID
        self.channel = channel
        self.format = format
        self.lookbackDays = lookbackDays
    }

    /// Rebuilds a request from a notification payload. Returns `nil` for anything
    /// that isn't one of ours.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let profileString = userInfo["trackerkit.profileID"] as? String,
              let profileID = UUID(uuidString: profileString)
        else { return nil }

        self.profileID = profileID
        self.scheduleID = (userInfo["trackerkit.scheduleID"] as? String).flatMap(UUID.init(uuidString:))
        self.channel = (userInfo["trackerkit.channel"] as? String)
            .flatMap(ExportChannel.init(rawValue:)) ?? .email
        self.format = (userInfo["trackerkit.format"] as? String)
            .flatMap(ReportFormat.init(rawValue:)) ?? .html
        self.lookbackDays = userInfo["trackerkit.lookbackDays"] as? Int ?? 7
    }

    /// Builds a request from a stored schedule.
    public init(_ schedule: ExportSchedule) {
        self.scheduleID = schedule.id
        self.profileID = schedule.profileID
        self.channel = schedule.channel
        self.format = schedule.format
        self.lookbackDays = schedule.lookbackDays
    }
}

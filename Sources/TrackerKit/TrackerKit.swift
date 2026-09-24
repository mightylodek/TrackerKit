import Foundation
import SwiftUI
import UserNotifications

/// Library-level entry points and metadata.
public enum TrackerKit {

    public static let version = "1.0.0"

    /// Wires up the pieces that need to happen once at launch: the notification
    /// category for export reminders, and the delegate that turns a tapped
    /// reminder into an ``ExportRequest``.
    ///
    /// Call from `application(_:didFinishLaunchingWithOptions:)` or a
    /// `UIApplicationDelegateAdaptor`. Skipping it costs you tap-to-compose on
    /// export notifications; everything else still works.
    @MainActor
    public static func configure(notificationDelegate: Bool = true) {
        ExportScheduler.registerCategory()
        if notificationDelegate {
            UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        }
    }
}

// MARK: - TrackerKitConfiguration

/// Options for ``TrackerKitRootView``.
public struct TrackerKitConfiguration: Sendable {

    /// Keeps everything in memory. For previews, tests and demos.
    public var inMemory: Bool

    /// App Group used for both the SwiftData store and the widget snapshot.
    /// Pass your group (`group.com.yourcompany.app`) to make widgets work.
    /// Without it the app runs fine and widgets simply never update.
    public var appGroupIdentifier: String?

    /// Populates three sample profiles with ~120 days of history when the store
    /// is empty. Leave on for a demo; turn off for a real app.
    public var seedSampleDataWhenEmpty: Bool

    /// Calendar used for every period, streak and bucket calculation.
    public var calendar: Calendar

    /// Tuning for how forgiving the stoplights are.
    public var stoplight: StoplightEngine

    /// Visual theme. Defaults to ``TrackerTheme/nocturne``.
    ///
    /// Note that Nocturne is a single-appearance theme — it forces dark. That is
    /// a deliberate identity choice rather than an oversight, but it does
    /// override the viewer's own light/dark preference, so an app that must
    /// respect that setting should use ``TrackerTheme/standard`` instead.
    public var theme: TrackerTheme

    /// Seconds of inactivity before the session drops back to the profile picker.
    /// Zero disables it.
    public var autoLockInterval: TimeInterval

    /// Which tab opens first. Also the landing point for a deep link.
    public var initialTab: TrackerKitTab

    /// Shows the live hero-style picker on the dashboard. A showcase control —
    /// leave off in a real app.
    public var showsHeroStyleSwitcher: Bool

    /// Opens straight into this profile instead of showing the picker.
    ///
    /// For kiosk-style single-user installs, demos and screenshots. Ignored when
    /// the named profile is PIN-protected — skipping a gate someone deliberately
    /// put up would defeat the point of it.
    public var autoSelectProfileNamed: String?

    /// How many people this install is for.
    ///
    /// A phone or a watch belongs to one person and is already gated by Face ID
    /// or a passcode, so a second 4-digit gate inside it protects little and
    /// costs a screen. A shared iPad is the opposite case, which is why this is
    /// a setting rather than a removal.
    public enum ProfileMode: String, Sendable, CaseIterable, Hashable {
        /// One person. No picker, no PIN, no profile management.
        case single
        /// Several people sharing a device, each behind their own PIN.
        case shared

        public var displayName: String {
            switch self {
            case .single: "Just me"
            case .shared: "Shared device"
            }
        }
    }

    /// Defaults to ``ProfileMode/single``: most installs are one person's own
    /// device.
    public var profileMode: ProfileMode

    public init(
        inMemory: Bool = false,
        appGroupIdentifier: String? = nil,
        seedSampleDataWhenEmpty: Bool = false,
        calendar: Calendar = .current,
        stoplight: StoplightEngine = .standard,
        // Nocturne is the shipped identity. `.standard` remains available and
        // deliberately neutral for anyone who would rather bring their own.
        theme: TrackerTheme = .nocturne,
        autoLockInterval: TimeInterval = 900,
        autoSelectProfileNamed: String? = nil,
        initialTab: TrackerKitTab = .today,
        showsHeroStyleSwitcher: Bool = false,
        profileMode: ProfileMode = .single
    ) {
        self.profileMode = profileMode
        self.inMemory = inMemory
        self.appGroupIdentifier = appGroupIdentifier
        self.seedSampleDataWhenEmpty = seedSampleDataWhenEmpty
        self.calendar = calendar
        self.stoplight = stoplight
        self.theme = theme
        self.autoLockInterval = autoLockInterval
        self.autoSelectProfileNamed = autoSelectProfileNamed
        self.initialTab = initialTab
        self.showsHeroStyleSwitcher = showsHeroStyleSwitcher
    }

    /// The demo configuration: in-memory, seeded, no App Group.
    public static let demo = TrackerKitConfiguration(
        inMemory: true,
        seedSampleDataWhenEmpty: true,
        showsHeroStyleSwitcher: true
    )
}

// MARK: - TrackerKitTab

/// The tabs in ``TrackerKitTabs``. Public so a host app can deep-link to one.
public enum TrackerKitTab: String, Sendable, CaseIterable, Hashable {
    case today
    case gallery
    case settings
}

// MARK: - NotificationRouter

/// Turns a tapped export reminder into a ``Notification`` the root view listens for.
///
/// Kept as a tiny singleton rather than something the host app has to own, since
/// `UNUserNotificationCenter.delegate` is a single global slot. A host app that
/// already has its own delegate should skip `notificationDelegate: true` and call
/// ``NotificationRouter/handle(response:)`` from its own.
@MainActor
public final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

    public static let shared = NotificationRouter()

    /// Posts the export request so the UI can open a composer.
    public func handle(response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        guard ExportRequest(userInfo: userInfo) != nil else { return }

        if response.actionIdentifier == ExportScheduler.snoozeActionIdentifier {
            // Snooze is handled by rescheduling, not by opening a composer.
            return
        }

        NotificationCenter.default.post(
            name: .trackerKitExportRequested,
            object: nil,
            userInfo: userInfo
        )
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        handle(response: response)
    }

    /// Shows export reminders even while the app is foregrounded — the reminder
    /// is the whole mechanism, and swallowing it because the app happens to be
    /// open would strand the user.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

public extension Notification.Name {
    /// Posted when an export reminder is tapped. `userInfo` decodes with
    /// ``ExportRequest/init(userInfo:)``.
    static let trackerKitExportRequested = Notification.Name("trackerkit.export.requested")
}

import Foundation
import SwiftUI
import Observation

/// Who is currently using the device, and whether they've proved it.
///
/// Kept separate from ``TrackerStore`` on purpose: the store is about data, this
/// is about access. On a shared iPad they change at different times — switching
/// profiles is an access event, logging a glass of water is a data event.
@MainActor
@Observable
public final class ProfileSession {

    // MARK: State

    public enum State: Equatable {
        /// No profile chosen — showing the picker.
        case choosing
        /// A PIN-protected profile is selected and waiting on the PIN.
        case authenticating(profileID: UUID)
        /// In.
        case active(profileID: UUID)
    }

    public private(set) var state: State = .choosing

    /// Set when the last PIN attempt failed, for the pad to show.
    public private(set) var lastVerification: PINVerification?

    /// Profile awaiting a PIN, if any.
    public var pendingProfile: Profile? {
        guard case .authenticating(let id) = state else { return nil }
        return store.profiles.first { $0.id == id }
    }

    public var activeProfileID: UUID? {
        guard case .active(let id) = state else { return nil }
        return id
    }

    public var isActive: Bool { activeProfileID != nil }

    // MARK: Configuration

    /// Seconds of inactivity after which the session locks back to the picker.
    /// Zero disables auto-lock. Defaults to 15 minutes — long enough not to annoy,
    /// short enough that an iPad left on the counter doesn't stay open on a kid's
    /// profile all afternoon.
    public var autoLockInterval: TimeInterval = 900

    /// Where the widget payload gets published. `nil` disables widget publishing.
    public var appGroupIdentifier: String?

    private let store: TrackerStore
    private let pinManager: PINManager
    private var lastInteraction: Date = .now

    public init(
        store: TrackerStore,
        pinManager: PINManager = .shared,
        appGroupIdentifier: String? = nil
    ) {
        self.store = store
        self.pinManager = pinManager
        self.appGroupIdentifier = appGroupIdentifier
    }

    // MARK: Selecting

    /// Picks a profile. Goes straight in when unprotected, otherwise asks for a PIN.
    public func select(_ profile: Profile) {
        lastVerification = nil

        guard profile.isPINProtected, pinManager.hasPIN(for: profile.id) else {
            enter(profile.id)
            return
        }
        state = .authenticating(profileID: profile.id)
    }

    /// Checks a PIN against the pending profile.
    @discardableResult
    public func submit(pin: String) -> PINVerification {
        guard case .authenticating(let id) = state else {
            return .noPINSet
        }

        let result = pinManager.verify(pin, for: id)
        lastVerification = result

        if case .success = result {
            enter(id)
        }
        return result
    }

    /// Backs out of the PIN prompt to the picker.
    public func cancelAuthentication() {
        lastVerification = nil
        state = .choosing
    }

    /// Leaves the current profile.
    public func signOut() {
        lastVerification = nil
        state = .choosing
        store.activeProfileID = nil
    }

    private func enter(_ profileID: UUID) {
        state = .active(profileID: profileID)
        store.activeProfileID = profileID
        // Entering a profile *is* the daily login — this is what feeds the streak.
        store.recordLogin(for: profileID)
        touch()
        publishWidgets()
    }

    // MARK: Auto-lock

    /// Marks activity. Call from a root-level gesture or on each logged entry.
    public func touch() {
        lastInteraction = .now
    }

    /// Locks back to the picker if the session has gone stale. Call on
    /// `scenePhase` becoming active.
    public func lockIfIdle(now: Date = .now) {
        guard autoLockInterval > 0, isActive else { return }
        guard now.timeIntervalSince(lastInteraction) > autoLockInterval else { return }
        signOut()
    }

    /// Whether the active profile could lock — used to decide if a "Lock" button
    /// is worth showing.
    public var canLock: Bool {
        guard let id = activeProfileID else { return false }
        return pinManager.hasPIN(for: id)
    }

    // MARK: Widgets

    public func publishWidgets() {
        guard let appGroupIdentifier else { return }
        store.publishWidgetSnapshot(appGroupIdentifier: appGroupIdentifier)
    }

    // MARK: PIN management

    public func setPIN(_ pin: String, for profile: Profile) throws {
        try pinManager.setPIN(pin, for: profile.id)
        var updated = profile
        updated.isPINProtected = true
        store.update(updated)
    }

    public func removePIN(for profile: Profile) {
        pinManager.removePIN(for: profile.id)
        var updated = profile
        updated.isPINProtected = false
        store.update(updated)
    }

    public func hasPIN(for profileID: UUID) -> Bool {
        pinManager.hasPIN(for: profileID)
    }

    public func lockoutExpiry(for profileID: UUID) -> Date? {
        pinManager.lockoutExpiry(for: profileID)
    }

    public func remainingAttempts(for profileID: UUID) -> Int {
        pinManager.remainingAttempts(for: profileID)
    }

    /// Parent override: clears a lockout without the PIN. Gate this behind an
    /// owner-authenticated path in the host app.
    public func administrativeUnlock(for profileID: UUID) {
        pinManager.administrativeUnlock(for: profileID)
        lastVerification = nil
    }
}

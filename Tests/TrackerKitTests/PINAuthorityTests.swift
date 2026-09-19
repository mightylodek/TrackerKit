import Testing
import Foundation
import SwiftData
@testable import TrackerKit

/// Who may change whose PIN, and how a forgotten one is recovered.
///
/// Before this existed, any signed-in profile could open Settings, tap any other
/// profile, and switch its PIN off — so a child could unlock their own profile
/// and disable a parent's. The recovery route and the bypass were one door.
@Suite("PIN authority")
@MainActor
struct PINAuthorityTests {

    private func makeSession() throws -> (TrackerStore, ProfileSession) {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        return (store, ProfileSession(store: store, pinManager: .inMemory()))
    }

    // MARK: Roles

    @Test("The first profile on a device owns it")
    func firstProfileIsOwner() throws {
        let (store, _) = try makeSession()
        let first = store.addProfile(name: "Parent")
        #expect(first.role == .owner)

        // Without this a fresh install has no owner, so nobody can reset a
        // forgotten PIN and the device is one 4-digit code from a reinstall.
        let second = store.addProfile(name: "Kid")
        #expect(second.role == .member)
    }

    /// Regression: the first-owner rule originally read the cached `profiles`
    /// array, which `performBatch` leaves stale. Seeding three profiles inside a
    /// batch saw an empty array on every pass and promoted all three to owner —
    /// handing two children the reset button and the device wipe.
    @Test("Roles survive batched seeding")
    func rolesSurviveBatching() throws {
        let (store, _) = try makeSession()
        store.performBatch {
            _ = store.addProfile(name: "Parent", role: .owner)
            _ = store.addProfile(name: "Kid", role: .member)
            _ = store.addProfile(name: "Sibling", role: .member)
        }

        #expect(store.profiles.count == 3)
        #expect(store.profiles.filter { $0.role == .owner }.count == 1)
        #expect(store.profiles.first { $0.name == "Kid" }?.role == .member)
    }

    @Test("The first profile owns it even when created inside a batch")
    func firstOwnerInsideBatch() throws {
        let (store, _) = try makeSession()
        store.performBatch {
            // A caller that doesn't think about roles still must not leave the
            // device ownerless.
            _ = store.addProfile(name: "Solo")
        }
        #expect(store.profiles.first?.role == .owner)
    }

    @Test("An explicit role still wins after the first profile")
    func explicitRoleHonoured() throws {
        let (store, _) = try makeSession()
        _ = store.addProfile(name: "Parent")
        let other = store.addProfile(name: "Other parent", role: .owner)
        #expect(other.role == .owner)
    }

    // MARK: Authority

    @Test("You always govern your own PIN")
    func selfServiceOverSelf() throws {
        let (store, session) = try makeSession()
        let kid = store.addProfile(name: "Kid", role: .member)
        _ = store.addProfile(name: "Parent", role: .owner)
        session.select(kid)

        #expect(session.authority(over: kid) == .selfService)
    }

    @Test("A member has no authority over anyone else")
    func memberHasNoAuthorityOverOthers() throws {
        let (store, session) = try makeSession()
        let parent = store.addProfile(name: "Parent")
        let kid = store.addProfile(name: "Kid", role: .member)
        let sibling = store.addProfile(name: "Sibling", role: .member)
        session.select(kid)

        #expect(session.authority(over: parent) == PINAuthority.none)
        #expect(session.authority(over: sibling) == PINAuthority.none)
    }

    @Test("An owner governs everyone")
    func ownerGovernsAll() throws {
        let (store, session) = try makeSession()
        let parent = store.addProfile(name: "Parent")
        let kid = store.addProfile(name: "Kid", role: .member)
        session.select(parent)

        #expect(session.authority(over: kid) == .owner)
        #expect(session.activeProfileIsOwner)
    }

    @Test("Nobody signed in means no authority")
    func signedOutHasNoAuthority() throws {
        let (store, session) = try makeSession()
        let kid = store.addProfile(name: "Kid", role: .member)
        #expect(session.authority(over: kid) == PINAuthority.none)
        #expect(!session.activeProfileIsOwner)
    }

    // MARK: Reset

    @Test("An owner can clear a forgotten PIN")
    func ownerResetsAMemberPIN() throws {
        let (store, session) = try makeSession()
        let parent = store.addProfile(name: "Parent")
        var kid = store.addProfile(name: "Kid", role: .member)
        try session.setPIN("1379", for: kid)
        kid = store.profiles.first { $0.id == kid.id } ?? kid
        #expect(session.hasPIN(for: kid.id))

        session.select(parent)
        #expect(session.resetPIN(for: kid))
        #expect(!session.hasPIN(for: kid.id))
        #expect(store.profiles.first { $0.id == kid.id }?.isPINProtected == false)
    }

    /// The bug this whole model exists to close.
    @Test("A member cannot clear another profile's PIN")
    func memberCannotResetAnother() throws {
        let (store, session) = try makeSession()
        var parent = store.addProfile(name: "Parent")
        let kid = store.addProfile(name: "Kid", role: .member)
        try session.setPIN("2468", for: parent)
        parent = store.profiles.first { $0.id == parent.id } ?? parent

        session.select(kid)
        #expect(!session.resetPIN(for: parent), "A member cleared an owner's PIN")
        #expect(session.hasPIN(for: parent.id), "The owner's PIN was removed anyway")
    }

    @Test("Resetting your own PIN is not an administrative act")
    func selfResetIsRefused() throws {
        let (store, session) = try makeSession()
        var parent = store.addProfile(name: "Parent")
        try session.setPIN("1379", for: parent)
        parent = store.profiles.first { $0.id == parent.id } ?? parent
        session.select(parent)

        // `.selfService` changes a PIN by setting a new one, not by clearing it
        // without knowing the old one.
        #expect(!session.resetPIN(for: parent))
    }

    // MARK: Device owner recovery

    @Test("An owner can get in with the device passcode")
    func ownerRecoversWithDeviceAuth() throws {
        let (store, session) = try makeSession()
        var parent = store.addProfile(name: "Parent")
        try session.setPIN("1379", for: parent)
        parent = store.profiles.first { $0.id == parent.id } ?? parent

        session.select(parent)
        #expect(session.pendingProfileCanUseDeviceOwnerAuth)
        #expect(session.enterAfterDeviceOwnerAuth())
        #expect(session.activeProfileID == parent.id)
    }

    /// The device passcode is the parent's, so offering it on a child's profile
    /// would hand them the key to their own lock.
    @Test("A member's profile does not offer device-passcode recovery")
    func memberCannotUseDeviceAuth() throws {
        let (store, session) = try makeSession()
        _ = store.addProfile(name: "Parent")
        var kid = store.addProfile(name: "Kid", role: .member)
        try session.setPIN("2468", for: kid)
        kid = store.profiles.first { $0.id == kid.id } ?? kid

        session.select(kid)
        #expect(!session.pendingProfileCanUseDeviceOwnerAuth)
        #expect(!session.enterAfterDeviceOwnerAuth())
        #expect(session.activeProfileID == nil)
    }

    @Test("Device recovery only works while a PIN prompt is open")
    func recoveryNeedsAnOpenPrompt() throws {
        let (store, session) = try makeSession()
        _ = store.addProfile(name: "Parent")
        #expect(!session.enterAfterDeviceOwnerAuth())
        #expect(session.activeProfileID == nil)
    }

    @Test("Recovering clears a standing lockout")
    func recoveryClearsLockout() throws {
        let (store, session) = try makeSession()
        var parent = store.addProfile(name: "Parent")
        try session.setPIN("1379", for: parent)
        parent = store.profiles.first { $0.id == parent.id } ?? parent

        session.select(parent)
        for _ in 0..<6 { _ = session.submit(pin: "0000") }
        #expect(session.lockoutExpiry(for: parent.id) != nil)

        session.select(parent)
        #expect(session.enterAfterDeviceOwnerAuth())
        #expect(session.lockoutExpiry(for: parent.id) == nil)
    }

    // MARK: The authenticator itself

    @Test("A scripted authenticator reports what it was told to")
    func stubBehaviour() async {
        let refuses = StubDeviceOwnerAuth(succeeds: false)
        #expect(await refuses.authenticate(reason: "x") == false)

        let unavailable = StubDeviceOwnerAuth(isAvailable: false, succeeds: true)
        #expect(await unavailable.authenticate(reason: "x") == false)
        #expect(unavailable.promptCount == 1)
    }
}

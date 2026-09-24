import Testing
import Foundation
import SwiftData
@testable import TrackerKit

/// Single-profile installs, and what stays true for shared ones.
///
/// A phone or a watch belongs to one person and is already gated by Face ID or
/// a passcode, so a second 4-digit gate inside it costs a screen and protects
/// little. A shared iPad is the opposite case — which is why this is a setting
/// rather than a removal, and why the PIN rules below still have to hold.
@Suite("Profile mode")
@MainActor
struct ProfileModeTests {

    private func makeSession() throws -> (TrackerStore, ProfileSession) {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        return (store, ProfileSession(store: store, pinManager: .inMemory()))
    }

    @Test("Single is the default: most installs are one person's own device")
    func singleIsDefault() {
        #expect(TrackerKitConfiguration().profileMode == .single)
    }

    @Test("Entering without authentication signs the profile in")
    func entersWithoutAGate() throws {
        let (store, session) = try makeSession()
        let me = store.addProfile(name: "Me")

        session.enterWithoutAuthentication(me)
        #expect(session.activeProfileID == me.id)
        #expect(session.isActive)
    }

    /// Entering ungated must not quietly clear a PIN — switching an install back
    /// to shared has to find every gate exactly as it was left.
    @Test("Going ungated leaves existing PINs intact")
    func pinsSurviveUngatedEntry() throws {
        let (store, session) = try makeSession()
        var me = store.addProfile(name: "Me")
        try session.setPIN("1379", for: me)
        me = store.profiles.first { $0.id == me.id } ?? me

        session.enterWithoutAuthentication(me)

        #expect(session.hasPIN(for: me.id), "The PIN was dropped")
        #expect(store.profiles.first { $0.id == me.id }?.isPINProtected == true)
    }

    @Test("Ungated entry still counts as the daily login")
    func loginIsRecorded() throws {
        let (store, session) = try makeSession()
        let me = store.addProfile(name: "Me")
        session.enterWithoutAuthentication(me)

        // Entering a profile is what feeds the streak; skipping the gate must
        // not skip that.
        #expect(store.loginStreak(for: me.id).current >= 1)
    }

    @Test("Signing out of a single-profile install still works")
    func signOutWorks() throws {
        let (store, session) = try makeSession()
        let me = store.addProfile(name: "Me")
        session.enterWithoutAuthentication(me)
        session.signOut()

        #expect(session.activeProfileID == nil)
        #expect(!session.isActive)
    }

    // MARK: The shared path is untouched

    @Test("A shared install still demands the PIN")
    func sharedStillGated() throws {
        let (store, session) = try makeSession()
        var kid = store.addProfile(name: "Kid")
        try session.setPIN("2468", for: kid)
        kid = store.profiles.first { $0.id == kid.id } ?? kid

        session.select(kid)
        #expect(session.activeProfileID == nil, "Selecting a protected profile signed straight in")

        #expect(session.submit(pin: "0000") == .incorrect(remainingAttempts: 4))
        #expect(session.submit(pin: "2468") == .success)
        #expect(session.activeProfileID == kid.id)
    }

    @Test("Authority rules are unchanged by the mode")
    func authorityUnchanged() throws {
        let (store, session) = try makeSession()
        let parent = store.addProfile(name: "Parent")
        let kid = store.addProfile(name: "Kid", role: .member)

        session.enterWithoutAuthentication(kid)
        #expect(session.authority(over: parent) == PINAuthority.none)

        session.enterWithoutAuthentication(parent)
        #expect(session.authority(over: kid) == .owner)
    }
}

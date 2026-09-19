import Foundation

// MARK: - DeviceOwnerAuthenticating

/// Authenticates the person holding the device, via biometrics or the device
/// passcode.
///
/// This is the root of trust for PIN recovery. On a family iPad the device
/// passcode belongs to the parent, which makes it exactly the right credential
/// for "prove you're the owner" — and it means a forgotten owner PIN never means
/// reinstalling the app and losing everything.
///
/// A protocol rather than a direct `LAContext` call for the same reason
/// ``SecretStorage`` is one: a test bundle has no entitlement to authenticate
/// anybody, so the real implementation can never run under test.
public protocol DeviceOwnerAuthenticating: Sendable {
    /// Whether the device can authenticate its owner at all. `false` on a device
    /// with no passcode set, where there is nothing to check against.
    var isAvailable: Bool { get }

    /// Prompts, and reports whether the owner proved themselves.
    /// `reason` is shown to the user by the system.
    func authenticate(reason: String) async -> Bool
}

// MARK: - StubDeviceOwnerAuth

/// A scripted stand-in for tests and previews.
public final class StubDeviceOwnerAuth: DeviceOwnerAuthenticating, @unchecked Sendable {
    public var isAvailable: Bool
    public var succeeds: Bool
    public private(set) var promptCount = 0

    public init(isAvailable: Bool = true, succeeds: Bool = true) {
        self.isAvailable = isAvailable
        self.succeeds = succeeds
    }

    public func authenticate(reason: String) async -> Bool {
        promptCount += 1
        return isAvailable && succeeds
    }
}

#if canImport(LocalAuthentication)

import LocalAuthentication

// MARK: - LocalDeviceOwnerAuth

/// The real thing: biometrics, falling back to the device passcode.
public struct LocalDeviceOwnerAuth: DeviceOwnerAuthenticating {
    public init() {}

    /// `.deviceOwnerAuthentication` rather than `...WithBiometrics`: the passcode
    /// fallback is the point. A parent whose Face ID fails, or who never set it
    /// up, still has to be able to recover a child's PIN.
    private var policy: LAPolicy { .deviceOwnerAuthentication }

    public var isAvailable: Bool {
        LAContext().canEvaluatePolicy(policy, error: nil)
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(policy, error: nil) else { return false }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            // A cancel, a failed match and a missing passcode all arrive here.
            // None of them is an unlock.
            return false
        }
    }
}

#endif

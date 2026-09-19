import Foundation
import CryptoKit

// MARK: - PINVerification

/// Outcome of checking a PIN.
public enum PINVerification: Sendable, Equatable {
    case success
    /// Wrong PIN. `remainingAttempts` counts down to a lockout.
    case incorrect(remainingAttempts: Int)
    /// Too many wrong tries. No further attempts accepted until `until`.
    case lockedOut(until: Date)
    /// The profile has no PIN set, so there is nothing to verify against.
    case noPINSet
}

// MARK: - PINPadOutcome

/// What the pad should do after a completed entry.
///
/// Unlocking and setting a PIN look identical on screen and are not the same
/// thing underneath: unlocking produces a security verdict, whereas the first
/// step of setup just takes an entry and asks for it again. Setup used to signal
/// that by returning `.incorrect(remainingAttempts: 99)`, which made the pad
/// shake and show "Wrong PIN — 99 attempts left" on a perfectly good entry.
public enum PINPadOutcome: Sendable, Equatable {
    /// Entry taken. Clear the dots, no error, no shake.
    case accepted
    /// Entry taken, but say something first — a caution, not a failure.
    case acceptedWithWarning(String)
    /// Not usable. Show the message and shake, but this is not a failed unlock
    /// attempt and must not count against the lockout ladder.
    case rejected(String)
    /// A real verdict from ``PINManager``.
    case verified(PINVerification)
}

// MARK: - PINManager

/// Stores and checks the 4-digit PINs that gate profile switching.
///
/// ## What this is and isn't
/// A 4-digit PIN is a **10,000-combination secret**. Any honest implementation
/// treats it as a convenience gate — the thing that stops a sibling opening the
/// wrong profile on a shared iPad — not as encryption. The protections that
/// actually matter at this key size are the ones implemented here:
///
/// - the PIN is never stored, only a salted hash, iterated to make offline
///   guessing slow rather than instant;
/// - the salt and hash live in the keychain, device-only, never synced;
/// - failed attempts trigger an **escalating lockout**, which is what makes
///   brute-forcing 10,000 combinations impractical in person.
///
/// If a host app needs real confidentiality for the data behind the gate, layer
/// file protection or a passphrase-derived key on top. Don't ask four digits to
/// do a job four digits cannot do.
@MainActor
public final class PINManager {

    // MARK: Configuration

    /// Wrong attempts allowed before the first lockout.
    public var maxAttempts: Int = 5
    /// Lockout durations in seconds, escalating with each round of failures.
    /// The last value repeats once exhausted.
    public var lockoutLadder: [TimeInterval] = [60, 300, 900, 3600]
    /// Required PIN length. Four by default; six also works if a host app wants it.
    public var pinLength: Int = 4
    /// Hash iterations. Tuned to be imperceptible on-device but costly in bulk.
    public var iterations: Int = 120_000

    private let keychain: any SecretStorage
    private let defaults: UserDefaults

    public init(
        keychain: any SecretStorage = KeychainStore(service: "com.trackerkit.pin"),
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    /// A manager backed by in-memory storage, for tests and previews.
    /// Fewer hash iterations too, since nothing here needs to resist an attacker.
    public static func inMemory() -> PINManager {
        let manager = PINManager(
            keychain: InMemorySecretStorage(),
            defaults: UserDefaults(suiteName: "com.trackerkit.pin.ephemeral.\(UUID().uuidString)")
                ?? .standard
        )
        manager.iterations = 1_000
        return manager
    }

    public static let shared = PINManager()

    // MARK: Keys

    private func hashAccount(_ profileID: UUID) -> String { "pin.hash.\(profileID.uuidString)" }
    private func saltAccount(_ profileID: UUID) -> String { "pin.salt.\(profileID.uuidString)" }
    private func attemptsKey(_ profileID: UUID) -> String { "trackerkit.pin.attempts.\(profileID.uuidString)" }
    private func lockoutKey(_ profileID: UUID) -> String { "trackerkit.pin.lockout.\(profileID.uuidString)" }
    private func roundKey(_ profileID: UUID) -> String { "trackerkit.pin.round.\(profileID.uuidString)" }

    // MARK: Validation

    /// Whether `pin` is structurally acceptable: right length, digits only.
    public func isWellFormed(_ pin: String) -> Bool {
        pin.count == pinLength && pin.allSatisfy(\.isNumber)
    }

    /// PINs rejected outright regardless of length rules. Sequential runs and
    /// repeated digits are the first things anyone guesses.
    public static let weakPINs: Set<String> = [
        "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999",
        "1234", "4321", "0123", "3210", "1212", "2121", "1122", "6969", "2580"
    ]

    public func isWeak(_ pin: String) -> Bool {
        Self.weakPINs.contains(pin)
    }

    // MARK: Hashing

    /// Salted, iterated SHA-256. Deliberately slow to evaluate in bulk.
    private func hash(pin: String, salt: Data) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(pin.utf8)))
        for _ in 1..<iterations {
            digest = Data(SHA256.hash(data: salt + digest))
        }
        return digest
    }

    private func randomSalt(byteCount: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // Fall back to a UUID-derived salt rather than a predictable constant.
            return Data((UUID().uuidString + UUID().uuidString).utf8)
        }
        return Data(bytes)
    }

    // MARK: Public API

    public func hasPIN(for profileID: UUID) -> Bool {
        keychain.exists(account: hashAccount(profileID))
    }

    /// Sets or replaces a profile's PIN. Clears any standing lockout.
    /// - Throws: ``PINError`` when the PIN is malformed.
    public func setPIN(_ pin: String, for profileID: UUID) throws {
        guard isWellFormed(pin) else { throw PINError.malformed(expectedLength: pinLength) }

        let salt = randomSalt()
        let digest = hash(pin: pin, salt: salt)

        do {
            try keychain.set(salt, account: saltAccount(profileID))
            try keychain.set(digest, account: hashAccount(profileID))
        } catch {
            // A PIN that silently failed to save is worse than no PIN at all:
            // the profile would show a lock it cannot actually enforce.
            throw PINError.storageFailed(error.localizedDescription)
        }
        clearFailures(for: profileID)
    }

    /// Removes PIN protection from a profile.
    public func removePIN(for profileID: UUID) {
        keychain.remove(account: hashAccount(profileID))
        keychain.remove(account: saltAccount(profileID))
        clearFailures(for: profileID)
    }

    /// Checks a PIN, applying and advancing the lockout ladder.
    @discardableResult
    public func verify(_ pin: String, for profileID: UUID) -> PINVerification {
        if let until = lockoutExpiry(for: profileID), until > .now {
            return .lockedOut(until: until)
        }

        guard let storedHash = keychain.data(account: hashAccount(profileID)),
              let salt = keychain.data(account: saltAccount(profileID))
        else { return .noPINSet }

        let candidate = hash(pin: pin, salt: salt)

        // Constant-time comparison — a length or early-exit difference leaks
        // information about how close a guess was.
        let matches = constantTimeEquals(candidate, storedHash)

        if matches {
            clearFailures(for: profileID)
            return .success
        }

        return registerFailure(for: profileID)
    }

    /// Changes a PIN, requiring the current one.
    public func changePIN(from current: String, to new: String, for profileID: UUID) throws {
        switch verify(current, for: profileID) {
        case .success:
            try setPIN(new, for: profileID)
        case .lockedOut(let until):
            throw PINError.lockedOut(until: until)
        case .incorrect:
            throw PINError.incorrect
        case .noPINSet:
            try setPIN(new, for: profileID)
        }
    }

    // MARK: Lockout

    /// When the current lockout ends, or `nil` if not locked.
    public func lockoutExpiry(for profileID: UUID) -> Date? {
        let stamp = defaults.double(forKey: lockoutKey(profileID))
        guard stamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: stamp)
        return date > .now ? date : nil
    }

    public func isLockedOut(for profileID: UUID) -> Bool {
        lockoutExpiry(for: profileID) != nil
    }

    /// Wrong attempts left before the next lockout.
    public func remainingAttempts(for profileID: UUID) -> Int {
        max(0, maxAttempts - defaults.integer(forKey: attemptsKey(profileID)))
    }

    private func registerFailure(for profileID: UUID) -> PINVerification {
        let failures = defaults.integer(forKey: attemptsKey(profileID)) + 1
        defaults.set(failures, forKey: attemptsKey(profileID))

        guard failures >= maxAttempts else {
            return .incorrect(remainingAttempts: max(0, maxAttempts - failures))
        }

        // Ladder advances each time the attempt budget is burned through.
        let round = defaults.integer(forKey: roundKey(profileID))
        let duration = lockoutLadder[min(round, lockoutLadder.count - 1)]
        let until = Date.now.addingTimeInterval(duration)

        defaults.set(until.timeIntervalSince1970, forKey: lockoutKey(profileID))
        defaults.set(round + 1, forKey: roundKey(profileID))
        defaults.set(0, forKey: attemptsKey(profileID))

        return .lockedOut(until: until)
    }

    private func clearFailures(for profileID: UUID) {
        defaults.removeObject(forKey: attemptsKey(profileID))
        defaults.removeObject(forKey: lockoutKey(profileID))
        defaults.removeObject(forKey: roundKey(profileID))
    }

    /// Clears a lockout without knowing the PIN. Only ever call this from an
    /// owner-authenticated path — it is the parent override, not a back door.
    public func administrativeUnlock(for profileID: UUID) {
        clearFailures(for: profileID)
    }

    // MARK: Helpers

    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

// MARK: - PINError

public enum PINError: Error, LocalizedError, Equatable {
    case malformed(expectedLength: Int)
    case incorrect
    case lockedOut(until: Date)
    case storageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let length):
            return "Enter exactly \(length) digits."
        case .incorrect:
            return "That PIN is incorrect."
        case .lockedOut(let until):
            let remaining = Int(until.timeIntervalSinceNow / 60) + 1
            return "Too many attempts. Try again in \(remaining) minute\(remaining == 1 ? "" : "s")."
        case .storageFailed(let reason):
            return "Could not save the PIN: \(reason)"
        }
    }
}

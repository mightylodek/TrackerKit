import Foundation
import Security

// MARK: - SecretStorage

/// Where ``PINManager`` keeps salted PIN hashes.
///
/// Abstracted for two reasons, one practical and one architectural. Practically:
/// the keychain needs an application container, so a unit-test bundle with no
/// host app cannot write to it and every PIN test would fail for reasons having
/// nothing to do with PINs. Architecturally: a host app with its own keychain
/// wrapper, an access group, or a hardware-backed store can supply it here
/// instead of being stuck with this one.
public protocol SecretStorage: Sendable {
    func set(_ data: Data, account: String) throws
    func data(account: String) -> Data?
    func exists(account: String) -> Bool
    func remove(account: String)
}

public extension SecretStorage {
    func exists(account: String) -> Bool { data(account: account) != nil }
}

// MARK: - InMemorySecretStorage

/// Non-persistent storage, for tests and previews.
///
/// Never ship this as a real PIN store — it forgets everything on launch, which
/// means the gate is open on every cold start.
public final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func set(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[account] = data
    }

    public func data(account: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[account]
    }

    public func exists(account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return items[account] != nil
    }

    public func remove(account: String) {
        lock.lock(); defer { lock.unlock() }
        items[account] = nil
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        items.removeAll()
    }
}

// MARK: - KeychainStore

/// Thin wrapper over the keychain for the handful of secrets TrackerKit keeps.
///
/// Items are stored `whenUnlockedThisDeviceOnly` — a PIN that syncs to iCloud and
/// lands on the user's other devices is a liability, not a feature.
public struct KeychainStore: SecretStorage, Sendable {

    public enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)
        case dataConversionFailed

        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return "Keychain error \(status): \(message)"
            case .dataConversionFailed:
                return "Could not convert the keychain value."
            }
        }
    }

    /// Namespace for every item this store writes. Override it to isolate a host
    /// app's items, or to share them with an extension via an access group.
    public var service: String
    public var accessGroup: String?

    public init(service: String = "com.trackerkit.secrets", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: Queries

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    // MARK: CRUD

    /// Writes `data`, replacing anything already stored under `account`.
    public func set(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func set(_ string: String, account: String) throws {
        guard let data = string.data(using: .utf8) else { throw KeychainError.dataConversionFailed }
        try set(data, account: account)
    }

    /// Reads an item, or `nil` when nothing is stored.
    public func data(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    public func string(account: String) -> String? {
        data(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func exists(account: String) -> Bool {
        data(account: account) != nil
    }

    /// Removes an item. Missing items are not an error.
    public func remove(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    /// Wipes every item in this service. Used when resetting the library.
    public func removeAll() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        SecItemDelete(query as CFDictionary)
    }
}

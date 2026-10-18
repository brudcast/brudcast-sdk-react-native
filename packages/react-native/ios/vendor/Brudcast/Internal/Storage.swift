import Foundation
import Security

/// Small values the SDK keeps between launches.
public final class BrudcastStorage {
    let defaults: UserDefaults
    public let directory: URL

    init(defaults: UserDefaults, directory: URL) {
        self.defaults = defaults
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func standard() -> BrudcastStorage {
        let defaults = UserDefaults(suiteName: "com.brudcast.sdk") ?? .standard
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return BrudcastStorage(defaults: defaults, directory: base.appendingPathComponent("Brudcast", isDirectory: true))
    }

    /// Reads a string.
    ///
    /// - Parameter key: The key.
    /// - Returns: The stored string, or nil.
    public func string(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    /// Stores a string, or removes the key when the value is nil.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - key: The key.
    public func set(_ value: String?, for key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Reads a boolean, false when absent.
    ///
    /// - Parameter key: The key.
    /// - Returns: The stored value.
    public func bool(_ key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Stores a boolean.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - key: The key.
    public func set(_ value: Bool, for key: String) {
        defaults.set(value, forKey: key)
    }

    /// Reads a JSON document from a file in the SDK's directory.
    ///
    /// - Parameter name: The file name.
    /// - Returns: The decoded document, or nil when the file is missing or unreadable.
    public func readJSON(_ name: String) -> Any? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    /// Writes a JSON document atomically to a file in the SDK's directory.
    ///
    /// - Parameters:
    ///   - object: The document.
    ///   - name: The file name.
    public func writeJSON(_ object: Any, to name: String) {
        let url = directory.appendingPathComponent(name)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            BrudcastLogger.shared.error("Could not encode \(name)")
            return
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            BrudcastLogger.shared.error("Could not write \(name): \(error.localizedDescription)")
        }
    }

    /// Deletes a file in the SDK's directory.
    ///
    /// - Parameter name: The file name.
    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

enum DeviceIdentifier {
    private static let service = "com.brudcast.sdk"
    private static let account = "device_id"
    private static let fallbackKey = "brudcast.device_id"

    enum KeychainRead: Equatable {
        case found(String)
        case missing
        case unavailable(OSStatus)
    }

    /// Loads this install's device id, creating it on first launch.
    ///
    /// The Keychain item is only ever added or updated, never deleted, so a launch that cannot read
    /// it, such as a background launch before the first unlock, does not destroy it. Such a launch
    /// uses an id for this process alone and leaves storage untouched.
    ///
    /// - Parameter storage: Where the id lives when the Keychain cannot be used at all.
    /// - Returns: The device id.
    static func load(storage: BrudcastStorage) -> String {
        load(storage: storage, read: readKeychain, write: writeKeychain)
    }

    /// Loads the device id through the given Keychain access, so tests can stand in for it.
    ///
    /// - Parameters:
    ///   - storage: Where the id lives when the Keychain cannot be used at all.
    ///   - read: Reads the Keychain item.
    ///   - write: Adds or updates the Keychain item, returning the Keychain status.
    /// - Returns: The device id.
    static func load(storage: BrudcastStorage, read: () -> KeychainRead, write: (String) -> OSStatus) -> String {
        switch read() {
        case .found(let existing):
            return existing
        case .unavailable(let status):
            if let fallback = storage.string(fallbackKey) {
                return fallback
            }
            BrudcastLogger.shared.warning("The Keychain is unavailable (\(status)), so this launch uses a temporary device id")
            return UUID().uuidString.lowercased()
        case .missing:
            let id = storage.string(fallbackKey) ?? UUID().uuidString.lowercased()
            if write(id) == errSecSuccess {
                storage.set(nil, for: fallbackKey)
            } else {
                storage.set(id, for: fallbackKey)
            }
            return id
        }
    }

    private static func readKeychain() -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                return .missing
            }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable(status)
        }
    }

    private static func writeKeychain(_ value: String) -> OSStatus {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attributes = identity
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status }
        return SecItemUpdate(identity as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
    }
}

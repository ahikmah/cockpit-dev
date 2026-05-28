import Foundation
import CryptoKit
import Security

// MARK: - Encryption Errors

/// Errors that can occur during encryption, decryption, or Keychain operations.
enum EncryptionError: Error, LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keychainStoreFailed(OSStatus)
    case keychainRetrieveFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case keychainItemNotFound
    case keychainDataCorrupted
    case invalidData

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .keychainStoreFailed(let status):
            return "Keychain store failed with status: \(status)"
        case .keychainRetrieveFailed(let status):
            return "Keychain retrieve failed with status: \(status)"
        case .keychainDeleteFailed(let status):
            return "Keychain delete failed with status: \(status)"
        case .keychainItemNotFound:
            return "Keychain item not found"
        case .keychainDataCorrupted:
            return "Keychain data is corrupted or unreadable"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

// MARK: - Keychain Storage

protocol KeychainStorage {
    func data(service: String, account: String) -> (status: OSStatus, data: Data?)
    func add(data: Data, service: String, account: String) -> OSStatus
    func update(data: Data, service: String, account: String) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

final class SystemKeychainStorage: KeychainStorage {
    static let shared = SystemKeychainStorage()

    private init() {}

    func data(service: String, account: String) -> (status: OSStatus, data: Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        return SecItemAdd(query as CFDictionary, nil)
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        return SecItemDelete(query as CFDictionary)
    }
}

final class InMemoryKeychainStorage: KeychainStorage {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    func data(service: String, account: String) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            guard let data = items[itemKey(service: service, account: account)] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        }
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        lock.withLock {
            let key = itemKey(service: service, account: account)
            guard items[key] == nil else { return errSecDuplicateItem }
            items[key] = data
            return errSecSuccess
        }
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        lock.withLock {
            let key = itemKey(service: service, account: account)
            guard items[key] != nil else { return errSecItemNotFound }
            items[key] = data
            return errSecSuccess
        }
    }

    func delete(service: String, account: String) -> OSStatus {
        lock.withLock {
            items.removeValue(forKey: itemKey(service: service, account: account))
            return errSecSuccess
        }
    }

    private func itemKey(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}

// MARK: - EncryptionService

/// Service responsible for AES-256-GCM encryption/decryption and macOS Keychain operations.
///
/// Tokens are encrypted before Keychain storage and masked in any UI display (Property 7).
class EncryptionService {

    // MARK: - Properties

    /// The service identifier used for Keychain entries.
    private let serviceIdentifier: String

    /// Storage backend for credential reads and writes.
    private let keychainStorage: KeychainStorage

    /// The symmetric key used for AES-256-GCM encryption.
    /// In production, this key is derived from or stored in the Keychain itself.
    private var encryptionKey: SymmetricKey?

    /// Process-local decrypted credential cache.
    ///
    /// Keychain reads can require user presence depending on the item ACL and
    /// macOS state. Since CockpitDev already gates the app behind the lock
    /// screen, keep successfully decrypted values in memory for the app process
    /// so switching workspaces does not re-prompt for the same GitLab account.
    private var cachedKeychainValues: [String: String] = [:]
    private let cacheLock = NSLock()

    // MARK: - Initialization

    /// Creates an EncryptionService with the specified service identifier.
    /// - Parameter serviceIdentifier: The Keychain service name (default: "com.cockpitdev.credentials")
    init(
        serviceIdentifier: String = "com.cockpitdev.credentials",
        keychainStorage: KeychainStorage = SystemKeychainStorage.shared
    ) {
        self.serviceIdentifier = serviceIdentifier
        self.keychainStorage = keychainStorage
    }

    // MARK: - Encryption Key Management

    /// Loads the encryption key from Keychain or creates and stores a new one.
    private func loadOrCreateEncryptionKey() -> SymmetricKey {
        let keyTag = "\(serviceIdentifier).encryptionKey"

        let result = keychainStorage.data(service: serviceIdentifier, account: keyTag)

        if result.status == errSecSuccess, let keyData = result.data {
            return SymmetricKey(data: keyData)
        }

        // Generate a new key and store it
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        let addStatus = keychainStorage.add(data: keyData, service: serviceIdentifier, account: keyTag)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            // If we can't store the key, use the generated one in memory
            // This is a fallback; in production this should be handled more robustly
        }

        return newKey
    }

    private func currentEncryptionKey() -> SymmetricKey {
        if let encryptionKey {
            return encryptionKey
        }

        let loadedKey = loadOrCreateEncryptionKey()
        encryptionKey = loadedKey
        return loadedKey
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypts a plaintext string using AES-256-GCM with a random nonce.
    /// - Parameter plaintext: The string to encrypt.
    /// - Returns: The combined sealed box data (nonce + ciphertext + tag).
    /// - Throws: `EncryptionError.encryptionFailed` if encryption fails.
    func encrypt(_ plaintext: String) throws -> Data {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed("Failed to convert plaintext to UTF-8 data")
        }

        do {
            let sealedBox = try AES.GCM.seal(plaintextData, using: currentEncryptionKey())
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed("Failed to produce combined sealed box")
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypts AES-256-GCM encrypted data back to a plaintext string.
    /// - Parameter ciphertext: The combined sealed box data (nonce + ciphertext + tag).
    /// - Returns: The decrypted plaintext string.
    /// - Throws: `EncryptionError.decryptionFailed` if decryption fails.
    func decrypt(_ ciphertext: Data) throws -> String {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decryptedData = try AES.GCM.open(sealedBox, using: currentEncryptionKey())
            guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
                throw EncryptionError.decryptionFailed("Failed to convert decrypted data to UTF-8 string")
            }
            return plaintext
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Keychain Operations

    /// Stores a value in the macOS Keychain using kSecClassGenericPassword.
    /// - Parameters:
    ///   - key: The account identifier for the Keychain entry.
    ///   - value: The plaintext value to encrypt and store.
    /// - Throws: `EncryptionError.keychainStoreFailed` if the operation fails.
    func storeInKeychain(key: String, value: String) throws {
        // Encrypt the value before storing
        let encryptedData = try encrypt(value)

        // Add the new entry, or update it if it already exists.
        let status = keychainStorage.add(data: encryptedData, service: serviceIdentifier, account: key)
        if status == errSecDuplicateItem {
            let updateStatus = keychainStorage.update(data: encryptedData, service: serviceIdentifier, account: key)
            guard updateStatus == errSecSuccess else {
                throw EncryptionError.keychainStoreFailed(updateStatus)
            }
            cacheKeychainValue(value, for: key)
            return
        }

        guard status == errSecSuccess else {
            throw EncryptionError.keychainStoreFailed(status)
        }
        cacheKeychainValue(value, for: key)
    }

    /// Retrieves and decrypts a value from the macOS Keychain.
    /// - Parameter key: The account identifier for the Keychain entry.
    /// - Returns: The decrypted plaintext value.
    /// - Throws: `EncryptionError.keychainItemNotFound` if the entry doesn't exist,
    ///           `EncryptionError.keychainDataCorrupted` if the data can't be read.
    func retrieveFromKeychain(key: String) throws -> String {
        if let cached = cachedKeychainValue(for: key) {
            return cached
        }

        let result = keychainStorage.data(service: serviceIdentifier, account: key)

        switch result.status {
        case errSecSuccess:
            guard let encryptedData = result.data else {
                throw EncryptionError.keychainDataCorrupted
            }
            let value = try decrypt(encryptedData)
            cacheKeychainValue(value, for: key)
            return value
        case errSecItemNotFound:
            throw EncryptionError.keychainItemNotFound
        default:
            throw EncryptionError.keychainRetrieveFailed(result.status)
        }
    }

    /// Deletes a credential entry from the macOS Keychain.
    /// - Parameter key: The account identifier for the Keychain entry to delete.
    /// - Throws: `EncryptionError.keychainDeleteFailed` if the operation fails.
    func deleteFromKeychain(key: String) throws {
        let status = keychainStorage.delete(service: serviceIdentifier, account: key)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainDeleteFailed(status)
        }
        removeCachedKeychainValue(for: key)
    }

    private func cachedKeychainValue(for key: String) -> String? {
        cacheLock.withLock {
            cachedKeychainValues[key]
        }
    }

    private func cacheKeychainValue(_ value: String, for key: String) {
        cacheLock.withLock {
            cachedKeychainValues[key] = value
        }
    }

    private func removeCachedKeychainValue(for key: String) {
        _ = cacheLock.withLock {
            cachedKeychainValues.removeValue(forKey: key)
        }
    }

    // MARK: - Token Masking

    /// Masks a token for safe display, showing only the last 4 characters.
    /// - Parameter token: The token string to mask.
    /// - Returns: A masked string in the format "****" + last 4 characters.
    ///           If the token has 4 or fewer characters, returns "****" + the full token.
    ///           If the token is empty, returns "****".
    func maskToken(_ token: String) -> String {
        guard !token.isEmpty else {
            return "****"
        }
        let suffix = String(token.suffix(4))
        return "****\(suffix)"
    }
}

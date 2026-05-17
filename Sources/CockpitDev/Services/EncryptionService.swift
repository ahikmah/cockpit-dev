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

// MARK: - EncryptionService

/// Service responsible for AES-256-GCM encryption/decryption and macOS Keychain operations.
///
/// Tokens are encrypted before Keychain storage and masked in any UI display (Property 7).
class EncryptionService {

    // MARK: - Properties

    /// The service identifier used for Keychain entries.
    private let serviceIdentifier: String

    /// The symmetric key used for AES-256-GCM encryption.
    /// In production, this key is derived from or stored in the Keychain itself.
    private var encryptionKey: SymmetricKey

    // MARK: - Initialization

    /// Creates an EncryptionService with the specified service identifier.
    /// - Parameter serviceIdentifier: The Keychain service name (default: "com.cockpitdev.credentials")
    init(serviceIdentifier: String = "com.cockpitdev.credentials") {
        self.serviceIdentifier = serviceIdentifier
        // Attempt to load existing key from Keychain, or generate a new one
        self.encryptionKey = SymmetricKey(size: .bits256)
        self.encryptionKey = loadOrCreateEncryptionKey()
    }

    // MARK: - Encryption Key Management

    /// Loads the encryption key from Keychain or creates and stores a new one.
    private func loadOrCreateEncryptionKey() -> SymmetricKey {
        let keyTag = "\(serviceIdentifier).encryptionKey"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }

        // Generate a new key and store it
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: keyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            // If we can't store the key, use the generated one in memory
            // This is a fallback; in production this should be handled more robustly
        }

        return newKey
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
            let sealedBox = try AES.GCM.seal(plaintextData, using: encryptionKey)
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
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
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

        // First, try to delete any existing entry
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: encryptedData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainStoreFailed(status)
        }
    }

    /// Retrieves and decrypts a value from the macOS Keychain.
    /// - Parameter key: The account identifier for the Keychain entry.
    /// - Returns: The decrypted plaintext value.
    /// - Throws: `EncryptionError.keychainItemNotFound` if the entry doesn't exist,
    ///           `EncryptionError.keychainDataCorrupted` if the data can't be read.
    func retrieveFromKeychain(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let encryptedData = result as? Data else {
                throw EncryptionError.keychainDataCorrupted
            }
            return try decrypt(encryptedData)
        case errSecItemNotFound:
            throw EncryptionError.keychainItemNotFound
        default:
            throw EncryptionError.keychainRetrieveFailed(status)
        }
    }

    /// Deletes a credential entry from the macOS Keychain.
    /// - Parameter key: The account identifier for the Keychain entry to delete.
    /// - Throws: `EncryptionError.keychainDeleteFailed` if the operation fails.
    func deleteFromKeychain(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainDeleteFailed(status)
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

import XCTest
import Security
@testable import CockpitDev

final class EncryptionServiceTests: CockpitDevTestCase {

    private var service: EncryptionService!
    private var keychainStorage: InMemoryKeychainStorage!

    override func setUp() {
        super.setUp()
        // Use a unique service identifier for tests to avoid conflicts with production Keychain
        keychainStorage = InMemoryKeychainStorage()
        service = EncryptionService(
            serviceIdentifier: "com.cockpitdev.tests.\(UUID().uuidString)",
            keychainStorage: keychainStorage
        )
    }

    override func tearDown() {
        service = nil
        keychainStorage = nil
        super.tearDown()
    }

    // MARK: - Encrypt/Decrypt Roundtrip Tests

    func testEncryptDecryptRoundtrip() throws {
        let plaintext = "glpat-xxxxxxxxxxxxxxxxxxxx"
        let encrypted = try service.encrypt(plaintext)
        let decrypted = try service.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptEmptyString() throws {
        let plaintext = ""
        let encrypted = try service.encrypt(plaintext)
        let decrypted = try service.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptLongString() throws {
        let plaintext = String(repeating: "a", count: 10_000)
        let encrypted = try service.encrypt(plaintext)
        let decrypted = try service.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptUnicodeString() throws {
        let plaintext = "🔐 Tökéñ with spëcial chars: 日本語テスト"
        let encrypted = try service.encrypt(plaintext)
        let decrypted = try service.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptProducesDifferentCiphertextEachTime() throws {
        let plaintext = "same-token-value"
        let encrypted1 = try service.encrypt(plaintext)
        let encrypted2 = try service.encrypt(plaintext)
        // Due to random nonce, encrypting the same plaintext should produce different ciphertext
        XCTAssertNotEqual(encrypted1, encrypted2)
    }

    func testDecryptWithCorruptedDataThrows() {
        let corruptedData = Data([0x01, 0x02, 0x03, 0x04])
        XCTAssertThrowsError(try service.decrypt(corruptedData)) { error in
            XCTAssertTrue(error is EncryptionError)
        }
    }

    func testDecryptWithTamperedCiphertextThrows() throws {
        let plaintext = "sensitive-token"
        var encrypted = try service.encrypt(plaintext)
        // Tamper with the ciphertext (modify a byte in the middle)
        if encrypted.count > 20 {
            encrypted[20] ^= 0xFF
        }
        XCTAssertThrowsError(try service.decrypt(encrypted)) { error in
            XCTAssertTrue(error is EncryptionError)
        }
    }

    // MARK: - Token Masking Tests

    func testMaskTokenStandard() {
        let token = "glpat-abcdefgh1234"
        let masked = service.maskToken(token)
        XCTAssertEqual(masked, "****1234")
    }

    func testMaskTokenExactly4Characters() {
        let token = "abcd"
        let masked = service.maskToken(token)
        XCTAssertEqual(masked, "****abcd")
    }

    func testMaskTokenShorterThan4Characters() {
        let token = "ab"
        let masked = service.maskToken(token)
        XCTAssertEqual(masked, "****ab")
    }

    func testMaskTokenSingleCharacter() {
        let token = "x"
        let masked = service.maskToken(token)
        XCTAssertEqual(masked, "****x")
    }

    func testMaskTokenEmpty() {
        let token = ""
        let masked = service.maskToken(token)
        XCTAssertEqual(masked, "****")
    }

    func testMaskTokenLong() {
        let token = "glpat-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        let masked = service.maskToken(token)
        XCTAssertEqual(masked, "****xxxx")
        // Ensure the original token is not visible
        XCTAssertFalse(masked.contains("glpat"))
    }

    // MARK: - Keychain Tests

    func testInitializationDoesNotCreateEncryptionKeyKeychainItem() {
        let serviceIdentifier = "com.cockpitdev.tests.lazy.\(UUID().uuidString)"
        let keyTag = "\(serviceIdentifier).encryptionKey"
        let storage = InMemoryKeychainStorage()

        _ = EncryptionService(serviceIdentifier: serviceIdentifier, keychainStorage: storage)

        XCTAssertEqual(
            storage.data(service: serviceIdentifier, account: keyTag).status,
            errSecItemNotFound
        )
    }

    func testStoreAndRetrieveFromKeychain() throws {
        let key = "test-token-\(UUID().uuidString)"
        let value = "glpat-secret-token-12345"

        try service.storeInKeychain(key: key, value: value)
        let retrieved = try service.retrieveFromKeychain(key: key)
        XCTAssertEqual(retrieved, value)

        // Cleanup
        try service.deleteFromKeychain(key: key)
    }

    func testRetrieveNonExistentKeyThrows() {
        let key = "non-existent-key-\(UUID().uuidString)"
        XCTAssertThrowsError(try service.retrieveFromKeychain(key: key)) { error in
            guard let encError = error as? EncryptionError else {
                XCTFail("Expected EncryptionError")
                return
            }
            if case .keychainItemNotFound = encError {
                // Expected
            } else {
                XCTFail("Expected keychainItemNotFound, got \(encError)")
            }
        }
    }

    func testDeleteFromKeychain() throws {
        let key = "test-delete-\(UUID().uuidString)"
        let value = "token-to-delete"

        try service.storeInKeychain(key: key, value: value)
        try service.deleteFromKeychain(key: key)

        XCTAssertThrowsError(try service.retrieveFromKeychain(key: key)) { error in
            guard let encError = error as? EncryptionError else {
                XCTFail("Expected EncryptionError")
                return
            }
            if case .keychainItemNotFound = encError {
                // Expected
            } else {
                XCTFail("Expected keychainItemNotFound, got \(encError)")
            }
        }
    }

    func testDeleteNonExistentKeyDoesNotThrow() {
        let key = "non-existent-delete-\(UUID().uuidString)"
        XCTAssertNoThrow(try service.deleteFromKeychain(key: key))
    }

    func testStoreOverwritesExistingValue() throws {
        let key = "test-overwrite-\(UUID().uuidString)"
        let value1 = "first-token"
        let value2 = "second-token"

        try service.storeInKeychain(key: key, value: value1)
        try service.storeInKeychain(key: key, value: value2)

        let retrieved = try service.retrieveFromKeychain(key: key)
        XCTAssertEqual(retrieved, value2)

        // Cleanup
        try service.deleteFromKeychain(key: key)
    }

    func testRetrieveFromKeychainUsesProcessCacheAfterFirstRead() throws {
        let serviceIdentifier = "com.cockpitdev.tests.cache.\(UUID().uuidString)"
        let storage = CountingKeychainStorage(base: InMemoryKeychainStorage())
        let key = "gitlab.oauth.clientId"
        let value = "oauth-client-id"

        let writer = EncryptionService(serviceIdentifier: serviceIdentifier, keychainStorage: storage)
        try writer.storeInKeychain(key: key, value: value)
        storage.resetCounts()

        let reader = EncryptionService(serviceIdentifier: serviceIdentifier, keychainStorage: storage)
        XCTAssertEqual(try reader.retrieveFromKeychain(key: key), value)
        XCTAssertEqual(try reader.retrieveFromKeychain(key: key), value)
        XCTAssertEqual(try reader.retrieveFromKeychain(key: key), value)

        XCTAssertEqual(
            storage.dataCallCount(service: serviceIdentifier, account: key),
            1,
            "Credential value should hit Keychain once, then be served from the process cache."
        )
    }

    func testStoreUpdatesKeychainCacheForOverwrittenValue() throws {
        let key = "test-cache-overwrite-\(UUID().uuidString)"

        try service.storeInKeychain(key: key, value: "first")
        XCTAssertEqual(try service.retrieveFromKeychain(key: key), "first")

        try service.storeInKeychain(key: key, value: "second")
        XCTAssertEqual(try service.retrieveFromKeychain(key: key), "second")
    }

}

private final class CountingKeychainStorage: KeychainStorage {
    private let base: KeychainStorage
    private var dataCalls: [String: Int] = [:]
    private let lock = NSLock()

    init(base: KeychainStorage) {
        self.base = base
    }

    func data(service: String, account: String) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            dataCalls[itemKey(service: service, account: account), default: 0] += 1
        }
        return base.data(service: service, account: account)
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        base.add(data: data, service: service, account: account)
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        base.update(data: data, service: service, account: account)
    }

    func delete(service: String, account: String) -> OSStatus {
        base.delete(service: service, account: account)
    }

    func dataCallCount(service: String, account: String) -> Int {
        lock.withLock {
            dataCalls[itemKey(service: service, account: account), default: 0]
        }
    }

    func resetCounts() {
        lock.withLock {
            dataCalls.removeAll()
        }
    }

    private func itemKey(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}

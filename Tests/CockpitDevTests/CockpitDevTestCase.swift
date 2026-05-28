import XCTest
import Darwin

class CockpitDevTestCase: XCTestCase {
    private static var didInstallStderrFilter = false
    private static var originalStderr: Int32 = -1

    override class func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: "com.apple.CoreData.Logging.stderr")
        installCoreDataNoiseFilter()
    }

    private static func installCoreDataNoiseFilter() {
        guard !didInstallStderrFilter else { return }
        didInstallStderrFilter = true

        var pipeFD: [Int32] = [0, 0]
        guard pipe(&pipeFD) == 0 else { return }

        originalStderr = dup(STDERR_FILENO)
        guard originalStderr >= 0 else { return }

        dup2(pipeFD[1], STDERR_FILENO)
        close(pipeFD[1])

        let readFD = pipeFD[0]
        let writeFD = originalStderr

        Thread.detachNewThread {
            var pending = ""
            var buffer = [UInt8](repeating: 0, count: 4096)
            var suppressingCoreDataOptionsBlock = false

            while true {
                let byteCount = Darwin.read(readFD, &buffer, buffer.count)
                guard byteCount > 0 else { break }

                pending += String(decoding: buffer.prefix(byteCount), as: UTF8.self)

                while let newlineIndex = pending.firstIndex(of: "\n") {
                    let nextIndex = pending.index(after: newlineIndex)
                    let line = String(pending[..<nextIndex])
                    pending.removeSubrange(..<nextIndex)

                    if shouldSuppressCoreDataNoise(
                        line,
                        suppressingOptionsBlock: &suppressingCoreDataOptionsBlock
                    ) {
                        continue
                    }

                    if !isKnownCoreDataNoise(line) {
                        write(line, to: writeFD)
                    }
                }
            }

            if !pending.isEmpty, !isKnownCoreDataNoise(pending) {
                write(pending, to: writeFD)
            }
        }
    }

    private static func shouldSuppressCoreDataNoise(
        _ line: String,
        suppressingOptionsBlock: inout Bool
    ) -> Bool {
        if suppressingOptionsBlock {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "}" {
                suppressingOptionsBlock = false
            }
            return true
        }

        if line.contains("CoreData: annotation: options:") {
            suppressingOptionsBlock = true
            return true
        }

        return false
    }

    private static func isKnownCoreDataNoise(_ line: String) -> Bool {
        line.contains("CoreData: error: Failed to create NSXPCConnection") ||
            line.contains("CoreData: XPC: sendMessage: failed") ||
            line.contains("CoreData: XPC: Unable to sendMessage") ||
            line.contains("CoreData: XPC: Unable to connect to server") ||
            line.contains("CoreData: XPC: Unable to load metadata") ||
            line.contains("CoreData: error: addPersistentStoreWithType") ||
            line.contains("CoreData: error: userInfo:") ||
            line.contains("CoreData: error: \tProblem : Unable to send to server") ||
            line.contains("CoreData: error: storeType: NSXPCStore") ||
            line.contains("CoreData: error: configuration: (null)") ||
            line.contains("CoreData: error: URL: file:///Users/ahikmah/Library/Application%20Support/AddressBook/") ||
            line.contains("CoreData: annotation: \tNSReadOnlyPersistentStoreOption") ||
            line.contains("CoreData: annotation: \tNSXPCStoreServerEndpointFactory") ||
            line.contains("CoreData: annotation: \tskipModelCheck") ||
            line.contains("CoreData: annotation: \tNSPersistentHistoryTrackingKey") ||
            line.contains("NSPersistentHistoryTrackingKey =") ||
            line.contains("NSReadOnlyPersistentStoreOption =") ||
            line.contains("NSXPCStoreServerEndpointFactory =") ||
            line.contains("skipModelCheck =") ||
            line.trimmingCharacters(in: .whitespacesAndNewlines) == "}"
    }

    private static func write(_ text: String, to fileDescriptor: Int32) {
        let bytes = Array(text.utf8)
        bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = Darwin.write(fileDescriptor, baseAddress, bytes.count)
        }
    }
}

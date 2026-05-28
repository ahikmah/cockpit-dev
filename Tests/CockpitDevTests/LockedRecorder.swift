import Foundation

/// Thread-safe recorder for progress callbacks that are invoked from @Sendable closures.
final class LockedRecorder<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return elements.isEmpty
    }

    func append(_ element: Element) {
        lock.lock()
        elements.append(element)
        lock.unlock()
    }
}

import Foundation

/// Complete content captured for one OpenSpec change at a point in time.
struct OpenSpecDocumentSnapshot: Codable, Equatable {

    struct SpecDocument: Codable, Equatable, Identifiable {
        var id: String { path }

        let path: String
        let content: String
    }

    let proposal: String?
    let design: String?
    let tasks: String?
    let specs: [SpecDocument]

    var taskProgress: OpenSpecTaskProgress? {
        guard let tasks else {
            return nil
        }

        var completed = 0
        var total = 0

        for line in tasks.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") else {
                continue
            }

            let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
            guard markerIndex < trimmed.endIndex else {
                continue
            }

            switch trimmed[markerIndex] {
            case "x", "X":
                completed += 1
                total += 1
            case " ":
                total += 1
            default:
                continue
            }
        }

        guard total > 0 else {
            return nil
        }

        return OpenSpecTaskProgress(completed: completed, total: total)
    }

    var hasContent: Bool {
        proposal != nil || design != nil || tasks != nil || !specs.isEmpty
    }

    func encodedContent() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let content = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: [], debugDescription: "Snapshot is not UTF-8.")
            )
        }
        return content
    }

    static func decode(_ content: String, legacyPhase: SpecPhase) -> OpenSpecDocumentSnapshot {
        if let data = content.data(using: .utf8),
           let snapshot = try? JSONDecoder().decode(OpenSpecDocumentSnapshot.self, from: data) {
            return snapshot
        }

        switch legacyPhase {
        case .proposal:
            return OpenSpecDocumentSnapshot(proposal: content, design: nil, tasks: nil, specs: [])
        case .design:
            return OpenSpecDocumentSnapshot(proposal: nil, design: content, tasks: nil, specs: [])
        case .tasks:
            return OpenSpecDocumentSnapshot(proposal: nil, design: nil, tasks: content, specs: [])
        }
    }
}

struct OpenSpecTaskProgress: Equatable {
    let completed: Int
    let total: Int

    var percentage: Int {
        Int((Double(completed) / Double(total) * 100).rounded())
    }

    var ratio: Double {
        Double(completed) / Double(total)
    }

    var displayText: String {
        "\(percentage)%"
    }
}

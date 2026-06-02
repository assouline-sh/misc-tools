import Foundation

struct PendingReminder: Codable {
    let id: UUID
    let messageText: String
    let senderName: String?
    let sourceApp: String?
    let createdAt: Date
    let intervalMinutes: Int

    func write() throws {
        let url = AppConstants.pendingRemindersURL
            .appendingPathComponent("\(id.uuidString).json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func loadAll() -> [PendingReminder] {
        let url = AppConstants.pendingRemindersURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }

        return files.compactMap { fileURL in
            guard fileURL.pathExtension == "json",
                  let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? JSONDecoder().decode(PendingReminder.self, from: data)
        }
    }

    static func delete(id: UUID) {
        let url = AppConstants.pendingRemindersURL
            .appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}

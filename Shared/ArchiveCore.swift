import Foundation
import CryptoKit

struct ArchiveOffer: Codable, Equatable {
    let recordingID: UUID
    let deviceID: UUID
    let deviceName: String
    let category: String
    let date: Date
    let day: String
    let duration: Double
    let byteCount: Int64
    let audioHash: String
    let transcript: String?
    var key: String { deviceID.uuidString + "_" + recordingID.uuidString }
    var textHash: String? { transcript.map { Self.digest(Data($0.utf8)) } }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha = SHA256()
        while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty { sha.update(data: data) }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func validate() throws {
        guard ["日常记录", "idea"].contains(category),
              day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              audioHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              byteCount > 0, byteCount <= 4 * 1024 * 1024 * 1024,
              duration.isFinite, duration >= 0,
              date.timeIntervalSince1970.isFinite,
              deviceName.utf8.count <= 256,
              (transcript?.utf8.count ?? 0) <= 4 * 1024 * 1024 else { throw ArchiveFailure.invalid }
    }
}

enum ArchiveFailure: LocalizedError {
    case invalid, integrity, interrupted, duplicateChanged, protocolError, unpaired
    var errorDescription: String? {
        switch self {
        case .invalid: return "文件信息无效或超过传输限制。"
        case .integrity: return "文件校验未通过，原文件保留，下次连接会重试。"
        case .interrupted: return "连接已中断，重新连接后会继续归档。"
        case .duplicateChanged: return "同一录音的音频发生变化，已保留 Mac 上的原归档。"
        case .protocolError: return "两端传输版本不一致，请更新 Glimpse。"
        case .unpaired: return "请重新扫描 Mac 的配对二维码。"
        }
    }
}

struct ArchiveReceipt: Codable {
    var offer: ArchiveOffer
    var archivedAt: Date
    var importedTextHash: String?
}

/// Serialized by its owning receiver. Stages outside the library and commits by an
/// atomic directory rename. No acknowledgement is sent until the receipt is durable.
final class ArchiveRepository {
    let root: URL
    private let fm = FileManager.default
    private(set) var receipts: [String: (URL, ArchiveReceipt)] = [:]
    private var staging: URL?
    private var handle: FileHandle?
    private var pending: ArchiveOffer?
    private var bytes: Int64 = 0
    private var sha = SHA256()

    init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }
    func reload() {
        receipts = [:]
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in iterator where url.lastPathComponent == "archive.json" {
            if let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(ArchiveReceipt.self, from: data) {
                if receipts[receipt.offer.key]?.1.archivedAt ?? .distantPast < receipt.archivedAt {
                    receipts[receipt.offer.key] = (url.deletingLastPathComponent(), receipt)
                }
            }
        }
    }
    /// Returns true only when the audio itself is missing. Existing audio is rehashed
    /// before it counts as an archive, so a damaged destination cannot produce an ACK.
    func needsAudio(_ offer: ArchiveOffer) throws -> Bool {
        try offer.validate()
        if let (dir, receipt) = receipts[offer.key] {
            guard receipt.offer.audioHash == offer.audioHash else { throw ArchiveFailure.duplicateChanged }
            let audio = dir.appendingPathComponent("recording.m4a")
            if fm.fileExists(atPath: audio.path), try ArchiveOffer.fileHash(audio) == offer.audioHash { return false }
        }
        return true
    }
    func begin(_ offer: ArchiveOffer) throws {
        abort()
        try offer.validate()
        let parent = root.appendingPathComponent(".incoming", isDirectory: true)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let dir = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        staging = dir
        pending = offer
        let file = dir.appendingPathComponent("recording.m4a")
        guard fm.createFile(atPath: file.path, contents: nil) else { abort(); throw ArchiveFailure.invalid }
        handle = try FileHandle(forWritingTo: file)
        sha = SHA256(); bytes = 0
    }
    func append(_ data: Data) throws {
        guard let pending, let handle, !data.isEmpty, data.count <= 256 * 1024,
              bytes + Int64(data.count) <= pending.byteCount else { throw ArchiveFailure.invalid }
        try handle.write(contentsOf: data)
        sha.update(data: data); bytes += Int64(data.count)
    }
    @discardableResult
    func finish() throws -> URL {
        guard let offer = pending, let staging else { throw ArchiveFailure.invalid }
        defer { abort() }
        try handle?.synchronize(); try handle?.close(); handle = nil
        let digest = sha.finalize().map { String(format: "%02x", $0) }.joined()
        guard bytes == offer.byteCount, digest == offer.audioHash else { throw ArchiveFailure.integrity }
        var receipt = ArchiveReceipt(offer: offer, archivedAt: Date(), importedTextHash: nil)
        try writeText(offer, directory: staging, receipt: &receipt)
        try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent("archive.json"), options: .atomic)
        let parent = root.appendingPathComponent(offer.day).appendingPathComponent(offer.category)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var destination = parent.appendingPathComponent(offer.key)
        // Damaged old archives are retained, rather than silently overwritten.
        if fm.fileExists(atPath: destination.path) { destination = parent.appendingPathComponent(offer.key + "_" + UUID().uuidString) }
        try fm.moveItem(at: staging, to: destination)
        receipts[offer.key] = (destination, receipt)
        return destination.appendingPathComponent("recording.m4a")
    }
    func updateText(_ offer: ArchiveOffer) throws {
        guard let (dir, stored) = receipts[offer.key] else { throw ArchiveFailure.invalid }
        var receipt = stored
        // Archive category is the category at first import; changes on either device
        // never move/delete a previously archived Mac file.
        try writeText(offer, directory: dir, receipt: &receipt)
        receipt.offer = offer
        try JSONEncoder().encode(receipt).write(to: dir.appendingPathComponent("archive.json"), options: .atomic)
        receipts[offer.key] = (dir, receipt)
    }
    private func writeText(_ offer: ArchiveOffer, directory: URL, receipt: inout ArchiveReceipt) throws {
        guard let text = offer.transcript else { return }
        let url = directory.appendingPathComponent("recording.txt")
        let state = directory.appendingPathComponent("recording.transcript.json")
        let exists = fm.fileExists(atPath: url.path)
        let oldHash = exists ? try ArchiveOffer.digest(Data(contentsOf: url)) : nil
        if exists, oldHash != receipt.importedTextHash, oldHash != offer.textHash {
            // A local edit wins. Keep the incoming phone version alongside it.
            try text.write(to: directory.appendingPathComponent("recording.phone.txt"), atomically: true, encoding: .utf8)
            return
        }
        if oldHash != offer.textHash || !fm.fileExists(atPath: state.path) {
            try text.write(to: url, atomically: true, encoding: .utf8)
            // Same schema as the shared transcription store. No API keys are transferred.
            struct State: Encodable { let status = "complete"; let text: String; let detail = "从 iPhone 归档 · TXT 已保存"; let language = "zh-CN"; let updatedAt = Date() }
            try JSONEncoder().encode(State(text: text)).write(to: state, options: .atomic)
        }
        receipt.importedTextHash = offer.textHash
    }
    func abort() {
        try? handle?.close(); handle = nil
        if let staging { try? fm.removeItem(at: staging) }
        staging = nil; pending = nil; bytes = 0
    }
    deinit { abort() }
}

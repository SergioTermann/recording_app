import Foundation

enum RecordingFolder: String, CaseIterable, Identifiable {
    case daily = "日常记录"
    case idea = "idea"
    var id: String { rawValue }
    var icon: String { self == .daily ? "folder" : "lightbulb" }
}

extension Recording {
    var folder: RecordingFolder {
        url.pathComponents.reversed().compactMap { RecordingFolder(rawValue: $0) }.first ?? .daily
    }
}

struct RecordingFiles {
    let root: URL
    private let files = FileManager.default

    func directory(for folder: RecordingFolder) -> URL {
        root.appendingPathComponent(folder.rawValue, isDirectory: true)
    }

    func prepare() throws {
        for folder in RecordingFolder.allCases {
            try files.createDirectory(at: directory(for: folder), withIntermediateDirectories: true)
        }
    }

    func audioURLs() throws -> [URL] {
        // Keep unmigrated legacy audio visible if a move fails (e.g. full storage).
        try ([root] + RecordingFolder.allCases.map(directory)).flatMap { folder in
            try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "m4a" }
        }
    }

    func migrateLegacy() throws {
        try prepare()
        for url in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) where url.pathExtension == "m4a" {
            _ = try move(url, to: .daily)
        }
    }

    @discardableResult
    func move(_ audio: URL, to folder: RecordingFolder) throws -> URL {
        let destinationDirectory = directory(for: folder)
        if audio.deletingLastPathComponent().standardizedFileURL == destinationDirectory.standardizedFileURL { return audio }
        try files.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let extensions = ["txt", "transcript.json", "md", "markdown-draft.json", "m4a"]
        var destination = destinationDirectory.appendingPathComponent(audio.lastPathComponent)
        // Never replace another recording or one of its text files.
        while extensions.contains(where: { files.fileExists(atPath: destination.deletingPathExtension().appendingPathExtension($0).path) }) {
            destination = destinationDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        }
        var copied: [(URL, URL)] = []
        do {
            // Keep original sidecars until the audio move commits. If the process
            // exits midway, either the source or destination still has a full set.
            for ext in ["txt", "transcript.json", "md", "markdown-draft.json"] {
                let source = audio.deletingPathExtension().appendingPathExtension(ext)
                let target = destination.deletingPathExtension().appendingPathExtension(ext)
                if files.fileExists(atPath: source.path) {
                    try files.copyItem(at: source, to: target)
                    copied.append((source, target))
                }
            }
            try files.moveItem(at: audio, to: destination)
            for (source, _) in copied { try? files.removeItem(at: source) }
            return destination
        } catch {
            for (_, target) in copied { try? files.removeItem(at: target) }
            throw error
        }
    }
}

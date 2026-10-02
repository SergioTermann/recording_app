import AVFoundation
import Speech
import SwiftUI

struct Transcript: Codable, Equatable {
    enum Status: String, Codable { case queued, working, complete, failed }
    var status: Status
    var text = ""
    var detail = ""
    var language = "zh-CN"
    var updatedAt = Date()
}

extension Recording {
    var transcriptURL: URL { url.deletingPathExtension().appendingPathExtension("txt") }
    var transcriptStateURL: URL { url.deletingPathExtension().appendingPathExtension("transcript.json") }
}

@MainActor
protocol SpeechRecognizing {
    func transcribe(url: URL, language: String, update: @escaping @MainActor (String, String) -> Void) async throws -> String
}

@MainActor
final class TranscriptionStore: ObservableObject {
    @Published private(set) var items: [URL: Transcript] = [:]
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: "automaticTranscription") }
    }
    private let defaults: UserDefaults
    private let engine: any SpeechRecognizing
    private var recordings: [Recording] = []
    private var worker: Task<Void, Never>?
    private var generation = UUID()
    private var canRun = false

    init(engine: (any SpeechRecognizing)? = nil, defaults: UserDefaults = .standard) {
        self.engine = engine ?? AppleSpeechEngine()
        self.defaults = defaults
        automatic = defaults.object(forKey: "automaticTranscription") as? Bool ?? true
    }

    func reload(_ recordings: [Recording]) {
        self.recordings = recordings
        let urls = Set(recordings.map(\.url))
        items = items.filter { urls.contains($0.key) }
        for recording in recordings {
            if let current = items[recording.url], current.status == .working || current.status == .queued { continue }
            guard let data = try? Data(contentsOf: recording.transcriptStateURL),
                  var item = try? JSONDecoder().decode(Transcript.self, from: data) else { continue }
            if let current = items[recording.url], current.updatedAt >= item.updatedAt { continue }
            if item.status == .working { item.status = .queued; item.detail = "等待继续识别" }
            items[recording.url] = item
        }
        runNext()
    }

    func setCanRun(_ value: Bool) {
        canRun = value
        if value { runNext() } else { pause() }
    }

    func enqueue(_ recording: Recording) {
        guard items[recording.url]?.status != .working,
              items[recording.url]?.status != .queued else { return }
        if !recordings.contains(where: { $0.url == recording.url }) { recordings.append(recording) }
        save(Transcript(status: .queued, detail: "等待转文字"), for: recording)
        runNext()
    }

    func saveEditedText(_ text: String, for recording: Recording) throws {
        // Manual corrections also work before recognition completes. Cancel this
        // recording's worker first so a late result cannot overwrite the edit.
        let wasWorking = items[recording.url]?.status == .working
        if wasWorking { pause() }
        try text.write(to: recording.transcriptURL, atomically: true, encoding: .utf8)
        let item = Transcript(status: .complete, text: text, detail: "文字已保存 · TXT 已生成")
        try persist(item, for: recording)
        items[recording.url] = item
        runNext()
    }

    func remove(_ recording: Recording) {
        if items[recording.url]?.status == .working { pause() }
        recordings.removeAll { $0.url == recording.url }
        items.removeValue(forKey: recording.url)
        for url in [recording.transcriptURL, recording.transcriptStateURL] {
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
        }
        runNext()
    }

    private func pause() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        for recording in recordings where items[recording.url]?.status == .working {
            var item = items[recording.url]!
            item.status = .queued
            item.detail = "回到Glimpse后继续识别"
            save(item, for: recording)
        }
    }

    private func runNext() {
        guard canRun, worker == nil,
              let recording = recordings.first(where: { items[$0.url]?.status == .queued }) else { return }
        let token = UUID()
        generation = token
        var item = items[recording.url]!
        item.status = .working
        item.text = ""
        item.detail = "正在准备中文识别…"
        save(item, for: recording)
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token { self.worker = nil; self.runNext() }
            }
            do {
                let text = try await self.engine.transcribe(url: recording.url, language: item.language) { [weak self] text, detail in
                    guard let self, self.generation == token else { return }
                    self.items[recording.url] = Transcript(status: .working, text: text, detail: detail)
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { throw SpeechFailure.noSpeech }
                // A completed status is published only after the durable UTF-8 export exists.
                try cleaned.write(to: recording.transcriptURL, atomically: true, encoding: .utf8)
                try self.persist(Transcript(status: .complete, text: cleaned, detail: "文字已保存 · TXT 已生成"), for: recording)
                self.items[recording.url] = Transcript(status: .complete, text: cleaned, detail: "文字已保存 · TXT 已生成")
            } catch {
                guard self.generation == token else { return }
                self.save(Transcript(status: .failed, detail: "转文字未完成：\(error.localizedDescription)"), for: recording)
            }
        }
    }

    private func persist(_ item: Transcript, for recording: Recording) throws {
        try JSONEncoder().encode(item).write(to: recording.transcriptStateURL, options: .atomic)
    }

    private func save(_ item: Transcript, for recording: Recording) {
        do { try persist(item, for: recording); items[recording.url] = item }
        catch { items[recording.url] = Transcript(status: .failed, detail: "文字状态保存失败：\(error.localizedDescription)") }
    }
}

enum SpeechFailure: LocalizedError {
    case unavailable, permission, noSpeech, timeout
    var errorDescription: String? {
        switch self {
        case .unavailable: return "本机中文识别暂不可用，请联网下载系统语言资源后重试。"
        case .permission: return "请在「设置 → 隐私与安全性 → 语音识别」中允许Glimpse。"
        case .noSpeech: return "没有识别到清晰语音。原录音仍然保留，可以重新尝试。"
        case .timeout: return "识别超时，请回到 App 后重试。"
        }
    }
}

@MainActor
final class AppleSpeechEngine: SpeechRecognizing {
    func transcribe(url: URL, language: String, update: @escaping @MainActor (String, String) -> Void) async throws -> String {
        if #available(iOS 26, macOS 26, *), SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) {
            return try await modern(url: url, locale: locale, update: update)
        }
        return try await legacy(url: url, language: language, update: update)
    }

    @available(iOS 26, macOS 26, *)
    private func modern(url: URL, locale: Locale, update: @escaping @MainActor (String, String) -> Void) async throws -> String {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        try Task.checkCancellation()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            update("", "首次使用：正在下载中文模型，请保持联网…")
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        update("", "正在设备上识别，请保持Glimpse在前台…")
        let analyzer = SpeechAnalyzer(modules: [module])
        let results = Task { @MainActor in
            var parts: [String] = []
            for try await result in module.results {
                try Task.checkCancellation()
                parts.append(String(result.text.characters))
                update(parts.joined(separator: "\n"), "正在设备上识别…")
            }
            return parts.joined(separator: "\n")
        }
        return try await withTaskCancellationHandler {
            do {
                let audio = try AVAudioFile(forReading: url)
                try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
                return try await results.value
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            results.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func legacy(url: URL, language: String, update: @escaping @MainActor (String, String) -> Void) async throws -> String {
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard permission == .authorized else { throw SpeechFailure.permission }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw SpeechFailure.unavailable }
        let input = try AVAudioFile(forReading: url)
        let segmentFrames = AVAudioFrameCount(input.processingFormat.sampleRate * 45)
        let count = max(1, Int(ceil(Double(input.length) / Double(segmentFrames))))
        var parts: [String] = []
        for index in 0..<count {
            try Task.checkCancellation()
            update(parts.joined(separator: "\n"), "正在设备上识别，第 \(index + 1)/\(count) 段…")
            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: segmentFrames) else { throw SpeechFailure.unavailable }
            try input.read(into: buffer, frameCount: segmentFrames)
            guard buffer.frameLength > 0 else { break }
            let chunk = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: chunk) }
            do {
                let file = try AVAudioFile(forWriting: chunk, settings: input.processingFormat.settings)
                try file.write(from: buffer)
            }
            let job = LegacySpeechJob()
            let text = try await job.run(url: chunk, recognizer: recognizer)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: "\n")
    }
}

@MainActor
private final class LegacySpeechJob {
    private var recognition: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?

    func run(url: URL, recognizer: SFSpeechRecognizer) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.requiresOnDeviceRecognition = true
                request.shouldReportPartialResults = false
                request.addsPunctuation = true
                recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor in
                        if let result, result.isFinal { self?.finish(.success(result.bestTranscription.formattedString)) }
                        else if let error { self?.finish(.failure(error)) }
                    }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)); self?.finish(.failure(SpeechFailure.timeout)) }
                    catch { }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        recognition?.cancel()
        recognition = nil
        continuation.resume(with: result)
    }
}

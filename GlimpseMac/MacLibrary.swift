import AppKit
import AVFoundation
import SwiftUI
import Combine

@MainActor
final class MacLibrary: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    let root: URL
    let transcripts = TranscriptionStore()
    let summaries: DailySummaryStore
    @Published var recordings: [Recording] = []
    @Published var selectedFolder: RecordingFolder = .daily
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    @Published var playing: URL?
    @Published var error: String?
    @Published var starting = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var maintenance: Timer?
    private var subscription: AnyCancellable?
    private var summarySubscription: AnyCancellable?
    private var importedURLs = Set<URL>()
    private var importedDates: [URL:Date] = [:]
    private var nativeRoot: URL { root.appendingPathComponent("Mac 录音") }
    var archiveRoot: URL { root.appendingPathComponent("手机归档") }

    override init() {
        #if DEBUG
        if let testRoot = ProcessInfo.processInfo.environment["GLIMPSE_TEST_ROOT"] ?? (Bundle.main.bundleIdentifier?.hasSuffix(".uitest") == true ? "/tmp/glimpse-mac-ui-test" : nil) {
            root = URL(fileURLWithPath: testRoot, isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Glimpse", isDirectory: true)
        }
        #else
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Glimpse", isDirectory: true)
        #endif
        summaries = DailySummaryStore(directory: root.appendingPathComponent("每日总结"))
        super.init()
        do {
            try RecordingFiles(root: nativeRoot).prepare()
            try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        } catch { self.error = error.localizedDescription }
        refresh()
        subscription = transcripts.$items.receive(on: DispatchQueue.main).sink { [weak self] items in
            guard let self else { return }; self.objectWillChange.send(); self.summaries.update(recordings: self.recordings, transcripts: items)
        }
        summarySubscription = summaries.$documents.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }
        transcripts.setCanRun(true); summaries.setCanRun(true)
        maintenance = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.summaries.update(recordings: self.recordings, transcripts: self.transcripts.items); self.summaries.rebuild() }
        }
    }
    var importedCount: Int { importedURLs.count }
    func isImported(_ r: Recording) -> Bool { importedURLs.contains(r.url) }
    func refresh() {
        do {
            var files = try RecordingFiles(root: nativeRoot).audioURLs()
            importedURLs = []; importedDates = [:]
            let repo = try ArchiveRepository(root: archiveRoot)
            for (directory, receipt) in repo.receipts.values {
                let audio = directory.appendingPathComponent("recording.m4a")
                if FileManager.default.fileExists(atPath: audio.path) {
                    files.append(audio); importedURLs.insert(audio); importedDates[audio] = receipt.offer.date
                }
            }
            recordings = files.filter { $0 != recorder?.url }.map { url in
                Recording(url: url, date: importedDates[url] ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(), duration: (try? AVAudioPlayer(contentsOf: url).duration) ?? 0)
            }.sorted { $0.date > $1.date }
            transcripts.reload(recordings)
            if transcripts.automatic {
                for recording in recordings where transcripts.items[recording.url] == nil { transcripts.enqueue(recording) }
            }
            summaries.update(recordings: recordings, transcripts: transcripts.items)
        } catch { self.error = "无法读取档案：\(error.localizedDescription)" }
    }
    func start() async {
        guard !isRecording, !starting else { return }; starting = true; defer { starting = false }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { error = "请在系统设置 → 隐私与安全性 → 麦克风中允许 Glimpse。"; return }
        stopPlaying(); transcripts.setCanRun(false)
        var output: URL?
        do {
            let folder = RecordingFiles(root: nativeRoot); try folder.prepare()
            let url = folder.directory(for: selectedFolder).appendingPathComponent(UUID().uuidString+".m4a"); output = url
            let audio = try AVAudioRecorder(url: url, settings: [AVFormatIDKey:kAudioFormatMPEG4AAC, AVSampleRateKey:44100, AVNumberOfChannelsKey:1, AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
            audio.delegate = self; audio.isMeteringEnabled = true
            guard audio.prepareToRecord(), audio.record() else { throw ArchiveFailure.invalid }
            recorder = audio; isRecording = true; elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let audio = self.recorder else { return }
                    self.elapsed = audio.currentTime; audio.updateMeters()
                    self.level = max(0,min(1,(audio.averagePower(forChannel: 0)+55)/55))
                }
            }
        } catch {
            if let output { try? FileManager.default.removeItem(at: output) }
            self.error = "无法开始录音：\(error.localizedDescription)"; transcripts.setCanRun(true)
        }
    }
    func stop() {
        guard let audio = recorder else { return }
        let url = audio.url; elapsed = audio.currentTime
        audio.delegate = nil; audio.stop(); recorder = nil
        timer?.invalidate(); timer = nil; isRecording = false; level = 0
        refresh(); transcripts.setCanRun(true)
        if transcripts.automatic, let recording = recordings.first(where: { $0.url == url }) { transcripts.enqueue(recording) }
    }
    func play(_ r: Recording) {
        if playing == r.url { stopPlaying(); return }; stopPlaying()
        do {
            let audio = try AVAudioPlayer(contentsOf: r.url); audio.delegate = self
            guard audio.play() else { throw ArchiveFailure.invalid }; player = audio; playing = r.url
        } catch { self.error = error.localizedDescription }
    }
    func stopPlaying() { player?.stop(); player = nil; playing = nil }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func move(_ recording: Recording, to folder: RecordingFolder) {
        guard !isImported(recording) else { return }
        do { _ = try RecordingFiles(root: nativeRoot).move(recording.url, to: folder); refresh() }
        catch { self.error = error.localizedDescription }
    }
    func trash(_ recording: Recording) {
        stopPlaying()
        do {
            let file = isImported(recording) ? recording.url.deletingLastPathComponent() : recording.url
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            if !isImported(recording) {
                for ext in ["txt", "transcript.json", "md", "markdown-draft.json"] {
                    let sidecar = recording.url.deletingPathExtension().appendingPathExtension(ext)
                    if FileManager.default.fileExists(atPath: sidecar.path) { try FileManager.default.trashItem(at: sidecar, resultingItemURL: nil) }
                }
            }
            transcripts.remove(recording); refresh()
        } catch { self.error = error.localizedDescription }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.stopPlaying() } }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.stop(); if !flag { self.error = "录音被中断，已保留录下的内容。" } }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.stop(); self.error = "录音写入失败，请检查存储空间。" }
    }
}

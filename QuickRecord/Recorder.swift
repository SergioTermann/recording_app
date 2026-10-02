import AVFoundation
import SwiftUI
import UIKit
import Combine

@MainActor
final class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = Recorder()
    let transcripts = TranscriptionStore()
    let dailySummaries = DailySummaryStore()
    private var summarySubscription: AnyCancellable?
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var playingURL: URL?
    @Published private(set) var microphoneName = "iPhone 内置麦克风"
    @Published var message: String?
    @Published var needsSettings = false
    @Published var selectedFolder = RecordingFolder(rawValue: UserDefaults.standard.string(forKey: "recordingFolder") ?? "") ?? .daily {
        didSet { UserDefaults.standard.set(selectedFolder.rawValue, forKey: "recordingFolder") }
    }
    var visibleRecordings: [Recording] { recordings.filter { $0.folder == selectedFolder } }

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var pendingStart = false
    private var observers: [NSObjectProtocol] = []
    private let session = AVAudioSession.sharedInstance()

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }
    private var storage: RecordingFiles { RecordingFiles(root: directory) }

    override private init() {
        super.init()
        do { try storage.migrateLegacy() }
        catch { message = "部分旧录音暂时无法归入文件夹，原文件仍保留：\(error.localizedDescription)" }
        refresh()
        summarySubscription = transcripts.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }
                self.dailySummaries.update(recordings: self.recordings, transcripts: items)
            }
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildDailySummaries() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                guard let self else { return }
                let wasRecording = self.isRecording
                self.stop()
                self.stopPlayback()
                if wasRecording { self.message = "录音被来电或其他音频打断，已保存录下的内容。" }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                do {
                    try PhoneMicrophone.enforce(on: self.session)
                    self.microphoneName = "iPhone 内置麦克风"
                } catch {
                    self.stop()
                    self.message = "录音已停止并保存：无法保持使用 iPhone 内置麦克风，请检查音频连接后重试。"
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stop()
                self.stopPlayback()
                self.message = "系统音频服务已重启，请重新开始录音。"
            }
        })
    }

    func requestStart() {
        // Repeated shortcut triggers never stop or replace an ongoing recording.
        guard !isRecording, !isStarting else { return }
        pendingStart = true
        startIfRequested()
    }

    func startIfRequested() {
        guard pendingStart, UIApplication.shared.applicationState == .active else { return }
        pendingStart = false
        Task { await start() }
    }

    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false; updateTranscriptionActivity() }
        needsSettings = false
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            needsSettings = true
            message = "请在系统设置中允许Glimpse使用麦克风，然后重新开始录音。"
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            pendingStart = true
            return
        }
        stopPlayback()
        transcripts.setCanRun(false)
        var output: URL?
        do {
            try storage.prepare()
            // Do not enable Bluetooth HFP inputs. Wired headset inputs are explicitly
            // overridden below, since omitting Bluetooth alone does not exclude them.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try PhoneMicrophone.enforce(on: session)
            let url = storage.directory(for: selectedFolder).appendingPathComponent("\(UUID().uuidString).m4a")
            output = url
            let audio = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            audio.delegate = self
            audio.isMeteringEnabled = true
            guard audio.prepareToRecord() else { throw RecordingError.cannotStart }
            // Keep the file writable after the user locks the screen during recording.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            guard audio.record() else { throw RecordingError.cannotStart }
            do { try PhoneMicrophone.enforce(on: session) }
            catch { audio.stop(); throw error }
            recorder = audio
            microphoneName = "iPhone 内置麦克风"
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let audio = self.recorder else { return }
                    self.elapsed = audio.currentTime
                    audio.updateMeters()
                    self.level = max(0, min(1, (audio.averagePower(forChannel: 0) + 55) / 55))
                }
            }
        } catch {
            if let output { try? FileManager.default.removeItem(at: output) }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            message = "无法开始录音：\(error.localizedDescription)"
            updateTranscriptionActivity()
        }
    }

    func stop() {
        guard isRecording else { return }
        elapsed = recorder?.currentTime ?? elapsed
        var savedURL = recorder?.url
        isRecording = false
        timer?.invalidate()
        timer = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        level = 0
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let original = savedURL {
            do { savedURL = try storage.move(original, to: selectedFolder) }
            catch { message = "录音已保存，但无法放入所选文件夹，保留在原文件夹：\(error.localizedDescription)" }
        }
        refresh()
        if transcripts.automatic, let savedURL, let recording = recordings.first(where: { $0.url == savedURL }) {
            transcripts.enqueue(recording)
        }
        updateTranscriptionActivity()
    }

    func updateTranscriptionActivity() {
        let active = UIApplication.shared.applicationState == .active && !isRecording && !isStarting
        transcripts.setCanRun(active)
        dailySummaries.setCanRun(active)
    }

    @discardableResult
    func rebuildDailySummaries() -> Bool {
        guard !isRecording, !isStarting else { return false }
        refresh()
        if transcripts.automatic, UIApplication.shared.applicationState == .active {
            let today = DailySummaryBuilder(timeZone: dailySummaries.timeZone).calendar.startOfDay(for: Date())
            for recording in recordings where recording.date < today && transcripts.items[recording.url] == nil {
                transcripts.enqueue(recording)
            }
        }
        dailySummaries.update(recordings: recordings, transcripts: transcripts.items)
        return dailySummaries.rebuild()
    }

    func refresh() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            recordings = try storage.audioURLs().map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
                return Recording(url: url, date: date, duration: duration)
            }.sorted { $0.date > $1.date }
            transcripts.reload(recordings)
            dailySummaries.update(recordings: recordings, transcripts: transcripts.items)
        } catch {
            message = "读取录音失败：\(error.localizedDescription)"
        }
    }

    func play(_ recording: Recording) {
        guard !isRecording, !isStarting else { return }
        if playingURL == recording.url { stopPlayback(); return }
        stopPlayback()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: recording.url)
            audio.delegate = self
            guard audio.play() else { throw RecordingError.cannotPlay }
            player = audio
            playingURL = recording.url
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            message = "无法播放：\(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        player?.delegate = nil
        player?.stop()
        player = nil
        playingURL = nil
        if !isRecording { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func delete(_ recording: Recording) {
        if playingURL == recording.url { stopPlayback() }
        do {
            try FileManager.default.removeItem(at: recording.url)
            transcripts.remove(recording)
            refresh()
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }

    func move(_ recording: Recording, to folder: RecordingFolder) {
        if playingURL == recording.url { stopPlayback() }
        transcripts.setCanRun(false)
        defer { updateTranscriptionActivity() }
        do {
            try storage.move(recording.url, to: folder)
            refresh()
        } catch { message = "移动失败，录音仍保留：\(error.localizedDescription)" }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlayback() }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
            if !flag { self.message = "录音未正常结束，请检查保存的文件。" }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.stop()
            self.message = "录音写入失败，请检查设备剩余空间和已保存的文件。"
        }
    }
}

enum RecordingError: LocalizedError {
    case cannotStart, cannotPlay, phoneMicrophoneUnavailable
    var errorDescription: String? {
        switch self {
        case .cannotStart: return "麦克风暂不可用，请稍后重试。"
        case .cannotPlay: return "录音文件无法播放。"
        case .phoneMicrophoneUnavailable: return "无法使用 iPhone 内置麦克风，录音未开始。请检查音频连接后重试。"
        }
    }
}

enum PhoneMicrophone {
    static func enforce(on session: AVAudioSession) throws {
        guard let microphone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            throw RecordingError.phoneMicrophoneUnavailable
        }
        if session.preferredInput?.uid != microphone.uid || !isBuiltIn(session.currentRoute.inputs) {
            try session.setPreferredInput(microphone)
        }
        guard isBuiltIn(session.currentRoute.inputs) else { throw RecordingError.phoneMicrophoneUnavailable }
    }

    private static func isBuiltIn(_ inputs: [AVAudioSessionPortDescription]) -> Bool {
        !inputs.isEmpty && inputs.allSatisfy { $0.portType == .builtInMic }
    }
}


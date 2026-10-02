import XCTest
import AVFoundation
@testable import QuickRecord

@MainActor
private final class StubSpeech: SpeechRecognizing {
    var result = "今天下午三点开会。\n请带上电脑。"
    var shouldFail = false
    var delay: Duration = .zero
    func transcribe(url: URL, language: String, update: @escaping @MainActor (String, String) -> Void) async throws -> String {
        try await Task.sleep(for: delay)
        if shouldFail { throw SpeechFailure.noSpeech }
        update(result, "正在识别")
        return result
    }
}

final class TranscriptionTests: XCTestCase {
    func testFolderMigrationAndMoveKeepAudioAndTextTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = RecordingFiles(root: root)
        try files.prepare()
        let audio = root.appendingPathComponent("legacy.m4a")
        for ext in ["m4a", "txt", "transcript.json", "md", "markdown-draft.json"] {
            try Data("内容-\(ext)".utf8).write(to: audio.deletingPathExtension().appendingPathExtension(ext))
        }
        try files.migrateLegacy()
        try files.migrateLegacy() // Reopening must not duplicate existing files.
        let daily = files.directory(for: .daily).appendingPathComponent("legacy.m4a")
        XCTAssertEqual(try files.audioURLs(), [daily])
        let idea = try files.move(daily, to: .idea)
        for ext in ["m4a", "txt", "transcript.json", "md", "markdown-draft.json"] {
            XCTAssertEqual(try Data(contentsOf: idea.deletingPathExtension().appendingPathExtension(ext)), Data("内容-\(ext)".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: daily.deletingPathExtension().appendingPathExtension(ext).path))
        }
        XCTAssertEqual(try files.audioURLs(), [idea])
    }

    func testFolderMoveNeverOverwritesExistingTextOrAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = RecordingFiles(root: root)
        try files.prepare()
        let source = files.directory(for: .daily).appendingPathComponent("same.m4a")
        let target = files.directory(for: .idea).appendingPathComponent("same.m4a")
        try Data("new audio".utf8).write(to: source)
        try Data("old audio".utf8).write(to: target)
        try Data("old text".utf8).write(to: target.deletingPathExtension().appendingPathExtension("txt"))
        let result = try files.move(source, to: .idea)
        XCTAssertNotEqual(result, target)
        XCTAssertEqual(try Data(contentsOf: target), Data("old audio".utf8))
        XCTAssertEqual(try Data(contentsOf: result), Data("new audio".utf8))
        XCTAssertEqual(try files.audioURLs().count, 2)
    }

    @MainActor
    private func fixture() throws -> (URL, Recording) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("sample.m4a")
        try Data().write(to: url)
        return (folder, Recording(url: url, date: Date(), duration: 5))
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition())
    }

    @MainActor
    func testAutomaticExportEditAndReload() async throws {
        let (folder, recording) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubSpeech()
        let store = TranscriptionStore(engine: engine)
        store.setCanRun(true)
        store.enqueue(recording)
        try await waitFor { store.items[recording.url]?.status == .complete }
        XCTAssertEqual(try String(contentsOf: recording.transcriptURL, encoding: .utf8), engine.result)
        try store.saveEditedText("修改后的中文文字。", for: recording)
        let restored = TranscriptionStore(engine: engine)
        restored.reload([recording])
        XCTAssertEqual(restored.items[recording.url]?.text, "修改后的中文文字。")
        XCTAssertEqual(try String(contentsOf: recording.transcriptURL, encoding: .utf8), "修改后的中文文字。")
    }

    @MainActor
    func testManualEditBeforeRecognitionAndLateResultCannotOverwrite() async throws {
        let (folder, recording) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubSpeech()
        engine.delay = .milliseconds(200)
        let store = TranscriptionStore(engine: engine)
        store.reload([recording])
        try store.saveEditedText("手动补写", for: recording)
        XCTAssertEqual(store.items[recording.url]?.status, .complete)
        store.setCanRun(true)
        store.enqueue(recording)
        XCTAssertEqual(store.items[recording.url]?.status, .working)
        try store.saveEditedText("人工修正优先", for: recording)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(store.items[recording.url]?.text, "人工修正优先")
        XCTAssertEqual(try String(contentsOf: recording.transcriptURL, encoding: .utf8), "人工修正优先")
        let restored = TranscriptionStore(engine: engine)
        restored.reload([recording])
        XCTAssertEqual(restored.items[recording.url]?.text, "人工修正优先")
    }

    @MainActor
    func testReloadPicksUpNewlyImportedTranscript() throws {
        let (folder, recording) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TranscriptionStore(engine: StubSpeech())
        store.reload([recording])
        try store.saveEditedText("第一版", for: recording)
        let revised = Transcript(status: .complete, text: "手机补传", updatedAt: Date().addingTimeInterval(1))
        try JSONEncoder().encode(revised).write(to: recording.transcriptStateURL)
        store.reload([recording])
        XCTAssertEqual(store.items[recording.url]?.text, "手机补传")
    }

    @MainActor
    func testPauseResumeAndDeleteDuringRecognition() async throws {
        let (folder, recording) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubSpeech()
        engine.delay = .milliseconds(300)
        let store = TranscriptionStore(engine: engine)
        store.setCanRun(true)
        store.enqueue(recording)
        store.setCanRun(false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(store.items[recording.url]?.status, .queued)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.transcriptURL.path))
        store.setCanRun(true)
        try await waitFor { store.items[recording.url]?.status == .complete }
        store.enqueue(recording)
        store.remove(recording)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(store.items[recording.url])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.transcriptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.transcriptStateURL.path))
    }

    @MainActor
    func testFailureDoesNotExportPartialTextAndCanRetry() async throws {
        let (folder, recording) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubSpeech()
        engine.shouldFail = true
        let store = TranscriptionStore(engine: engine)
        store.setCanRun(true)
        store.enqueue(recording)
        try await waitFor { store.items[recording.url]?.status == .failed }
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.transcriptURL.path))
        engine.shouldFail = false
        store.enqueue(recording)
        try await waitFor { store.items[recording.url]?.status == .complete }
    }

    @MainActor
    func testPhoneMicrophoneSelection() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        try PhoneMicrophone.enforce(on: session)
        XCTAssertEqual(session.preferredInput?.portType, .builtInMic)
        XCTAssertFalse(session.currentRoute.inputs.isEmpty)
        XCTAssertTrue(session.currentRoute.inputs.allSatisfy { $0.portType == .builtInMic })
        XCTAssertFalse(session.categoryOptions.contains(.allowBluetoothHFP))
        print("Verified microphone route: \(session.currentRoute.inputs.map { $0.portName })")
    }

    @MainActor
    func testRealChineseSpeechOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("系统中文模型需在真机验证")
        #else
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "chinese-sample", withExtension: "aiff"))
        let result = try await AppleSpeechEngine().transcribe(url: url, language: "zh-CN") { _, detail in
            print("Speech integration: \(detail)")
        }
        print("Speech integration result: \(result)")
        XCTAssertTrue(result.contains("天气"), result)
        XCTAssertTrue(result.contains("电脑"), result)
        #endif
    }
}

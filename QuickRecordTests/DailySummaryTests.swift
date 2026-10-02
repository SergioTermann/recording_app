import XCTest
@testable import QuickRecord

@MainActor
private final class StubDailyAI: DailySummarizing {
    var calls = 0
    var delay: Duration = .zero
    var fail = false
    func summarize(source: String, day: String, key: String) async throws -> String {
        calls += 1
        try await Task.sleep(for: delay)
        if fail { throw SummaryAIError.http(402) }
        return "【今日重点】\n- 测试模型总结\n【明确待办】\n- 未提及"
    }
}

final class DailySummaryTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func recording(_ stamp: String, folder: String = "日常记录", name: String = UUID().uuidString) -> Recording {
        Recording(url: URL(fileURLWithPath: "/test/\(folder)/\(name).m4a"), date: date(stamp), duration: 10)
    }

    func testLocalMidnightBoundaryAndTwoFolders() {
        let builder = DailySummaryBuilder(timeZone: TimeZone(identifier: "Asia/Singapore")!)
        let daily = recording("2025-01-01T15:59:59Z")
        let idea = recording("2025-01-01T10:00:00Z", folder: "idea")
        let today = recording("2025-01-01T16:00:00Z")
        let docs = builder.build(recordings: [today, daily, idea], transcripts: [daily.url: Transcript(status: .complete, text: "今天散步"), idea.url: Transcript(status: .complete, text: "做一个语音日记")], now: date("2025-01-01T16:00:01Z"), directory: URL(fileURLWithPath: "/out"))
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs[0].day, "2025-01-01")
        XCTAssertEqual(docs[0].recordingCount, 2)
        XCTAssertTrue(docs[0].text.contains("23:59"))
        XCTAssertTrue(docs[0].text.contains("【idea】"))
        XCTAssertTrue(docs[0].text.contains("今天散步"))
        XCTAssertEqual(docs[0].pendingCount, 0)
    }

    func testPendingAndDSTBoundaryDoNotInventTextOrEmptyDays() {
        let builder = DailySummaryBuilder(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let beforeMidnight = recording("2025-03-10T06:59:59Z")
        let midnight = recording("2025-03-10T07:00:00Z")
        let docs = builder.build(recordings: [beforeMidnight, midnight], transcripts: [:], now: date("2025-03-10T07:00:01Z"), directory: URL(fileURLWithPath: "/out"))
        XCTAssertEqual(docs.map(\.day), ["2025-03-09"])
        XCTAssertEqual(docs[0].pendingCount, 1)
        XCTAssertTrue(docs[0].text.contains("等待转文字"))
        XCTAssertTrue(builder.build(recordings: [], transcripts: [:], now: Date(), directory: URL(fileURLWithPath: "/out")).isEmpty)
    }

    @MainActor
    func testAIExportIsCachedAndUpdatesAfterTextEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubDailyAI()
        let store = DailySummaryStore(directory: folder, engine: engine, keyProvider: { "test-only" })
        let entry = recording("2025-01-01T10:00:00Z")
        store.update(recordings: [entry], transcripts: [entry.url: Transcript(status: .complete, text: "测试原文")])
        XCTAssertTrue(store.rebuild())
        let completed = await store.finishBackgroundWork()
        XCTAssertTrue(completed)
        XCTAssertEqual(engine.calls, 1)
        XCTAssertTrue(store.documents[0].text.contains("测试模型总结"))
        XCTAssertTrue(store.documents[0].text.contains("测试原文"))
        XCTAssertEqual(try String(contentsOf: store.documents[0].url, encoding: .utf8), store.documents[0].text)
        store.rebuild()
        _ = await store.finishBackgroundWork()
        XCTAssertEqual(engine.calls, 1)
        store.update(recordings: [entry], transcripts: [entry.url: Transcript(status: .complete, text: "修改后的原文")])
        store.rebuild()
        _ = await store.finishBackgroundWork()
        XCTAssertEqual(engine.calls, 2)
        XCTAssertTrue(store.documents[0].text.contains("修改后的原文"))
        let restored = DailySummaryStore(directory: folder, engine: engine, keyProvider: { "test-only" })
        restored.update(recordings: [entry], transcripts: [entry.url: Transcript(status: .complete, text: "修改后的原文")])
        restored.rebuild()
        _ = await restored.finishBackgroundWork()
        XCTAssertEqual(engine.calls, 2)
    }

    @MainActor
    func testPendingFailureRetryAndDeletionPreserveUnrelatedFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubDailyAI()
        let store = DailySummaryStore(directory: folder, engine: engine, keyProvider: { "test-only" })
        let entry = recording("2025-01-01T10:00:00Z")
        store.update(recordings: [entry], transcripts: [:])
        store.rebuild()
        _ = await store.finishBackgroundWork()
        XCTAssertEqual(engine.calls, 0)
        XCTAssertTrue(store.documents[0].text.contains("AI 总结待生成"))
        engine.fail = true
        store.update(recordings: [entry], transcripts: [entry.url: Transcript(status: .complete, text: "保留原文")])
        store.rebuild()
        _ = await store.finishBackgroundWork()
        XCTAssertEqual(store.failures.count, 1)
        XCTAssertTrue(store.documents[0].text.contains("保留原文"))
        store.rebuild()
        _ = await store.finishBackgroundWork()
        XCTAssertEqual(engine.calls, 1)
        engine.fail = false
        store.retry()
        _ = await store.finishBackgroundWork()
        XCTAssertEqual(engine.calls, 2)
        let owned = store.documents[0].url
        let personal = folder.appendingPathComponent("我的文档.txt")
        try "我的内容".write(to: personal, atomically: true, encoding: .utf8)
        store.update(recordings: [], transcripts: [:])
        store.rebuild()
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: personal.path))
    }

    @MainActor
    func testCancelledAIIsNotPublishedAsComplete() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubDailyAI()
        engine.delay = .milliseconds(200)
        let store = DailySummaryStore(directory: folder, engine: engine, keyProvider: { "test-only" })
        let entry = recording("2025-01-01T10:00:00Z")
        store.update(recordings: [entry], transcripts: [entry.url: Transcript(status: .complete, text: "原文")])
        store.rebuild()
        store.setCanRun(true)
        try await Task.sleep(for: .milliseconds(30))
        store.setCanRun(false)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(store.documents[0].text.contains("测试模型总结"))
        XCTAssertNil(store.activeDay)
        XCTAssertTrue(store.failures.isEmpty)
    }

    func testAPIFinishReasonAndUnicodeChunking() throws {
        let valid = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"完整总结"}}]}"#.utf8)
        XCTAssertEqual(try DeepSeekDailySummarizer.parse(valid), "完整总结")
        let truncated = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"截断内容"}}]}"#.utf8)
        XCTAssertThrowsError(try DeepSeekDailySummarizer.parse(truncated))
        let source = String(repeating: "中文👨‍👩‍👧‍👦记录\n", count: 100)
        let chunks = DeepSeekDailySummarizer.chunks(source, limit: 37)
        XCTAssertEqual(chunks.joined(), source)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 37 })
    }
}

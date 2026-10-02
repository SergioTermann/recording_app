import Foundation
import SwiftUI
import CryptoKit

struct DailySummary: Identifiable, Equatable {
    let day: String
    let date: Date
    let text: String
    let recordingCount: Int
    let pendingCount: Int
    let url: URL
    var id: String { day }
}

struct DailySummaryBuilder {
    var calendar: Calendar

    init(timeZone: TimeZone) {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
    }

    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func build(recordings: [Recording], transcripts: [URL: Transcript], now: Date, directory: URL) -> [DailySummary] {
        let today = calendar.startOfDay(for: now)
        let groups = Dictionary(grouping: recordings.filter { $0.date < today }) { dayKey($0.date) }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "zh_CN")
        clock.timeZone = calendar.timeZone
        clock.dateFormat = "HH:mm"
        return groups.keys.sorted(by: >).map { day in
            let entries = groups[day]!.sorted { $0.date == $1.date ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.date < $1.date }
            let pending = entries.filter { transcripts[$0.url]?.status != .complete }.count
            let duration = entries.reduce(0) { $0 + $1.duration }
            var lines = ["\(day) · 当天原文", "", "共 \(entries.count) 段录音 · \(timeString(duration)) · 已转文字 \(entries.count - pending)/\(entries.count)", "按录音开始日期整理 · 时区：\(calendar.timeZone.identifier)", ""]
            if pending > 0 {
                lines += ["还有 \(pending) 段录音未完成转文字；完成后本文档会自动更新。", ""]
            }
            for folder in RecordingFolder.allCases {
                lines += ["【\(folder.rawValue)】", ""]
                let matching = entries.filter { $0.folder == folder }
                if matching.isEmpty { lines += ["当天没有这类记录。", ""] }
                for recording in matching {
                    lines.append("\(clock.string(from: recording.date)) · \(timeString(recording.duration))")
                    if let item = transcripts[recording.url], item.status == .complete {
                        lines.append(item.text.isEmpty ? "（文字已清空）" : item.text)
                    } else {
                        lines.append(transcripts[recording.url]?.status == .failed ? "（转文字失败，请到录音列表重新识别；原录音保留）" : "（等待转文字，原录音保留）")
                    }
                    lines.append("")
                }
            }
            lines += ["—", "原始录音转写按时间归档；语音识别可能有误，请对照原录音核对。"]
            return DailySummary(day: day, date: calendar.startOfDay(for: entries[0].date), text: lines.joined(separator: "\n"), recordingCount: entries.count, pendingCount: pending, url: directory.appendingPathComponent("\(day) 每日总结.txt"))
        }
    }
}

@MainActor
final class DailySummaryStore: ObservableObject {
    @Published private(set) var documents: [DailySummary] = []
    @Published private(set) var error: String?
    @Published private(set) var isConnected: Bool
    @Published private(set) var activeDay: String?
    @Published private(set) var failures: [String: String] = [:]
    let directory: URL
    let timeZone: TimeZone
    private let engine: any DailySummarizing
    private let keyProvider: () -> String?
    private var originals: [DailySummary] = []
    private var aiTask: Task<Void, Never>?
    private var aiGeneration = UUID()
    private var canRun = false
    private struct CachedAI: Codable {
        let fingerprint: String
        let text: String
    }
    private var cache: [String: CachedAI] = [:]
    private var recordings: [Recording] = []
    private var transcripts: [URL: Transcript] = [:]
    private var updateTask: Task<Void, Never>?

    init(directory: URL? = nil, defaults: UserDefaults = .standard, engine: any DailySummarizing = DeepSeekDailySummarizer(), keyProvider: @escaping () -> String? = SummaryKeychain.read) {
        self.engine = engine
        self.keyProvider = keyProvider
        isConnected = keyProvider() != nil
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("每日总结", isDirectory: true)
        // Pin the initial timezone so travelling never silently moves historical entries between days.
        let zone = defaults.string(forKey: "dailySummaryTimeZone") ?? TimeZone.current.identifier
        timeZone = TimeZone(identifier: zone) ?? .current
        defaults.set(timeZone.identifier, forKey: "dailySummaryTimeZone")
    }

    func update(recordings: [Recording], transcripts: [URL: Transcript]) {
        self.recordings = recordings
        self.transcripts = transcripts
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)); self?.rebuild() }
            catch { }
        }
    }

    @discardableResult
    func rebuild(now: Date = Date()) -> Bool {
        updateTask?.cancel()
        updateTask = nil
        let sources = DailySummaryBuilder(timeZone: timeZone).build(recordings: recordings, transcripts: transcripts, now: now, directory: directory)
        originals = sources
        for source in sources where cache[source.day] == nil {
            if let data = try? Data(contentsOf: cacheURL(source.day)), let saved = try? JSONDecoder().decode(CachedAI.self, from: data) { cache[source.day] = saved }
        }
        let next = sources.map { source -> DailySummary in
            let ai = cache[source.day]
            let matches = ai?.fingerprint == fingerprint(source) && source.pendingCount == 0
            let prefix: String
            if matches {
                prefix = "\(source.day) · AI 每日总结\n\n\(ai!.text)\n\nAI 提炼可能有误，以下原文用于核对。\n\n────────────────\n【当天完整原文】\n\n"
            } else {
                prefix = "\(source.day) · 每日文档（AI 总结待生成）\n\n\(source.pendingCount > 0 ? "正在等待录音转写完成。" : "已保留原文，AI 连接并完成处理后会自动更新。")\n\n"
            }
            return DailySummary(day: source.day, date: source.date, text: prefix + source.text, recordingCount: source.recordingCount, pendingCount: source.pendingCount, url: source.url)
        }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifestURL = directory.appendingPathComponent(".generated.json")
            let previous = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: manifestURL))) ?? []
            for document in next {
                if (try? String(contentsOf: document.url, encoding: .utf8)) != document.text {
                    try document.text.write(to: document.url, atomically: true, encoding: .utf8)
                }
            }
            let names = next.map { $0.url.lastPathComponent }
            // Only remove files this feature previously generated, never unrelated user documents.
            for name in previous where !names.contains(name) && name == URL(fileURLWithPath: name).lastPathComponent {
                let url = directory.appendingPathComponent(name)
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            }
            try JSONEncoder().encode(names).write(to: manifestURL, options: .atomic)
            documents = next
            error = nil
            for day in Array(cache.keys) where !sources.contains(where: { $0.day == day }) {
                cache.removeValue(forKey: day)
                try? manager.removeItem(at: cacheURL(day))
            }
            startAIIfNeeded()
            return true
        } catch {
            self.error = "每日总结保存失败：\(error.localizedDescription)"
            return false
        }
    }
    private func cacheURL(_ day: String) -> URL { directory.appendingPathComponent(".\(day).ai.json") }
    private func fingerprint(_ source: DailySummary) -> String {
        SHA256.hash(data: Data((DeepSeekDailySummarizer.model + "|prompt-v1|" + source.text).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func status(for day: String) -> String {
        if activeDay == day { return "正在生成 AI 总结…" }
        if let failure = failures[day] { return failure }
        guard let source = originals.first(where: { $0.day == day }) else { return "等待整理" }
        if source.pendingCount > 0 { return "等待 \(source.pendingCount) 段转文字" }
        if cache[day]?.fingerprint == fingerprint(source) { return "AI 总结已生成" }
        return isConnected ? "等待 AI 整理" : "连接 DeepSeek 后自动总结"
    }

    func connect(key: String) throws {
        guard !key.isEmpty else { throw SummaryAIError.missingKey }
        try SummaryKeychain.save(key)
        isConnected = true
        failures = [:]
        startAIIfNeeded()
    }

    func disconnect() {
        setCanRun(false)
        SummaryKeychain.remove()
        isConnected = false
    }

    func retry() {
        failures = [:]
        rebuild()
    }

    func setCanRun(_ value: Bool) {
        canRun = value
        if value { startAIIfNeeded() }
        else {
            aiGeneration = UUID()
            aiTask?.cancel()
            aiTask = nil
            activeDay = nil
        }
    }

    func finishBackgroundWork() async -> Bool {
        setCanRun(true)
        if let task = aiTask { await task.value }
        return failures.isEmpty && error == nil
    }

    private func startAIIfNeeded() {
        guard canRun, isConnected, aiTask == nil else { return }
        let token = UUID()
        aiGeneration = token
        aiTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.aiGeneration == token { self.aiTask = nil; self.activeDay = nil } }
            while !Task.isCancelled, self.canRun, self.aiGeneration == token,
                  let source = self.originals.first(where: { $0.pendingCount == 0 && self.failures[$0.day] == nil && self.cache[$0.day]?.fingerprint != self.fingerprint($0) }) {
                self.activeDay = source.day
                let digest = self.fingerprint(source)
                do {
                    guard let key = self.keyProvider() else { throw SummaryAIError.missingKey }
                    let text = try await self.engine.summarize(source: source.text, day: source.day, key: key)
                    try Task.checkCancellation()
                    guard self.aiGeneration == token else { return }
                    guard let current = self.originals.first(where: { $0.day == source.day }), self.fingerprint(current) == digest else { continue }
                    let saved = CachedAI(fingerprint: digest, text: text)
                    try JSONEncoder().encode(saved).write(to: self.cacheURL(source.day), options: .atomic)
                    self.cache[source.day] = saved
                    self.rebuild()
                } catch {
                    guard self.aiGeneration == token, !Task.isCancelled else { return }
                    self.failures[source.day] = "AI 总结未完成：\(error.localizedDescription)"
                }
            }
        }
    }

}

#if os(iOS)
struct DailySummaryListView: View {
    @ObservedObject var store: DailySummaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showConnection = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("每天结束后，AI 提炼今日重点、生活记录、idea 和明确待办，并附完整原文，保存为 TXT 文档。后台运行由系统安排；下次打开Glimpse时也会补齐。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("按 \(store.timeZone.identifier) 的录音开始日期整理；未完成转写时先保留原文，补齐后生成 AI 总结。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button(store.isConnected ? "DeepSeek 已连接 · 管理连接" : "连接 DeepSeek，开启 AI 总结") { showConnection = true }
                    if !store.failures.isEmpty { Button("重试未完成的 AI 总结") { store.retry() } }
                }
                if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
                if store.documents.isEmpty {
                    ContentUnavailableView("还没有每日总结", systemImage: "calendar", description: Text("今天的录音会在这一天结束后归档。没有录音的日期不会生成空文档。"))
                } else {
                    Section("按日期") {
                        ForEach(store.documents) { document in
                            NavigationLink {
                                DailySummaryDetailView(day: document.day, store: store)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(document.day).font(.headline)
                                    Text("\(document.recordingCount) 段录音 · \(store.status(for: document.day))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("dailySummary-\(document.day)")
                        }
                    }
                }
                Section { Text("文档位置：文件 → 我的 iPhone → Glimpse → 每日总结。转写修改、移动分类或删除录音后，文档会同步更新；已分享到其他位置的副本不变。")
                    .font(.caption).foregroundStyle(.secondary) }
            }
            .sheet(isPresented: $showConnection) { SummaryConnectionView(store: store) }
            .navigationTitle("每日总结")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.light)
    }
}

struct DailySummaryDetailView: View {
    let day: String
    @ObservedObject var store: DailySummaryStore
    @State private var copied = false
    var body: some View {
        if let document = store.documents.first(where: { $0.day == day }) {
            ScrollView {
                Text(document.text).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).lineSpacing(6).padding(24)
                    .accessibilityIdentifier("dailySummaryText")
            }
            .navigationTitle(day)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(copied ? "已复制" : "复制全文", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = document.text
                        copied = true
                    }
                    Spacer()
                    ShareLink(item: document.url) { Label("导出文档", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("exportDailySummary")
                }
            }
        } else { ContentUnavailableView("该日期已没有录音", systemImage: "doc") }
    }
}

#endif

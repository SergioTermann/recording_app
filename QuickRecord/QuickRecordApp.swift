import SwiftUI
import AppIntents

@main
struct QuickRecordApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = Recorder.shared
    @State private var lastSummaryDay = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .onOpenURL { url in
                    if url.scheme == "quickrecord", url.host == "pair" {
                        do { try PhoneArchiveSync.shared.accept(url) } catch { recorder.message = error.localizedDescription }; return
                    }
                    guard url.scheme == "quickrecord", url.host == "record" else { return }
                    recorder.requestStart()
                }
                .task {
                    PhoneArchiveSync.shared.observe(recorder)
                    PhoneArchiveSync.shared.setActive(scenePhase == .active)
                    recorder.startIfRequested()
                    recorder.rebuildDailySummaries()
                    recorder.updateTranscriptionActivity()
                    DailySummaryScheduler.schedule(timeZone: recorder.dailySummaries.timeZone)
                }
                .onChange(of: scenePhase) { _, phase in
                    PhoneArchiveSync.shared.setActive(phase == .active)
                    if phase == .active { recorder.startIfRequested() }
                    if phase == .active { recorder.rebuildDailySummaries() }
                    recorder.updateTranscriptionActivity()
                    if phase == .background { DailySummaryScheduler.schedule(timeZone: recorder.dailySummaries.timeZone) }
                }
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                    let day = DailySummaryBuilder(timeZone: recorder.dailySummaries.timeZone).dayKey(now)
                    if scenePhase == .active && day != lastSummaryDay {
                        lastSummaryDay = day
                        recorder.rebuildDailySummaries()
                    }
                }
        }
    }
}

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始录音"
    static var description = IntentDescription("打开Glimpse并立即开始录音。首次使用需要允许麦克风；锁屏时可能需要解锁。")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Recorder.shared.requestStart()
        return .result()
    }
}

struct RecordingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: ["用\(.applicationName)开始录音", "Start recording with \(.applicationName)"],
            shortTitle: "开始录音",
            systemImageName: "mic.fill"
        )
    }
}

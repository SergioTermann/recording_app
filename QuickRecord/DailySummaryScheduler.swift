import BackgroundTasks
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: DailySummaryScheduler.identifier, using: .main) { task in
            // The scheduler can expire the task; never report success after expiry.
            let completion = BackgroundCompletion(task)
            task.expirationHandler = {
                completion.finish(success: false)
                Task { @MainActor in Recorder.shared.dailySummaries.setCanRun(false) }
            }
            Task { @MainActor in
                guard !completion.finished else { return }
                let recorder = Recorder.shared
                DailySummaryScheduler.schedule(timeZone: recorder.dailySummaries.timeZone)
                var success = recorder.rebuildDailySummaries()
                if success { success = await recorder.dailySummaries.finishBackgroundWork() }
                completion.finish(success: success)
            }
        }
        return true
    }
}

private final class BackgroundCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let task: BGTask
    init(_ task: BGTask) { self.task = task }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return completed }
    func finish(success: Bool) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

enum DailySummaryScheduler {
    static let identifier = "com.zinger.quickrecord.daily-summary"
    static func schedule(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = midnight.addingTimeInterval(60)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        // Background scheduling is opportunistic. Foreground catch-up is always enabled.
        try? BGTaskScheduler.shared.submit(request)
    }
}

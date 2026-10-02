import Foundation

struct Recording: Identifiable {
    let url: URL
    let date: Date
    let duration: TimeInterval
    var id: URL { url }
    var title: String { date.formatted(.dateTime.month().day().hour().minute().second()) }
}


func timeString(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
}

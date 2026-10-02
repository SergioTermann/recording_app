import SwiftUI
import AppKit

@main
struct GlimpseMacApp: App {
    @StateObject private var library: MacLibrary
    @StateObject private var server: MacSyncServer
    init() {
        let library = MacLibrary()
        _library = StateObject(wrappedValue: library)
        _server = StateObject(wrappedValue: MacSyncServer(library: library))
    }
    var body: some Scene {
        WindowGroup("Glimpse") {
            MacContentView(library: library, server: server)
        }.defaultSize(width: 1190, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button(library.isRecording ? "停止并保存录音" : "开始录音") {
                    if library.isRecording { library.stop() } else { Task { await library.start() } }
                }.keyboardShortcut("r",modifiers:[.command,.shift])
                Button("打开档案文件夹") { library.reveal(library.root) }.keyboardShortcut("o",modifiers:[.command,.shift])
            }
        }
    }
}

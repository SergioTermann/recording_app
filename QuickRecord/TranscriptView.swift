import SwiftUI

struct TranscriptRow: View {
    let recording: Recording
    @ObservedObject var store: TranscriptionStore
    let open: () -> Void

    var body: some View {
        let item = store.items[recording.url]
        Button {
            if item == nil { store.enqueue(recording) }
            open()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if item?.status == .working || item?.status == .queued { ProgressView().controlSize(.small) }
                else { Image(systemName: "doc.text") }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item?.status == .complete ? "文字 · 已生成 TXT" : (item?.detail ?? "转文字"))
                        .font(.caption.weight(.medium))
                    if let item, !item.text.isEmpty {
                        Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcriptRow")
    }
}

struct TranscriptView: View {
    let recording: Recording
    @ObservedObject var store: TranscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var editing = false
    @State private var copied = false
    @State private var error: String?

    var body: some View {
        let item = store.items[recording.url]
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(recording.title).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    if item?.status == .working || item?.status == .queued { ProgressView() }
                    Text(item?.detail ?? "将录音转换为普通话文字").font(.footnote).foregroundStyle(.secondary)
                }
                if editing {
                    TextEditor(text: $draft).accessibilityIdentifier("transcriptEditor")
                } else {
                    ScrollView {
                        Text(item?.text.isEmpty == false ? item!.text : "识别完成后，文字会显示在这里。")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled).lineSpacing(7)
                            .accessibilityIdentifier("transcriptText")
                    }
                }
                if item?.status == .complete {
                    if editing {
                        Button("保存修改并更新 TXT") {
                            do { try store.saveEditedText(draft, for: recording); editing = false }
                            catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                    } else {
                        HStack {
                            Button(copied ? "已复制" : "复制文字", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = item?.text
                                copied = true
                            }
                            ShareLink(item: recording.transcriptURL) {
                                Label("导出 TXT", systemImage: "square.and.arrow.up")
                            }.accessibilityIdentifier("exportTranscript")
                        }.buttonStyle(.bordered)
                        Button("修改文字") { draft = item?.text ?? ""; editing = true }
                        Text("识别可能有误，重要内容请对照录音核对。TXT 已自动保存到本机。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if item == nil || item?.status == .failed {
                    Button("重新识别") { store.enqueue(recording) }.buttonStyle(.borderedProminent)
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(.footnote)
                }
            }
            .padding(24)
            .navigationTitle("录音文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(editing) } }
            .interactiveDismissDisabled(editing)
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }.preferredColorScheme(.light)
    }
}

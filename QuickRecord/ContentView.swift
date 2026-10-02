import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var recorder: Recorder
    @State private var deleteTarget: Recording?
    @State private var transcriptTarget: Recording?
    @State private var showDailySummaries = false
    private let accent = Color(red: 0.86, green: 0.20, blue: 0.13)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Glimpse").font(.largeTitle.bold())
                            Text("把此刻，留下来。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            recorder.rebuildDailySummaries()
                            showDailySummaries = true
                        } label: {
                            Label("每日总结", systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                        }.accessibilityIdentifier("dailySummaries")
                    }

                    MacArchiveCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("保存到").font(.subheadline).foregroundStyle(.secondary)
                        Picker("保存到", selection: $recorder.selectedFolder) {
                            ForEach(RecordingFolder.allCases) { folder in
                                Text(folder.rawValue).tag(folder)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("folderPicker")
                        Text("录音和文字一起保存 · 停止前可切换文件夹")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Circle().fill(recorder.isRecording ? accent : .gray).frame(width: 7, height: 7)
                            Text(recorder.isRecording ? "正在录音" : "准备就绪")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        Text(timeString(recorder.elapsed))
                            .font(.system(size: 38, weight: .light, design: .monospaced))
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .accessibilityIdentifier("recordingTimer")
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(0..<35) { index in
                                let contour = Float((index * 13 + 7) % 19 + 3) / 22
                                Capsule().fill(recorder.isRecording ? accent : .black.opacity(0.18))
                                    .frame(width: 4, height: recorder.isRecording ? 4 + CGFloat(recorder.level * contour) * 30 : 4)
                            }
                        }
                        .frame(height: 36).accessibilityHidden(true)
                        Button {
                            if recorder.isRecording { recorder.stop() }
                            else { Task { await recorder.start() } }
                        } label: {
                            ZStack {
                                Circle().stroke(accent.opacity(0.35), lineWidth: 2).frame(width: 76, height: 76)
                                Circle().fill(accent).frame(width: 64, height: 64)
                                if recorder.isStarting {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 25, weight: .semibold)).foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(recorder.isStarting)
                        .accessibilityLabel(recorder.isRecording ? "停止并保存" : "开始录音")
                        .accessibilityIdentifier("recordButton")
                        Text(recorder.isRecording ? "轻点停止，自动保存" : "轻点录音 · 或长按操作按钮")
                            .font(.footnote).foregroundStyle(.secondary)
                        Label(recorder.microphoneName, systemImage: "iphone")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("microphoneSource")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18).padding(.horizontal, 16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(recorder.selectedFolder.rawValue, systemImage: recorder.selectedFolder.icon).font(.title3.bold())
                            Spacer()
                            Text("\(recorder.visibleRecordings.count) 条").font(.caption).foregroundStyle(.secondary)
                        }
                        if recorder.visibleRecordings.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "waveform").font(.title).foregroundStyle(.gray)
                                Text("这个文件夹还没有录音").font(.subheadline).foregroundStyle(.secondary)
                                Text("录音保存在本机，无需注册")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        } else {
                            ForEach(recorder.visibleRecordings) { recording in
                                VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button { recorder.play(recording) } label: {
                                        Image(systemName: recorder.playingURL == recording.url ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 38)).foregroundStyle(accent)
                                    }
                                    .disabled(recorder.isRecording || recorder.isStarting)
                                    .accessibilityLabel(recorder.playingURL == recording.url ? "停止播放" : "播放录音")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(recording.title).font(.subheadline.weight(.medium))
                                        Text(timeString(recording.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Menu {
                                        ShareLink(item: recording.url) { Label("导出录音", systemImage: "square.and.arrow.up") }
                                        Button {
                                            recorder.move(recording, to: recording.folder == .daily ? .idea : .daily)
                                        } label: {
                                            Label("移到\(recording.folder == .daily ? RecordingFolder.idea.rawValue : RecordingFolder.daily.rawValue)", systemImage: "folder")
                                        }
                                        Button(role: .destructive) { deleteTarget = recording } label: {
                                            Label("删除录音", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").padding(12).contentShape(Rectangle())
                                    }.accessibilityLabel("录音选项")
                                }
                                TranscriptRow(recording: recording, store: recorder.transcripts) {
                                    transcriptTarget = recording
                                }
                                }
                                .padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDailySummaries) { DailySummaryListView(store: recorder.dailySummaries) }
            .sheet(item: $transcriptTarget) { recording in
                TranscriptView(recording: recording, store: recorder.transcripts)
            }
            .alert("提示", isPresented: Binding(get: { recorder.message != nil }, set: { if !$0 { recorder.message = nil } })) {
                if recorder.needsSettings {
                    Button("打开设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button("知道了", role: .cancel) { recorder.message = nil }
            } message: { Text(recorder.message ?? "") }
            .confirmationDialog("删除这段录音及对应文字？每日总结会同步更新，删除后无法恢复。", isPresented: Binding(
                get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible) {
                Button("删除录音", role: .destructive) {
                    if let recording = deleteTarget { recorder.delete(recording) }
                    deleteTarget = nil
                }
            }
        }
        .tint(accent).preferredColorScheme(.light)
    }
}

import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

struct MacContentView: View {
    @ObservedObject var library: MacLibrary
    @ObservedObject var server: MacSyncServer
    @State private var section = "全部文稿"
    @State private var selected: URL?
    @State private var search = ""
    @State private var pairing = false
    @State private var capture = false
    @State private var deleting: Recording?
    private let accent = Color(red: 0.40, green: 0.12, blue: 0.19)
    private let sections = ["全部文稿", "日常记录", "idea", "手机归档", "每日总结"]
    private var filtered: [Recording] {
        library.recordings.filter { r in
            let matches = section == "全部文稿" || (section == "手机归档" ? library.isImported(r) : r.folder.rawValue == section)
            let text = library.transcripts.items[r.url]?.text ?? ""
            return matches && (search.isEmpty || r.title.localizedCaseInsensitiveContains(search) || text.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Glimpse").font(.system(size: 29, weight: .medium, design: .serif))
                        Spacer()
                        Image(systemName: "square.and.pencil").foregroundStyle(accent.opacity(0.7))
                    }
                    Picker("文稿分类", selection: $section) {
                        ForEach(sections, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).controlSize(.large).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索文稿", text: $search).textFieldStyle(.plain).accessibilityIdentifier("documentSearch")
                    }.padding(10).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    HStack { Text(section == "每日总结" ? "按日期整理" : "文稿").fontWeight(.medium); Spacer(); Text("\(filtered.count)") }.font(.caption).foregroundStyle(.secondary)
                }.padding(20)
                if section == "每日总结" {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "calendar").font(.title2)
                        Text("每日重点与灵感").font(.headline)
                        Text("在右侧查看每日总结与完整原文。").font(.caption).foregroundStyle(.secondary)
                    }.padding(22)
                    Spacer()
                } else if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text").font(.title2)
                        Text(search.isEmpty ? "还没有文稿" : "没有匹配的文稿")
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 25)
                    Spacer()
                } else {
                    List(selection: $selected) {
                        ForEach(filtered) { r in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(documentTitle(r)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                Text(excerpt(r)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                                HStack(spacing: 5) {
                                    Text(r.date.formatted(.dateTime.month().day().hour().minute()))
                                    Spacer(minLength: 3)
                                    Image(systemName: library.isImported(r) ? "iphone" : "mic")
                                    Text(r.folder.rawValue)
                                }.font(.system(size: 10)).foregroundStyle(.tertiary)
                            }.padding(.vertical, 11).tag(r.url)
                            .contextMenu {
                                Button("在 Finder 中显示") { library.reveal(r.url) }
                                Button("移到废纸篓", role: .destructive) { deleting = r }
                            }
                        }
                    }.listStyle(.sidebar).scrollContentBackground(.hidden)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Circle().fill(server.available ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text(server.receiving ? "正在接收手机文稿" : "手机归档").font(.caption.weight(.medium))
                        Spacer()
                        Button { pairing = true } label: { Image(systemName: "qrcode") }.buttonStyle(.plain).help("连接手机")
                    }
                    if server.receiving { ProgressView(value: server.progress) }
                    Text(server.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    Button("打开档案文件夹", systemImage: "folder") { library.reveal(library.root) }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }.padding(18)
            }
            .background(Color(red: 0.953, green: 0.947, blue: 0.935))
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 320)
        } detail: {
            if section == "每日总结" {
                MacSummaryView(store: library.summaries)
            } else if let recording = library.recordings.first(where: { $0.url == selected }) {
                MacMarkdownWorkspace(recording: recording, library: library).id(recording.url)
            } else {
                VStack(spacing: 17) {
                    Image(systemName: "square.and.pencil").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(accent.opacity(0.6))
                    Text("把声音，写成自己的文稿。").font(.system(size: 27, weight: .medium, design: .serif))
                    Text("从左侧选择录音，在这里用 Markdown 整理、补充和写作。").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("连接 iPhone", systemImage: "qrcode") { pairing = true }
                        Button("在 Mac 录音", systemImage: "mic") { capture = true }
                    }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.98, green: 0.977, blue: 0.971))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { capture = true } label: {
                    Label(library.isRecording ? timeString(library.elapsed) : "录音", systemImage: library.isRecording ? "record.circle.fill" : "mic")
                }.help("录制新的文稿").popover(isPresented: $capture) { captureControls }
                Button("连接手机", systemImage: "iphone") { pairing = true }
            }
        }
        .tint(accent).preferredColorScheme(.light).frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $pairing) { MacPairingSheet(server: server) }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: filtered.map(\.url)) { _, _ in selectFirstIfNeeded() }
        .alert("提示", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("好") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .confirmationDialog("将录音移到废纸篓？手机原文件保留，再次归档时可能重新传入。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("移到废纸篓", role: .destructive) { if let deleting { library.trash(deleting) }; deleting = nil }
        }
    }
    private func selectFirstIfNeeded() {
        guard section != "每日总结" else { return }
        if !filtered.contains(where: { $0.url == selected }) { selected = filtered.first?.url }
    }
    private func documentTitle(_ r: Recording) -> String {
        let text = library.transcripts.items[r.url]?.text ?? ""
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        let stripped = line.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
        return stripped.isEmpty ? r.date.formatted(.dateTime.month().day().hour().minute()) + " 录音" : stripped
    }
    private func excerpt(_ r: Recording) -> String {
        let text = library.transcripts.items[r.url]?.text ?? ""
        let lines = text.split(separator: "\n").dropFirst().joined(separator: " ")
        return lines.isEmpty ? (text.isEmpty ? "点击开始整理文字" : "Markdown 文稿") : lines
    }
    private var captureControls: some View {
        VStack(spacing: 20) {
            Text(library.isRecording ? "正在录音" : "新录音").font(.headline)
            Text(timeString(library.elapsed)).font(.system(size: 30, weight: .light, design: .monospaced))
            Picker("保存到", selection: $library.selectedFolder) { ForEach(RecordingFolder.allCases) { Text($0.rawValue).tag($0) } }.disabled(library.isRecording)
            Button(library.isRecording ? "停止并保存" : "开始录音", systemImage: library.isRecording ? "stop.fill" : "mic.fill") {
                if library.isRecording { library.stop(); capture = false } else { Task { await library.start() } }
            }.buttonStyle(.borderedProminent).disabled(library.starting).accessibilityIdentifier("macRecordButton")
            Text("保存后自动转写，继续在中间编辑区整理。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 280)
    }
}

struct MacPairingSheet: View {
    @ObservedObject var server: MacSyncServer
    @Environment(\.dismiss) private var dismiss
    @State private var reveal = false
    @State private var reset = false
    var body: some View {
        VStack(spacing:20) {
            HStack { Text("连接你的 iPhone").font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
            Text("两台设备连接同一 Wi-Fi。手机打开 Glimpse → Mac 归档 → 扫描 Mac 配对二维码。")
                .foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            if reveal, let pair=server.pair, let qr=qrImage(pair.pairingURL) {
                Image(nsImage:qr).interpolation(.none).resizable().frame(width:260,height:260).padding(16).background(.white,in:RoundedRectangle(cornerRadius:16))
                Button("复制配对链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pair.pairingURL,forType:.string) }
                Text("二维码是这台 Mac 的配对凭证，请只用自己的手机扫描。").font(.caption).foregroundStyle(.secondary)
            } else {
                Button { reveal=true } label: { Label("显示配对二维码",systemImage:"qrcode").frame(width:260,height:220) }.buttonStyle(.bordered)
            }
            Text(server.status).font(.callout)
            if let host = server.pair?.host { Text("局域网 IP：\(host)").font(.callout.monospaced()).textSelection(.enabled) }
            Text("若扫描后一直等待，可在手机配对页输入上方 IP；仍使用同一配对密钥加密连接。").font(.caption).foregroundStyle(.secondary)
            Text("配对后自动传输未归档录音及文字，原文件留在手机。归档位置：文稿 / Glimpse / 手机归档 / 日期 / 分类。")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Button("重新启动连接") { server.start() }; Spacer(); Button("重置配对",role:.destructive) { reset=true } }
        }.padding(28).frame(width:490)
        .confirmationDialog("重置后，原来配对的手机需要重新扫码。",isPresented:$reset) { Button("重置配对",role:.destructive) { server.resetPairing(); reveal=false } }
    }
    private func qrImage(_ value:String) -> NSImage? {
        let f=CIFilter.qrCodeGenerator(); f.message=Data(value.utf8); f.correctionLevel="M"
        guard let output=f.outputImage?.transformed(by:CGAffineTransform(scaleX:8,y:8)),let cg=CIContext().createCGImage(output,from:output.extent) else{return nil}
        return NSImage(cgImage:cg,size:NSSize(width:output.extent.width,height:output.extent.height))
    }
}

struct MacSummaryView: View {
    @ObservedObject var store: DailySummaryStore
    @State private var selected:String?
    @State private var connecting=false
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Text("每日总结").font(.largeTitle.weight(.semibold)); Spacer()
                Button(store.isConnected ? "管理 AI 连接" : "连接 DeepSeek") { connecting=true }
                Button("重新检查") { store.rebuild(); store.retry() }
            }
            Text("每天结束后按日期整理重点、生活、idea 和待办。Mac 上的 AI 密钥独立保存在本机钥匙串；手机密钥不会随录音传输。")
                .foregroundStyle(.secondary)
            if let error=store.error { Text(error).foregroundStyle(.red) }
            HSplitView {
                List(selection:$selected) { ForEach(store.documents) { doc in VStack(alignment:.leading,spacing:6) { Text(doc.day).font(.headline); Text(store.status(for:doc.day)).font(.caption).foregroundStyle(.secondary) }.padding(.vertical,8).tag(doc.day) } }.frame(width:210)
                if let doc=store.documents.first(where:{$0.day==selected}) {
                    VStack { HStack { Text(doc.day).font(.title2); Spacer(); ShareLink("导出文档",item:doc.url) }; ScrollView { Text(doc.text).textSelection(.enabled).lineSpacing(7).frame(maxWidth:.infinity,alignment:.leading) } }.padding(20)
                } else { ContentUnavailableView("每日档案",systemImage:"calendar",description:Text("选择日期查看总结；今天的录音在当天结束后整理。" )).frame(maxWidth:.infinity) }
            }
        }.padding(28).sheet(isPresented:$connecting) { MacAIConnection(store:store) }
    }
}
struct MacAIConnection: View {
    @ObservedObject var store:DailySummaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var key=""
    @State private var validating=false
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("连接 DeepSeek").font(.title2.bold())
            Text("每日总结会将文字与日期发送到 DeepSeek，按你的账户计费。密钥仅保存于此 Mac 的钥匙串。")
            SecureField("API Key",text:$key).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.disabled(validating)
                if store.isConnected { Button("断开",role:.destructive) { store.disconnect();dismiss() } }
                Spacer()
                Button(validating ? "验证中…" : "保存并开启") {
                    validating=true
                    Task { defer{validating=false};do { let entered=key.trimmingCharacters(in:.whitespacesAndNewlines);try await DeepSeekDailySummarizer.validateKey(entered);try store.connect(key:entered);store.setCanRun(true);key="";dismiss() }catch{self.error=error.localizedDescription} }
                }.disabled(validating || key.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width:470).interactiveDismissDisabled(validating)
    }
}

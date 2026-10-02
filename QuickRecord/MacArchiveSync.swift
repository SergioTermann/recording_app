import SwiftUI
import Network
import AVFoundation
import Combine

private struct SyncCandidate: Sendable {
    let url: URL
    let date: Date
    let duration: Double
    let category: String
    let text: String?
}
private actor PhoneOfferBuilder {
    private var hashes: [URL: (Int64, Date, String)] = [:]
    func build(_ candidates: [SyncCandidate], deviceID: UUID, name: String) throws -> [(ArchiveOffer, URL)] {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return try candidates.map { c in
            try Task.checkCancellation()
            let values = try c.url.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey])
            let size = Int64(values.fileSize ?? 0); let modified = values.contentModificationDate ?? .distantPast
            let hash: String
            if let saved = hashes[c.url], saved.0 == size, saved.1 == modified { hash = saved.2 }
            else { hash = try ArchiveOffer.fileHash(c.url); hashes[c.url] = (size, modified, hash) }
            let base = c.url.deletingPathExtension().lastPathComponent
            let id: UUID
            if let uuid = UUID(uuidString: base) { id = uuid }
            else {
                let h = ArchiveOffer.digest(Data(base.utf8))
                let chars = Array(h.prefix(32)); let parts = [0..<8,8..<12,12..<16,16..<20,20..<32].map { String(chars[$0]) }
                id = UUID(uuidString: parts.joined(separator: "-"))!
            }
            return (ArchiveOffer(recordingID: id, deviceID: deviceID, deviceName: name, category: c.category, date: c.date, day: formatter.string(from: c.date), duration: c.duration, byteCount: size, audioHash: hash, transcript: c.text), c.url)
        }
    }
}

@MainActor
final class PhoneArchiveSync: ObservableObject {
    static let shared = PhoneArchiveSync()
    @Published private(set) var paired = PairKeychain.read() != nil
    @Published private(set) var status = "未连接 Mac"
    @Published private(set) var progress: Double = 0
    @Published private(set) var syncing = false
    @Published private(set) var lastCompleted: Date?
    @Published var showPairing = false
    private var pair = PairKeychain.read()
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var connection: LocalConnection?
    private var task: Task<Void,Never>?
    private var debounce: Task<Void,Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var active = false
    private var retry: Timer?
    private var completedFingerprint: String?
    private var preferDirect = false
    private let builder = PhoneOfferBuilder()
    private let sender = ArchiveSender()
    private var deviceID: UUID {
        if let text = UserDefaults.standard.string(forKey: "archiveDeviceID"), let id = UUID(uuidString: text) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: "archiveDeviceID"); return id
    }
    init() {
        status = pair == nil ? "扫码连接 Mac，自动归档" : "等待同一 Wi-Fi 下的 Mac"
    }
    func observe(_ recorder: Recorder) {
        guard subscriptions.isEmpty else { return }
        recorder.$recordings.combineLatest(recorder.transcripts.$items)
            .sink { [weak self] _,_ in
                self?.debounce?.cancel()
                self?.debounce = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.sync()
                }
            }.store(in: &subscriptions)
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if value {
            completedFingerprint = nil
            browse()
            retry = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in Task { @MainActor in self?.sync() } }
        } else {
            retry?.invalidate(); retry = nil
            browser?.cancel(); browser = nil; endpoint = nil
            task?.cancel(); connection?.cancel()
            if paired { status = "打开 Glimpse 后继续归档" }
        }
    }
    func accept(_ url: URL) throws {
        let config = try PairConfiguration.parse(url)
        try PairKeychain.save(config)
        task?.cancel(); connection?.cancel(); browser?.cancel(); browser = nil; endpoint = nil
        pair = config; paired = true; completedFingerprint = nil; showPairing = false
        browse()
    }
    func disconnect() {
        task?.cancel(); connection?.cancel(); browser?.cancel(); browser = nil; endpoint = nil
        PairKeychain.remove(); pair = nil; paired = false; completedFingerprint = nil; status = "扫码连接 Mac，自动归档"
    }
    func useDirectAddress(_ host: String) throws {
        guard PairConfiguration.localIPv4(host), var updated = pair else { throw ArchiveFailure.unpaired }
        updated.host = host; updated.port = 49743
        try PairKeychain.save(updated); pair = updated; preferDirect = true; retryNow()
    }
    func retryNow() { completedFingerprint = nil; if browser == nil { browse() }; sync() }
    private func browse() {
        guard active, let pair, browser == nil else { return }
        status = "正在寻找已配对的 Mac…"
        let params = NWParameters.tcp; params.includePeerToPeer = false; params.prohibitedInterfaceTypes = [.cellular]
        let browser = NWBrowser(for: .bonjour(type: PairConfiguration.serviceType, domain: "local."), using: params)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results,_ in
            Task { @MainActor in
                guard let self else { return }
                self.endpoint = results.first { result in
                    if case .service(let name,_,_,_) = result.endpoint { return name == pair.serverID.uuidString }
                    return false
                }?.endpoint
                if self.endpoint != nil { self.sync() }
                else if !self.syncing { self.status = "等待同一 Wi-Fi 下的 Mac" }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .waiting = state { self?.status = "请允许本地网络访问，并连接同一 Wi-Fi" }
                if case .failed = state { self?.status = "未找到 Mac，请检查 Wi-Fi 与本地网络权限"; self?.browser?.cancel(); self?.browser = nil }
            }
        }
        browser.start(queue: DispatchQueue(label: "glimpse.browse"))
        sync()
    }
    private func sync() {
        guard active, !syncing, let pair else { return }
        let direct: NWEndpoint? = pair.host.flatMap { host in pair.port.flatMap { NWEndpoint.Port(rawValue: $0) }.map { .hostPort(host: NWEndpoint.Host(host), port: $0) } }
        guard let target = preferDirect ? (direct ?? endpoint) : (endpoint ?? direct) else { return }
        let recorder = Recorder.shared
        guard !recorder.isRecording, !recorder.isStarting else { return }
        let candidates = recorder.recordings.map { r in
            SyncCandidate(url: r.url, date: r.date, duration: r.duration, category: r.folder.rawValue, text: recorder.transcripts.items[r.url].flatMap { $0.status == .complete ? $0.text : nil })
        }
        guard !candidates.isEmpty else { status = "Mac 已发现 · 录音保存后自动归档"; return }
        let device = deviceID
        let name = UIDevice.current.name
        syncing = true
        task = Task { [weak self] in
            guard let self else { return }
            var connection: LocalConnection?
            defer { connection?.cancel(); self.connection = nil; self.syncing = false; self.task = nil }
            do {
                let offers = try await builder.build(candidates, deviceID: device, name: name)
                let fingerprint = ArchiveOffer.digest(try JSONEncoder().encode(offers.map { $0.0 }))
                guard fingerprint != self.completedFingerprint else { return }
                self.status = "正在安全连接 Mac…"
                let socket = LocalConnection(NWConnection(to: target, using: pair.parameters()))
                connection = socket; self.connection = socket
                try await socket.start()
                self.status = "正在归档 \(offers.count) 条录音…"
                try await sender.send(offers: offers, through: socket) { [self] index,total,part in
                    await MainActor.run {
                        self.progress = (Double(index)+part)/Double(max(1,total))
                        self.status = "正在归档 \(min(index+1,total))/\(total)"
                    }
                }
                self.completedFingerprint = fingerprint; self.progress = 1
                self.lastCompleted = Date(); self.status = "\(offers.count) 条录音已归档到 Mac"
            } catch {
                self.preferDirect.toggle()
                if self.active, self.paired { self.status = "归档未完成，将自动重试：\(error.localizedDescription)" }
            }
        }
    }
}

struct MacArchiveCard: View {
    @ObservedObject private var sync = PhoneArchiveSync.shared
    var body: some View {
        Button { sync.showPairing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac 归档").font(.subheadline.weight(.semibold))
                    Text(sync.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if sync.syncing { ProgressView(value: sync.progress) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("macArchive")
        .sheet(isPresented: $sync.showPairing) { MacPairingView(sync: sync) }
    }
}

struct MacPairingView: View {
    @ObservedObject var sync: PhoneArchiveSync
    @Environment(\.dismiss) private var dismiss
    @State private var scan = false
    @State private var error: String?
    @State private var link = ""
    @State private var address = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(sync.paired ? "已配对 Mac" : "连接你的 Mac", systemImage: "desktopcomputer")
                    Text(sync.status).foregroundStyle(.secondary)
                    Text("在 Mac 打开 Glimpse → 连接手机 → 显示二维码，再用下方按钮扫描。两端连接同一 Wi-Fi，并保持 Glimpse 打开。")
                }
                Section {
                    Button("扫描 Mac 配对二维码", systemImage: "qrcode.viewfinder") { scan = true }
                    SecureField("也可以粘贴 Mac 配对链接", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("使用配对链接") { accept(link) }.disabled(link.isEmpty)
                }
                Section {
                    Text("自动上传所有未归档录音和已完成的文字稿；手机文件保留。传输使用端到端加密，仅已配对设备可连接。切到后台可能暂停，重新打开会重试。")
                    Text("录音按日期及「日常记录 / idea」在 Mac 归档。之后的手机文字可补传；Mac 已编辑的文字不会被覆盖，手机版本会另存为 recording.phone.txt。")
                }
                if sync.paired {
                    TextField("找不到 Mac？输入 Mac 显示的局域网 IP", text: $address).keyboardType(.decimalPad)
                    Button("使用局域网 IP 连接") {
                        do { try sync.useDirectAddress(address.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(address.isEmpty)
                    Button("立即检查归档") { sync.retryNow() }
                    Button("断开此 Mac", role: .destructive) { sync.disconnect() }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Mac 归档").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $scan) {
                NavigationStack {
                    QRScanner { result in
                        scan = false
                        switch result { case .success(let text): accept(text); case .failure(let e): error = e.localizedDescription }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("扫描 Mac 二维码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { scan = false } } }
                }
            }
        }.preferredColorScheme(.light)
    }
    private func accept(_ text: String) {
        do { guard let url = URL(string: text) else { throw ArchiveFailure.unpaired }; try sync.accept(url); link = ""; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let completion: (Result<String,Error>) -> Void
    func makeUIViewController(context: Context) -> QRScannerController { let c = QRScannerController(); c.completion = completion; return c }
    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) { }
    static func dismantleUIViewController(_ uiViewController: QRScannerController, coordinator: ()) { uiViewController.stop() }
}
private final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var completion: ((Result<String,Error>) -> Void)?
    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "glimpse.qr.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var completed = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: capture); layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer); preview = layer
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { finish(.failure(NSError(domain: "Glimpse", code: 1, userInfo: [NSLocalizedDescriptionKey:"请在系统设置允许相机，或粘贴 Mac 配对链接。 "]))); return }
            queue.async { [self] in
                do {
                    guard let camera = AVCaptureDevice.default(for: .video) else { throw ArchiveFailure.invalid }
                    let input = try AVCaptureDeviceInput(device: camera)
                    let output = AVCaptureMetadataOutput()
                    capture.beginConfiguration()
                    guard capture.canAddInput(input), capture.canAddOutput(output) else { capture.commitConfiguration(); throw ArchiveFailure.invalid }
                    capture.addInput(input); capture.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                    capture.commitConfiguration(); capture.startRunning()
                } catch { DispatchQueue.main.async { self.finish(.failure(error)) } }
            }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func stop() { queue.async { [capture] in capture.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = objects.first as? AVMetadataMachineReadableCodeObject, let text = code.stringValue else { return }
        finish(.success(text))
    }
    private func finish(_ result: Result<String,Error>) { guard !completed else { return }; completed = true; stop(); completion?(result) }
}

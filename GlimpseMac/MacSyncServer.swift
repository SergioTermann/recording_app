import Foundation
import Network
import SwiftUI
import Darwin

@MainActor
final class MacSyncServer: ObservableObject {
    @Published private(set) var status = "正在启动本地归档…"
    @Published private(set) var receiving = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastReceived: Date?
    @Published private(set) var pair: PairConfiguration?
    @Published private(set) var available = false
    private var listener: NWListener?
    private var connection: LocalConnection?
    private var worker: Task<Void,Never>?
    private var receiver: ArchiveReceiver?
    private let library: MacLibrary
    init(library: MacLibrary) { self.library = library; start() }
    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GLIMPSE_TEST_ROOT"] != nil || Bundle.main.bundleIdentifier?.hasSuffix(".uitest") == true { status = "独立测试资料库"; return }
        #endif
        guard listener == nil else { return }
        do {
            let pair = try PairKeychain.read() ?? PairConfiguration.create()
            try PairKeychain.save(pair); self.pair = pair
            receiver = try ArchiveReceiver(root: library.archiveRoot)
            let listener = try NWListener(using: pair.parameters(), on: NWEndpoint.Port(rawValue: 49743)!)
            listener.service = NWListener.Service(name: pair.serverID.uuidString, type: PairConfiguration.serviceType)
            listener.newConnectionHandler = { [weak self] raw in Task { @MainActor in self?.accept(raw) } }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.available = true; self.status = "等待 iPhone · 同一 Wi-Fi 自动归档"
                        if var updated = self.pair {
                            updated.host = Self.localAddress(); updated.port = listener.port?.rawValue
                            self.pair = updated
                            try? PairKeychain.save(updated)
                        }
                    case .failed(let error): self.available = false; self.status = "本地连接未启动：\(error.localizedDescription)"; self.listener?.cancel(); self.listener = nil
                    case .waiting: self.status = "请允许 Glimpse 访问本地网络"
                    default: break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: DispatchQueue(label: "glimpse.listener"))
        } catch { status = error.localizedDescription }
    }
    private static func localAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        defer { freeifaddrs(pointer) }
        var cursor = pointer
        var addresses: [(String,String)] = []
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if PairConfiguration.localIPv4(value) { addresses.append((name,value)) }
            }
        }
        return addresses.sorted { $0.0 < $1.0 }.first?.1
    }
    func resetPairing() {
        worker?.cancel(); connection?.cancel(); listener?.cancel(); listener = nil
        PairKeychain.remove(); pair = nil; available = false; start()
    }
    private func accept(_ raw: NWConnection) {
        guard worker == nil, let receiver else { raw.cancel(); return }
        let socket = LocalConnection(raw); connection = socket
        worker = Task { [weak self] in
            guard let self else { return }
            defer { socket.cancel(); self.connection = nil; self.worker = nil; self.receiving = false }
            do {
                try await socket.start()
                self.receiving = true; self.status = "iPhone 已安全连接"
                try await receiver.run(socket) { [self] name,bytes,total in
                    await MainActor.run { self.status = "正在接收 \(name) 的录音"; self.progress = Double(bytes)/Double(max(1,total)) }
                } committed: { [self] in
                    await MainActor.run { self.lastReceived = Date(); self.library.refresh() }
                }
                self.progress = 1; self.status = "已归档 · 等待新的录音"
            } catch {
                try? await socket.send(SyncPacket(kind: "error", message: error.localizedDescription))
                self.status = "等待重连 · 未完成文件不会进入档案"
            }
        }
    }
}

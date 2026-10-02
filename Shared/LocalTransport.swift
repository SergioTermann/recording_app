@preconcurrency import Foundation
import Network
import Security

struct PairConfiguration: Codable, Equatable {
    let serverID: UUID
    let secret: Data
    var host: String? = nil
    var port: UInt16? = nil
    static let serviceType = "_glimpse-sync._tcp"
    var pairingURL: String {
        var value = "quickrecord://pair?id=\(serverID.uuidString)&key=\(secret.map { String(format: "%02x", $0) }.joined())"
        if let host, let port { value += "&host=\(host)&port=\(port)" }
        return value
    }
    static func localIPv4(_ host: String) -> Bool {
        let raw = host.split(separator: ".", omittingEmptySubsequences: false)
        let pieces = raw.compactMap { UInt8($0) }
        guard raw.count == 4, pieces.count == 4 else { return false }
        return pieces[0] == 10 || (pieces[0] == 192 && pieces[1] == 168) || (pieces[0] == 172 && (16...31).contains(pieces[1])) || (pieces[0] == 169 && pieces[1] == 254)
    }
    static func parse(_ url: URL) throws -> Self {
        guard url.scheme == "quickrecord", url.host == "pair", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:)),
              let text = components.queryItems?.first(where: { $0.name == "key" })?.value,
              text.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw ArchiveFailure.unpaired }
        var key = Data(); var index = text.startIndex
        for _ in 0..<32 { let end = text.index(index, offsetBy: 2); key.append(UInt8(text[index..<end], radix: 16)!); index = end }
        let host = components.queryItems?.first(where: { $0.name == "host" })?.value
        let port = components.queryItems?.first(where: { $0.name == "port" })?.value.flatMap(UInt16.init)
        if let host { guard localIPv4(host), let port, port > 0 else { throw ArchiveFailure.unpaired } }
        return Self(serverID: id, secret: key, host: host, port: port)
    }
    static func create() throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ArchiveFailure.unpaired }
        return Self(serverID: UUID(), secret: Data(bytes))
    }
    func parameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        // A random 256-bit out-of-band QR secret authenticates BOTH endpoints.
        // No anonymous TLS, HTTP, certificate bypass, or six-digit network password.
        let key = secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(serverID.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        return parameters
    }
}

enum PairKeychain {
    static let service = "com.zinger.glimpse.local-pairing"
    static func read() -> PairConfiguration? {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"pair", kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PairConfiguration.self, from: data)
    }
    static func save(_ pair: PairConfiguration) throws {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"pair"]
        let data = try JSONEncoder().encode(pair)
        let values: [String: Any] = [kSecValueData as String:data, kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(q.merging(values) { _,new in new } as CFDictionary, nil) == errSecSuccess else { throw ArchiveFailure.unpaired }
        } else if status != errSecSuccess { throw ArchiveFailure.unpaired }
    }
    static func remove() {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"pair"] as CFDictionary)
    }
}

struct SyncPacket: Codable {
    var kind: String
    var version: Int = 1
    var offer: ArchiveOffer?
    var data: Data?
    var needsAudio: Bool?
    var message: String?
}

private final class Once<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ value: Result<Value, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: value)
    }
}

/// One request/response in flight per connection. Each operation has a deadline;
/// cancelling closes the socket and wakes a pending receive.
final class LocalConnection: @unchecked Sendable {
    let raw: NWConnection
    private let queue = DispatchQueue(label: "glimpse.tls.connection")
    init(_ raw: NWConnection) { self.raw = raw }
    func cancel() { raw.cancel() }
    func start() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = Once(continuation)
                let deadline = DispatchWorkItem { [raw] in raw.cancel(); once.finish(.failure(ArchiveFailure.interrupted)) }
                raw.stateUpdateHandler = { state in
                    switch state {
                    case .ready: deadline.cancel(); once.finish(.success(()))
                    case .failed(let error): deadline.cancel(); once.finish(.failure(error))
                    case .cancelled: deadline.cancel(); once.finish(.failure(ArchiveFailure.interrupted))
                    default: break
                    }
                }
                queue.asyncAfter(deadline: .now()+12, execute: deadline)
                raw.start(queue: queue)
            }
        } onCancel: { self.cancel() }
    }
    func send(_ packet: SyncPacket) async throws {
        let payload = try JSONEncoder().encode(packet)
        guard payload.count <= 6*1024*1024 else { throw ArchiveFailure.invalid }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(payload)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = Once(continuation)
                let deadline = DispatchWorkItem { [raw] in raw.cancel(); once.finish(.failure(ArchiveFailure.interrupted)) }
                queue.asyncAfter(deadline: .now()+30, execute: deadline)
                raw.send(content: frame, completion: .contentProcessed { error in
                    deadline.cancel()
                    if let error { once.finish(.failure(error)) } else { once.finish(.success(())) }
                })
            }
        } onCancel: { self.cancel() }
    }
    func receive() async throws -> SyncPacket {
        let header = try await receiveExactly(4)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= 6*1024*1024 else { throw ArchiveFailure.protocolError }
        let packet = try JSONDecoder().decode(SyncPacket.self, from: await receiveExactly(count))
        guard packet.version == 1 else { throw ArchiveFailure.protocolError }
        if packet.kind == "error" { throw NSError(domain: "Glimpse", code: 1, userInfo: [NSLocalizedDescriptionKey:packet.message ?? "传输未完成"]) }
        return packet
    }
    private func receiveExactly(_ count: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let once = Once<Data>(continuation)
                let deadline = DispatchWorkItem { [raw] in raw.cancel(); once.finish(.failure(ArchiveFailure.interrupted)) }
                queue.asyncAfter(deadline: .now()+40, execute: deadline)
                raw.receive(minimumIncompleteLength: count, maximumLength: count) { data,_,_,error in
                    deadline.cancel()
                    if let error { once.finish(.failure(error)) }
                    else if let data, data.count == count { once.finish(.success(data)) }
                    else { once.finish(.failure(ArchiveFailure.interrupted)) }
                }
            }
        } onCancel: { self.cancel() }
    }
}

actor ArchiveReceiver {
    let repository: ArchiveRepository
    init(root: URL) throws { repository = try ArchiveRepository(root: root) }
    func run(_ connection: LocalConnection, progress: @escaping @Sendable (String, Int64, Int64) async -> Void, committed: @escaping @Sendable () async -> Void) async throws {
        defer { repository.abort() }
        repository.reload()
        var offered: ArchiveOffer?
        var receiving = false
        var count: Int64 = 0
        while !Task.isCancelled {
            let packet = try await connection.receive()
            switch packet.kind {
            case "offer":
                guard offered == nil, let offer = packet.offer else { throw ArchiveFailure.protocolError }
                let need = try repository.needsAudio(offer)
                offered = offer; receiving = need; count = 0
                if need { try repository.begin(offer) }
                await progress(offer.deviceName, 0, offer.byteCount)
                try await connection.send(SyncPacket(kind: "need", needsAudio: need))
            case "chunk":
                guard receiving, let offer = offered, let data = packet.data else { throw ArchiveFailure.protocolError }
                try repository.append(data); count += Int64(data.count)
                await progress(offer.deviceName, count, offer.byteCount)
            case "commit":
                guard let offer = offered else { throw ArchiveFailure.protocolError }
                if receiving { _ = try repository.finish() } else { try repository.updateText(offer) }
                offered = nil; receiving = false
                await committed()
                try await connection.send(SyncPacket(kind: "ack"))
            case "done":
                guard offered == nil else { throw ArchiveFailure.protocolError }
                try await connection.send(SyncPacket(kind: "done")); return
            default: throw ArchiveFailure.protocolError
            }
        }
        throw CancellationError()
    }
}

actor ArchiveSender {
    func send(offers: [(ArchiveOffer, URL)], through connection: LocalConnection, progress: @escaping @Sendable (Int, Int, Double) async -> Void) async throws {
        for (index, pair) in offers.enumerated() {
            try Task.checkCancellation()
            let (offer, url) = pair
            try await connection.send(SyncPacket(kind: "offer", offer: offer))
            let reply = try await connection.receive()
            guard reply.kind == "need", let needed = reply.needsAudio else { throw ArchiveFailure.protocolError }
            if needed {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var sent: Int64 = 0
                while let chunk = try handle.read(upToCount: 256*1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    try await connection.send(SyncPacket(kind: "chunk", data: chunk))
                    sent += Int64(chunk.count)
                    await progress(index, offers.count, Double(sent)/Double(offer.byteCount))
                }
            }
            try await connection.send(SyncPacket(kind: "commit"))
            guard try await connection.receive().kind == "ack" else { throw ArchiveFailure.protocolError }
            await progress(index+1, offers.count, 0)
        }
        try await connection.send(SyncPacket(kind: "done"))
        guard try await connection.receive().kind == "done" else { throw ArchiveFailure.protocolError }
    }
}

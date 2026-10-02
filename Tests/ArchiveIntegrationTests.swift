import Foundation
import Network

private struct TestFailure: Error { let message: String }
private func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try value() else { throw TestFailure(message: message) }
}
private func expectFailure(_ body: () throws -> Void, _ name: String) throws {
    do { try body() } catch { return }; throw TestFailure(message: name)
}
@main struct ArchiveIntegrationTests {
    static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("glimpse-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let audio=Data((0..<760001).map { UInt8($0%251) })
        let file=root.appendingPathComponent("fixture.m4a");try audio.write(to:file)
        let id=UUID(),device=UUID()
        func offer(text:String?="虚构测试：明天画一个浇水工具草图。",hash:String?=nil,bytes:Int64?=nil,category:String="idea") -> ArchiveOffer {
            ArchiveOffer(recordingID:id,deviceID:device,deviceName:"合成测试设备",category:category,date:Date(timeIntervalSince1970:1700000000),day:"2023-11-15",duration:42,byteCount:bytes ?? Int64(audio.count),audioHash:hash ?? ArchiveOffer.digest(audio),transcript:text)
        }
        let repo=try ArchiveRepository(root:root.appendingPathComponent("archive"))
        try repo.begin(offer(text:nil));try repo.append(audio.prefix(200000))
        try check(repo.receipts.isEmpty,"Partial file must not become an archive")
        repo.abort();try check(repo.receipts.isEmpty,"Abort must not commit")
        try repo.begin(offer(text:nil))
        for offset in stride(from:0,to:audio.count,by:256*1024) { try repo.append(audio.subdata(in:offset..<min(offset+256*1024,audio.count))) }
        let committed=try repo.finish()
        try check(try Data(contentsOf:committed)==audio,"Audio content must be identical")
        try check(try !repo.needsAudio(offer()),"Duplicate must skip audio upload")
        try repo.updateText(offer())
        let txt=committed.deletingPathExtension().appendingPathExtension("txt")
        try check(try String(contentsOf:txt,encoding:.utf8)==offer().transcript,"Late transcript must arrive")
        try "Mac 手动编辑内容".write(to:txt,atomically:true,encoding:.utf8)
        try repo.updateText(offer(text:"新的手机版文字"))
        try check(try String(contentsOf:txt,encoding:.utf8)=="Mac 手动编辑内容","Never overwrite local edits")
        try check(try String(contentsOf:committed.deletingLastPathComponent().appendingPathComponent("recording.phone.txt"),encoding:.utf8)=="新的手机版文字","Keep incoming conflict copy")
        try expectFailure({try offer(category:"../../escape").validate()},"Reject path traversal")
        try expectFailure({ _ = try repo.needsAudio(offer(hash:String(repeating:"0",count:64))) },"Reject changed audio identity")
        let broken=try ArchiveRepository(root:root.appendingPathComponent("broken"))
        try broken.begin(offer(hash:String(repeating:"0",count:64)))
        for offset in stride(from:0,to:audio.count,by:256*1024) { try broken.append(audio.subdata(in:offset..<min(offset+256*1024,audio.count))) }
        try expectFailure({_ = try broken.finish()},"Reject corrupt audio")
        try check(broken.receipts.isEmpty,"No receipt for corruption")
        try broken.begin(offer());try broken.append(audio.prefix(100))
        try expectFailure({_ = try broken.finish()},"Reject short file")
        let reloaded=try ArchiveRepository(root:root.appendingPathComponent("archive"))
        try check(reloaded.receipts.count==1,"Receipt persists across restart")
        try check(reloaded.receipts.values.first!.1.offer.date==offer().date,"Original date persists")
        print("PASS: atomic archive, interrupted cleanup, checksums, duplicate skip, late transcript, edit conflicts, path validation, persistent metadata")
        try check(PairConfiguration.localIPv4("192.168.5.5"), "Accept LAN address")
        try check(!PairConfiguration.localIPv4("192.168.extra.5.5"), "Reject malformed LAN host")
        try check(!PairConfiguration.localIPv4("8.8.8.8"), "Reject public direct-connect host")
        let pair=try PairConfiguration.create()
        try check(try PairConfiguration.parse(URL(string:pair.pairingURL)!)==pair,"QR credential round trip")
        try await transport(pair:pair,clientPair:pair,offer:offer(),file:file,root:root.appendingPathComponent("encrypted"),succeed:true)
        let wrong=PairConfiguration(serverID:pair.serverID,secret:Data(repeating:42,count:32))
        try await transport(pair:pair,clientPair:wrong,offer:offer(),file:file,root:root.appendingPathComponent("wrong-key"),succeed:false)
        print("PASS: real TLS-PSK multi-chunk transfer and wrong-key rejection")
    }
    static func transport(pair:PairConfiguration,clientPair:PairConfiguration,offer:ArchiveOffer,file:URL,root:URL,succeed:Bool) async throws {
        let listener=try NWListener(using:pair.parameters(),on:.any)
        let stream=AsyncStream<LocalConnection>.makeStream()
        listener.newConnectionHandler={ raw in stream.continuation.yield(LocalConnection(raw)) }
        listener.stateUpdateHandler = { print("Listener:", $0) }
        listener.start(queue:DispatchQueue(label:"test.listener"))
        defer { listener.cancel();stream.continuation.finish() }
        for _ in 0..<100 { if let port = listener.port, port.rawValue > 0 { break };try await Task.sleep(for:.milliseconds(50)) }
        guard let port=listener.port else { throw TestFailure(message:"Listener failed") }
        print("Port:",port.rawValue)
        let receiver=try ArchiveReceiver(root:root)
        let worker=Task {
            for await connection in stream.stream {
                defer{connection.cancel()}
                do {try await connection.start();try await receiver.run(connection,progress:{_,_,_ in},committed:{});return true}
                catch{print("Receiver error:",error);return false}
            }
            return false
        }
        let client=LocalConnection(NWConnection(host:"127.0.0.1",port:port,using:clientPair.parameters()))
        defer {client.cancel();worker.cancel()}
        var passed=false
        do {
            try await client.start()
            try await ArchiveSender().send(offers:[(offer,file)],through:client,progress:{_,_,_ in})
            passed=true
        } catch { if succeed { throw error } }
        try check(passed==succeed,"Authentication expectation mismatch")
        if succeed {
            let received = await worker.value
            try check(received,"Receiver did not finish")
            let repository=try ArchiveRepository(root:root)
            try check(try !repository.needsAudio(offer),"Encrypted transfer did not create a valid archive")
        }
    }
}

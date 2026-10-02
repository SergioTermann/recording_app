import Foundation
@MainActor private final class NoSpeech:SpeechRecognizing {
    func transcribe(url:URL,language:String,update:@escaping @MainActor(String,String)->Void) async throws -> String {throw SpeechFailure.noSpeech}
}
@main struct MarkdownPersistenceTests {
    @MainActor static func main() async throws {
        func check(_ value:Bool,_ message:String) throws {if !value{throw NSError(domain:"MarkdownPersistence",code:1,userInfo:[NSLocalizedDescriptionKey:message])}}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("markdown-persistence-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let recording=Recording(url:root.appendingPathComponent("fixture.m4a"),date:Date(),duration:1)
        try Data().write(to:recording.url)
        let store=TranscriptionStore(engine:NoSpeech());store.reload([recording])
        try store.saveEditedText("原始文字",for:recording)
        let doc=MarkdownDocument(recording:recording,store:store)
        try check(doc.text=="原始文字","Existing transcript opens")
        let revised="# 灵感💡\n\n- [ ] 写下 **重点**\n\n```swift\nlet x = 1\n```"
        doc.edit(revised)
        try check(FileManager.default.fileExists(atPath:recording.markdownDraftURL.path),"Draft immediately durable")
        let recovering=MarkdownDocument(recording:recording,store:store)
        try check(recovering.text==revised && recovering.dirty,"Recover unfinished draft after restart")
        try await Task.sleep(for:.milliseconds(1000))
        try check(!doc.dirty,"Autosave completes")
        let md=try String(contentsOf:recording.markdownURL,encoding:.utf8)
        let txt=try String(contentsOf:recording.transcriptURL,encoding:.utf8)
        try check(md==revised && txt==revised && store.items[recording.url]?.text==revised,"MD TXT and transcript stay consistent")
        try check(!FileManager.default.fileExists(atPath:recording.markdownDraftURL.path),"Successful save clears recovery draft")
        let reopened=MarkdownDocument(recording:recording,store:store)
        try check(reopened.text==revised,"Reopen persisted Markdown")
        doc.edit("");doc.save()
        try check(try String(contentsOf:recording.markdownURL,encoding:.utf8)=="","Explicitly clearing a document persists")
        print("PASS: existing transcript migration, immediate crash-recovery draft, autosave, exact Markdown persistence, reload, empty document")
    }
}

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

extension Recording {
    var markdownURL: URL { url.deletingPathExtension().appendingPathExtension("md") }
    var markdownDraftURL: URL { url.deletingPathExtension().appendingPathExtension("markdown-draft.json") }
}

@MainActor
final class MarkdownDocument: ObservableObject {
    @Published private(set) var text: String
    @Published private(set) var dirty = false
    @Published private(set) var status = "Markdown · 已保存"
    @Published private(set) var error: String?
    let recording: Recording
    private let store: TranscriptionStore
    private var pending: Task<Void,Never>?
    private var subscription: AnyCancellable?
    private struct Draft: Codable { let text: String }

    init(recording:Recording, store:TranscriptionStore) {
        self.recording=recording;self.store=store
        // The transcript remains canonical for phone imports; .md is its native
        // editing/export companion. A crash-recovery draft always wins on reopening.
        let current=store.items[recording.url]?.text ?? (try? String(contentsOf:recording.transcriptURL,encoding:.utf8)) ?? ""
        if let data=try? Data(contentsOf:recording.markdownDraftURL),let draft=try? JSONDecoder().decode(Draft.self,from:data) {
            text=draft.text;dirty=true;status="已恢复未保存草稿"
        } else { text=current }
        if !dirty, store.items[recording.url]?.status == .complete {
            do { try text.write(to:recording.markdownURL,atomically:true,encoding:.utf8) }
            catch { self.error=error.localizedDescription;status="Markdown 副本保存失败" }
        }
        subscription=store.$items.receive(on:DispatchQueue.main).sink { [weak self] items in
            guard let self,!self.dirty,let item=items[recording.url],item.status == .complete,item.text != self.text else{return}
            self.text=item.text
            do {try item.text.write(to:recording.markdownURL,atomically:true,encoding:.utf8);self.status="转写已更新 · Markdown 已保存"}
            catch{self.error=error.localizedDescription;self.status="Markdown 副本保存失败"}
        }
    }
    func edit(_ value:String) {
        guard value != text else{return}
        text=value;dirty=true;error=nil;status="正在保存…"
        // Recovery is written immediately, not after the autosave timer.
        do {try JSONEncoder().encode(Draft(text:value)).write(to:recording.markdownDraftURL,options:.atomic)}
        catch{self.error=error.localizedDescription;status="草稿保存失败，请勿关闭窗口"}
        pending?.cancel()
        pending=Task { [weak self] in
            do {try await Task.sleep(for:.milliseconds(800));self?.save()}
            catch{}
        }
    }
    func save() {
        pending?.cancel();pending=nil
        guard dirty else{return}
        do {
            try text.write(to:recording.markdownURL,atomically:true,encoding:.utf8)
            try store.saveEditedText(text,for:recording)
            try? FileManager.default.removeItem(at:recording.markdownDraftURL)
            dirty=false;error=nil;status="Markdown · 已自动保存"
        } catch {self.error=error.localizedDescription;status="保存失败 · 草稿保留"}
    }
}

@MainActor
final class MarkdownEditorBridge: ObservableObject {
    weak var view: NSTextView?
    func apply(_ action:MarkdownAction) {
        guard let view else{return}
        let (next,selection)=action.apply(to:view.string,selection:view.selectedRange())
        let all=NSRange(location:0,length:(view.string as NSString).length)
        guard view.shouldChangeText(in:all,replacementString:next) else{return}
        view.textStorage?.replaceCharacters(in:all,with:next)
        view.didChangeText();view.setSelectedRange(selection);view.scrollRangeToVisible(selection)
        view.window?.makeFirstResponder(view)
    }
    func undo() {view?.undoManager?.undo()}
    func redo() {view?.undoManager?.redo()}
}

private final class MarkdownTextView: NSTextView {
    var format: ((MarkdownAction)->Void)?
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        let flags=event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command,let key=event.charactersIgnoringModifiers?.lowercased() {
            let action:MarkdownAction?=key == "b" ? .bold : key == "i" ? .italic : key == "k" ? .link : nil
            if let action {format?(action);return true}
        }
        return super.performKeyEquivalent(with:event)
    }
}

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text:String
    @ObservedObject var bridge:MarkdownEditorBridge
    func makeCoordinator() -> Coordinator {Coordinator(self)}
    func makeNSView(context:Context) -> NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        let view=MarkdownTextView(frame:.zero)
        view.isRichText=false;view.importsGraphics=false;view.allowsUndo=true;view.isEditable=true;view.isSelectable=true
        view.isAutomaticQuoteSubstitutionEnabled=false;view.isAutomaticDashSubstitutionEnabled=false
        view.isAutomaticTextReplacementEnabled=false;view.isAutomaticLinkDetectionEnabled=false
        view.isContinuousSpellCheckingEnabled=false;view.isGrammarCheckingEnabled=false
        view.font=NSFont.monospacedSystemFont(ofSize:16,weight:.regular);view.textColor = .labelColor
        view.backgroundColor = .white;view.drawsBackground=true
        view.textContainerInset=NSSize(width:28,height:24)
        view.minSize=NSSize(width:0,height:0);view.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask=[.width]
        view.textContainer?.widthTracksTextView=true;view.textContainer?.containerSize=NSSize(width:0,height:CGFloat.greatestFiniteMagnitude)
        let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=7;paragraph.paragraphSpacing=4
        view.defaultParagraphStyle=paragraph
        view.setAccessibilityIdentifier("macMarkdownEditor");view.setAccessibilityLabel("Markdown 正文编辑区")
        view.string=text;view.delegate=context.coordinator
        view.format={ [weak bridge] action in bridge?.apply(action) }
        scroll.documentView=view;bridge.view=view;context.coordinator.view=view
        context.coordinator.highlight()
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        context.coordinator.parent=self
        guard let view=scroll.documentView as? NSTextView else{return}
        bridge.view=view
        if view.string != text,!view.hasMarkedText() {
            let selected=view.selectedRange();view.string=text
            view.setSelectedRange(NSRange(location:min(selected.location,(text as NSString).length),length:0))
            context.coordinator.highlight()
        }
    }
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:MarkdownSourceEditor
        weak var view:NSTextView?
        private var work:DispatchWorkItem?
        init(_ parent:MarkdownSourceEditor){self.parent=parent}
        func textDidChange(_ notification:Notification) {
            guard let view,!view.hasMarkedText() else{return}
            parent.text=view.string
            work?.cancel();let next=DispatchWorkItem{[weak self] in self?.highlight()};work=next
            DispatchQueue.main.asyncAfter(deadline:.now()+0.12,execute:next)
        }
        func highlight() {
            guard let view,!view.hasMarkedText(),let storage=view.textStorage else{return}
            let source=view.string as NSString;let range=NSRange(location:0,length:source.length)
            guard source.length <= 250_000 else{return} // Keep long transcripts responsive.
            let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=7;paragraph.paragraphSpacing=4
            storage.beginEditing()
            storage.setAttributes([.font:NSFont.monospacedSystemFont(ofSize:16,weight:.regular),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph],range:range)
            func style(_ pattern:String,_ attrs:[NSAttributedString.Key:Any]) {
                guard let regex=try? NSRegularExpression(pattern:pattern,options:[.anchorsMatchLines]) else{return}
                for match in regex.matches(in:view.string,range:range){storage.addAttributes(attrs,range:match.range)}
            }
            let wine=NSColor(srgbRed:0.40,green:0.12,blue:0.19,alpha:1)
            style(#"^#{1,6}\s+.*$"#,[.foregroundColor:wine,.font:NSFont.monospacedSystemFont(ofSize:20,weight:.semibold)])
            style(#"\*\*[^\n]+?\*\*|__[^\n]+?__"#,[.font:NSFont.monospacedSystemFont(ofSize:16,weight:.bold)])
            style(#"(?<!\*)\*[^*\n]+\*(?!\*)"#,[.foregroundColor:NSColor.secondaryLabelColor])
            style(#"^\s*(?:[-*+] |\d+[.)] |> ).*$"#,[.foregroundColor: NSColor(srgbRed:0.24,green:0.32,blue:0.35,alpha:1)])
            style(#"\[[^\]\n]+\]\([^)\n]+\)"#,[.foregroundColor:wine])
            style(#"`[^`\n]+`|^\s*```.*$"#,[.foregroundColor:NSColor.systemBrown,.backgroundColor:NSColor.black.withAlphaComponent(0.035)])
            storage.endEditing()
            view.typingAttributes=[.font:NSFont.monospacedSystemFont(ofSize:16,weight:.regular),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph]
        }
    }
}

struct MarkdownPreview:View {
    let source:String
    private var blocks:[MarkdownBlock]{MarkdownBlocks.parse(source)}
    private func inline(_ text:String) -> Text {
        if let value=try? AttributedString(markdown:text,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace)){return Text(value)}
        return Text(text)
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if source.isEmpty {Text("写下第一行，预览会在这里呈现。").foregroundStyle(.tertiary)}
                ForEach(blocks) { block in
                    switch block.kind {
                    case .heading(let level):inline(block.text).font(.system(size:level == 1 ? 30 : level == 2 ? 24 : 19,weight:.semibold)).padding(.top,level<3 ? 12 : 4)
                    case .paragraph:inline(block.text).lineSpacing(7)
                    case .bullet:HStack(alignment:.top,spacing:12){Text("•").foregroundStyle(.secondary);inline(block.text).lineSpacing(5)}.padding(.leading,8)
                    case .ordered(let label):HStack(alignment:.top,spacing:12){Text(label).foregroundStyle(.secondary);inline(block.text).lineSpacing(5)}.padding(.leading,8)
                    case .task(let checked):HStack(alignment:.top,spacing:10){Image(systemName:checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? Color.accentColor : .secondary);inline(block.text).strikethrough(checked).lineSpacing(5)}.padding(.leading,8)
                    case .quote:HStack(spacing:14){RoundedRectangle(cornerRadius:2).fill(Color.accentColor.opacity(0.35)).frame(width:3);inline(block.text).foregroundStyle(.secondary).lineSpacing(6).frame(maxWidth:.infinity,alignment:.leading)}.fixedSize(horizontal:false,vertical:true).padding(.vertical,4)
                    case .code(let language):VStack(alignment:.leading,spacing:8){if !language.isEmpty {Text(language.uppercased()).font(.caption2).foregroundStyle(.secondary)};ScrollView(.horizontal){Text(block.text).font(.system(size:14,design:.monospaced)).fixedSize(horizontal:true,vertical:false)}}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.black.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
                    case .rule:Divider().padding(.vertical,8)
                    case .table:ScrollView(.horizontal){Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:12){ForEach(Array(block.rows.enumerated()),id:\.offset){index,row in GridRow {ForEach(Array(row.enumerated()),id:\.offset){_,cell in inline(cell).fontWeight(index == 0 ? .semibold : .regular)}};if index == 0 {Divider().gridCellColumns(max(1,row.count))}}}.padding(14).background(Color.black.opacity(0.025),in:RoundedRectangle(cornerRadius:8))}
                    }
                }
                Spacer(minLength:40)
            }.font(.system(size:16)).frame(maxWidth:.infinity,alignment:.leading).padding(32).textSelection(.enabled)
        }.background(.white).accessibilityIdentifier("markdownPreview")
        .environment(\.openURL,OpenURLAction { url in
            guard ["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") else{return .discarded}
            return .systemAction
        })
    }
}

struct MarkdownExport:FileDocument {
    static var readableContentTypes:[UTType]{[UTType(filenameExtension:"md") ?? .plainText]}
    var text:String
    init(text:String){self.text=text}
    init(configuration:ReadConfiguration) throws {text=String(data:configuration.file.regularFileContents ?? Data(),encoding:.utf8) ?? ""}
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper {FileWrapper(regularFileWithContents:Data(text.utf8))}
}

struct MacMarkdownWorkspace:View {
    let recording:Recording
    @ObservedObject var library:MacLibrary
    @ObservedObject var store:TranscriptionStore
    @StateObject private var document:MarkdownDocument
    @StateObject private var bridge=MarkdownEditorBridge()
    @State private var mode="编辑"
    @State private var exporting=false
    init(recording:Recording,library:MacLibrary) {
        self.recording=recording;self.library=library;self.store=library.transcripts
        _document=StateObject(wrappedValue:MarkdownDocument(recording:recording,store:library.transcripts))
    }
    private var textBinding:Binding<String>{Binding(get:{document.text},set:{document.edit($0)})}
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:14) {
                VStack(alignment:.leading,spacing:5) {
                    Text(recording.date.formatted(.dateTime.year().month().day().hour().minute())).font(.headline)
                    HStack(spacing:6){Label(recording.folder.rawValue,systemImage:recording.folder.icon);Text("·");Text(timeString(recording.duration));Text(library.isImported(recording) ? "· 来自 iPhone" : "· Mac 录音")}.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(library.playing == recording.url ? "停止回听" : "回听",systemImage:library.playing == recording.url ? "stop.fill" : "play.fill"){library.play(recording)}.disabled(library.isRecording).buttonStyle(.borderless)
                Menu {
                    Button("导出 Markdown…"){exporting=true}
                    ShareLink("导出录音",item:recording.url)
                    Button("在 Finder 中显示"){library.reveal(recording.url)}
                    Button("复制 Markdown"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(document.text,forType:.string)}
                } label:{Image(systemName:"square.and.arrow.up").frame(width:22)}.menuStyle(.borderlessButton).frame(width:28).help("导出与分享")
                Button("保存"){document.save()}.keyboardShortcut("s",modifiers:.command).disabled(!document.dirty).accessibilityIdentifier("saveMarkdown")
            }.padding(.horizontal,28).padding(.vertical,18)
            Divider()
            HStack(spacing:3) {
                ForEach(MarkdownAction.allCases,id:\.rawValue) {action in
                    Button{bridge.apply(action)}label:{Image(systemName:action.symbol).frame(width:29,height:28)}.buttonStyle(.plain).help(action.title).accessibilityLabel(action.title).disabled(mode == "预览")
                }
                Divider().frame(height:20).padding(.horizontal,8)
                Button{bridge.undo()}label:{Image(systemName:"arrow.uturn.backward").frame(width:26,height:28)}.buttonStyle(.plain).help("撤销")
                Button{bridge.redo()}label:{Image(systemName:"arrow.uturn.forward").frame(width:26,height:28)}.buttonStyle(.plain).help("重做")
                Spacer(minLength:16)
                Picker("显示模式",selection:$mode){Text("编辑").tag("编辑");Text("双栏").tag("双栏");Text("预览").tag("预览")}.labelsHidden().pickerStyle(.segmented).frame(width:176).accessibilityIdentifier("markdownMode")
            }.padding(.horizontal,22).padding(.vertical,10)
            Divider()
            if let error=document.error {Text("\(document.status)：\(error)").font(.caption).foregroundStyle(.red).padding(12)}
            if store.items[recording.url]?.status != .complete,document.text.isEmpty {
                HStack {Text(store.items[recording.url]?.detail ?? "可以直接输入 Markdown，或先识别录音。").font(.caption).foregroundStyle(.secondary);Spacer();if store.items[recording.url] == nil || store.items[recording.url]?.status == .failed {Button("转写录音"){store.enqueue(recording)}}}.padding(.horizontal,28).padding(.vertical,10)
            }
            GeometryReader { geometry in
                HStack(spacing:0) {
                    Spacer(minLength:0)
                    Group {
                        if mode == "双栏" {
                            HSplitView {
                                MarkdownSourceEditor(text:textBinding,bridge:bridge).frame(minWidth:250)
                                MarkdownPreview(source:document.text).frame(minWidth:250)
                            }
                        } else if mode == "预览" {MarkdownPreview(source:document.text)}
                        else {MarkdownSourceEditor(text:textBinding,bridge:bridge)}
                    }
                    .frame(width:mode == "双栏" ? max(500,geometry.size.width-40) : min(840,max(360,geometry.size.width-64)))
                    .background(.white).clipShape(RoundedRectangle(cornerRadius:5))
                    .overlay(RoundedRectangle(cornerRadius:5).stroke(Color.black.opacity(0.045)))
                    Spacer(minLength:0)
                }.padding(.vertical,22)
            }.background(Color(red:0.97,green:0.966,blue:0.958))
            Divider()
            HStack {
                Image(systemName:document.error == nil ? (document.dirty ? "circle.dotted" : "checkmark.circle") : "exclamationmark.circle")
                Text(document.status)
                Spacer()
                Text("\(document.text.count) 字符")
                Text("·").padding(.horizontal,4)
                Text("Markdown").fontWeight(.medium)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,10)
        }
        .onDisappear{document.save()}
        .fileExporter(isPresented:$exporting,document:MarkdownExport(text:document.text),contentType:UTType(filenameExtension:"md") ?? .plainText,defaultFilename:"\(recording.folder.rawValue) \(recording.date.formatted(.iso8601.year().month().day())).md") {result in
            if case .failure(let error)=result {library.error=error.localizedDescription}
        }
    }
}

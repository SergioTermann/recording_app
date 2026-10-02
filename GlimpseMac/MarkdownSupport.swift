import Foundation

/// UTF-16 ranges match NSTextView, including selections containing emoji or Chinese.
enum MarkdownAction: String, CaseIterable {
    case heading, bold, italic, bullet, task, quote, code, link
    var title: String {
        switch self {
        case .heading: return "标题"; case .bold: return "粗体"; case .italic: return "斜体"
        case .bullet: return "列表"; case .task: return "待办"; case .quote: return "引用"
        case .code: return "代码块"; case .link: return "链接"
        }
    }
    var symbol: String {
        switch self {
        case .heading: return "textformat.size"; case .bold: return "bold"; case .italic: return "italic"
        case .bullet: return "list.bullet"; case .task: return "checklist"; case .quote: return "text.quote"
        case .code: return "curlybraces"; case .link: return "link"
        }
    }
    func apply(to text: String, selection: NSRange) -> (String, NSRange) {
        let ns = text as NSString
        let range = NSRange(location: min(selection.location, ns.length), length: min(selection.length, max(0, ns.length - selection.location)))
        let selected = ns.substring(with: range)
        switch self {
        case .bold, .italic, .link, .code:
            let prefix: String, suffix: String, placeholder: String
            switch self {
            case .bold: prefix = "**"; suffix = "**"; placeholder = "粗体文字"
            case .italic: prefix = "*"; suffix = "*"; placeholder = "斜体文字"
            case .link: prefix = "["; suffix = "](https://)"; placeholder = "链接文字"
            default:
                let fence = selected.contains("```") ? "````" : "```"
                let before = range.location == 0 || ns.substring(with: NSRange(location: range.location-1, length: 1)) == "\n"
                let end = NSMaxRange(range)
                let after = end == ns.length || ns.substring(with: NSRange(location: end, length: 1)) == "\n"
                prefix = (before ? "" : "\n") + fence + "\n"
                suffix = "\n" + fence + (after ? "\n" : "\n")
                placeholder = "在这里写代码"
            }
            let inner = selected.isEmpty ? placeholder : selected
            return (ns.replacingCharacters(in: range, with: prefix+inner+suffix), NSRange(location: range.location+(prefix as NSString).length,length: (inner as NSString).length))
        default:
            var linesRange = ns.lineRange(for: range)
            // A selection ending at the next line's beginning should not format that line.
            if range.length > 0, NSMaxRange(range) <= ns.length, ns.substring(with: NSRange(location:NSMaxRange(range)-1,length:1)) == "\n" {
                linesRange = ns.lineRange(for: NSRange(location:range.location,length:range.length-1))
            }
            let block = ns.substring(with: linesRange)
            var lines = block.components(separatedBy: "\n")
            let trailing = lines.last == "" && block.hasSuffix("\n")
            if trailing { lines.removeLast() }
            let prefix = self == .heading ? "## " : self == .bullet ? "- " : self == .task ? "- [ ] " : "> "
            lines = lines.map { prefix + $0 }
            let replacement = lines.joined(separator:"\n") + (trailing ? "\n" : "")
            return (ns.replacingCharacters(in:linesRange,with:replacement), NSRange(location:linesRange.location,length:(replacement as NSString).length))
        }
    }
}

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable { case heading(Int), paragraph, bullet, ordered(String), task(Bool), quote, code(String), rule, table }
    let id: Int
    let kind: Kind
    let text: String
    var rows: [[String]] = []
}

enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n")
        var result: [MarkdownBlock] = []; var index = 0
        func add(_ kind: MarkdownBlock.Kind, _ text: String, rows: [[String]] = []) { result.append(MarkdownBlock(id:result.count,kind:kind,text:text,rows:rows)) }
        func cells(_ line:String) -> [String] {
            var parts=line.trimmingCharacters(in:.whitespaces).components(separatedBy:"|")
            if parts.first?.trimmingCharacters(in:.whitespaces).isEmpty == true { parts.removeFirst() }
            if parts.last?.trimmingCharacters(in:.whitespaces).isEmpty == true { parts.removeLast() }
            return parts.map{$0.trimmingCharacters(in:.whitespaces)}
        }
        func matches(_ pattern:String,_ text:String) -> Bool { text.range(of:pattern,options:.regularExpression) != nil }
        func isBlockStart(_ line:String) -> Bool {
            let t=line.trimmingCharacters(in:.whitespaces)
            return t.isEmpty || matches(#"^(#{1,6}\s|[-*+]\s|\d+[.)]\s|>|`{3,}|~{3,}|(?:-{3,}|\*{3,}|_{3,})$)"#,t)
        }
        while index < lines.count {
            let line=lines[index];let trimmed=line.trimmingCharacters(in:.whitespaces)
            if trimmed.isEmpty { index += 1;continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let char=trimmed.first!;let fence=String(trimmed.prefix(while:{$0==char}))
                let language=String(trimmed.dropFirst(fence.count)).trimmingCharacters(in:.whitespaces)
                index += 1; var code:[String]=[]
                while index<lines.count {
                    let candidate=lines[index].trimmingCharacters(in:.whitespaces)
                    if candidate.count>=fence.count && candidate.allSatisfy({$0==char}) { index += 1;break }
                    code.append(lines[index]);index += 1
                }
                add(.code(language),code.joined(separator:"\n"));continue
            }
            if matches(#"^#{1,6}\s"#,trimmed) {
                let level=trimmed.prefix(while:{$0=="#"}).count
                add(.heading(level),String(trimmed.dropFirst(level)).trimmingCharacters(in:.whitespaces));index += 1;continue
            }
            if matches(#"^(?:-{3,}|\*{3,}|_{3,})$"#,trimmed) {add(.rule,"");index += 1;continue}
            if index+1<lines.count, trimmed.contains("|"), !cells(lines[index+1]).isEmpty,
               cells(lines[index+1]).allSatisfy({matches(#"^:?-{3,}:?$"#,$0)}) {
                var rows=[cells(line)];index += 2
                while index<lines.count,lines[index].contains("|"),!lines[index].trimmingCharacters(in:.whitespaces).isEmpty {rows.append(cells(lines[index]));index += 1}
                add(.table,"",rows:rows);continue
            }
            if matches(#"^[-*+] \[[ xX]\]\s?"#,trimmed) {
                add(.task(trimmed.dropFirst(3).first?.lowercased()=="x"),String(trimmed.dropFirst(5)).trimmingCharacters(in:.whitespaces));index += 1;continue
            }
            if matches(#"^[-*+]\s"#,trimmed) {add(.bullet,String(trimmed.dropFirst(2)));index += 1;continue}
            if let range=trimmed.range(of:#"^\d+[.)]\s+"#,options:.regularExpression) {
                let label=String(trimmed[range]).trimmingCharacters(in:.whitespaces)
                add(.ordered(label),String(trimmed[range.upperBound...]));index += 1;continue
            }
            if trimmed.hasPrefix(">") {
                var quote:[String]=[]
                while index<lines.count,lines[index].trimmingCharacters(in:.whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in:.whitespaces).dropFirst()).trimmingCharacters(in:.whitespaces));index += 1
                }
                add(.quote,quote.joined(separator:"\n"));continue
            }
            var paragraph=[line];index += 1
            while index<lines.count,!isBlockStart(lines[index]) {
                if index+1<lines.count,lines[index].contains("|"),cells(lines[index+1]).allSatisfy({matches(#"^:?-{3,}:?$"#,$0)}) {break}
                paragraph.append(lines[index]);index += 1
            }
            add(.paragraph,paragraph.joined(separator:"\n"))
        }
        return result
    }
}

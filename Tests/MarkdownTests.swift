import Foundation
@main struct MarkdownTests {
    static func main() throws {
        func check(_ value:Bool,_ name:String) throws { if !value {throw NSError(domain:"MarkdownTest",code:1,userInfo:[NSLocalizedDescriptionKey:name])} }
        let text="灵感💡：明天开始"
        let range=(text as NSString).range(of:"💡")
        let (bold, selected)=MarkdownAction.bold.apply(to:text,selection:range)
        try check(bold=="灵感**💡**：明天开始","Unicode formatting")
        try check((bold as NSString).substring(with:selected)=="💡","UTF16 selection")
        let (list,_)=MarkdownAction.task.apply(to:"第一项\n第二项\n第三项",selection:NSRange(location:0,length:8))
        try check(list=="- [ ] 第一项\n- [ ] 第二项\n第三项","Line selection ending with newline")
        let (code,_)=MarkdownAction.code.apply(to:"内含```代码",selection:NSRange(location:0,length:7))
        try check(code.hasPrefix("````\n"),"Nested fence must not prematurely close code")
        let doc="""
        # 灵感
        正文 **加粗** 和 [链接](https://example.com)。

        ## 待办
        - [ ] 画草图
        - [x] 整理文字
        1. 第一步
        > 保留原始想法

        ```swift
        let idea = "💡"
        # 代码里不是标题
        ```

        | 事项 | 状态 |
        | --- | :---: |
        | 归档 | 已完成 |

        ---
        """
        let blocks=MarkdownBlocks.parse(doc)
        try check(blocks.contains(where:{$0.kind == .heading(1)}),"heading")
        try check(blocks.contains(where:{$0.kind == .task(false) && $0.text=="画草图"}),"unchecked task")
        try check(blocks.contains(where:{$0.kind == .task(true)}),"checked task")
        try check(blocks.contains(where:{$0.kind == .code("swift") && $0.text.contains("# 代码里不是标题")}),"fenced code")
        try check(blocks.contains(where:{$0.kind == .table && $0.rows.count==2}),"table")
        try check(blocks.contains(where:{$0.kind == .rule}),"horizontal rule")
        try check(MarkdownBlocks.parse("<script>alert(1)</script>")[0].kind == .paragraph,"HTML remains plain text")
        print("PASS: Markdown formatting, Unicode selections, multiline boundaries, nested fences, preview headings/lists/tasks/code/tables, inert HTML")
    }
}

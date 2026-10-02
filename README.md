# Glimpse · iPhone 与 Mac 的声音档案

## Mac 1.1 / iPhone 1.6.2：Markdown 写作工作区与纯图形图标

电脑版以文稿编辑为主：左侧紧凑的分类与文稿列表，中间大幅 Markdown 编辑区，录音收进工具栏。选择录音直接编辑，支持标题、粗体、斜体、列表、待办、引用、代码块、链接的快捷插入与语法着色，提供「编辑 / 双栏 / 预览」。预览支持常见块级语法、表格与行内格式；原始 HTML 按文本显示，不执行脚本、不加载远程图片。此内置预览覆盖常用 Markdown 子集，不是完整 CommonMark/GFM 引擎。

输入后约 0.8 秒自动保存；Cmd-S 立即保存。原样保留 Markdown 语法到同目录 `.md` 与原 TXT，同时更新转写状态及每日总结源文。每次输入立即保存恢复草稿，自动保存成功后清理；切换文稿保存，意外退出后恢复草稿。输入法组词期间不落入半成品。导出菜单支持独立 `.md` 文件。现有录音文字可直接打开，原始录音不变。

图标更换为深海蓝珐琅、古金钢笔尖、放射雕纹和装饰艺术边框；**图标内没有任何文字或字母缩写**。Mac 和 iPhone 均已安装此版资源。

验证：Markdown Unicode/UTF-16 选区、跨行格式、代码围栏、预览标题/列表/待办/代码/表格测试通过；独立 Mac 持久化测试验证即时恢复草稿、自动保存、MD/TXT/状态一致、重新打开和清空文字。实际 Mac UI 验证大编辑区输入、自动保存、重启保留和双栏预览；文件移动测试包含 `.md` 与草稿副本。图标检查了大图及 180/120/60 像素预览，两端签名构建通过。

新增实现：`GlimpseMac/MarkdownEditor.swift`、`GlimpseMac/MarkdownSupport.swift`；测试位于 `Tests/MarkdownTests.swift` 与 `Tests/MarkdownPersistenceTests.swift`。图标源稿 `scripts/render-icon.py`，当前资源 `design/AppIcon-glimpse-deco.png`。


## Mac 1.0.1 / iPhone 1.6.1：局域网自动归档与桌面文字编辑

Mac 应用已安装在 `~/Applications/Glimpse.app`。Mac 界面包含全部录音、日常记录、idea、手机归档和每日总结；支持 Mac 录音、播放、文字识别、搜索、文字编辑、TXT/音频导出和 Finder 定位。原生 macOS 目标为 `GlimpseMac`，支持 macOS 14 及以上；macOS 26 使用本机 SpeechTranscriber，旧版本使用本机 SFSpeechRecognizer（需要系统语言资源支持）。

### 自动归档

1. 两台设备连接同一局域网，Mac 打开 Glimpse → 连接手机 → 显示配对二维码。
2. iPhone 打开 Glimpse → Mac 归档 → 扫描 Mac 配对二维码，允许相机及本地网络权限。
3. 配对后，两端打开 App 时自动归档所有未归档录音与完成的文字稿。手机原文件保留；后台或锁屏可能暂停，回到前台自动重试。
4. 如 Bonjour 发现受网络影响，可使用新版二维码包含的局域网 IP，或在手机配对页输入 Mac 页面显示的 IP。默认端口 TCP 49743。若 IP 改变且 Bonjour 不可用，需重新扫码或输入新 IP。

归档路径：`~/Documents/Glimpse/手机归档/YYYY-MM-DD/日常记录或idea/设备ID_录音ID/`。每条包含 `recording.m4a`、已有的 `recording.txt`、文字状态文件及 `archive.json`。保留录音开始日期、时长和首次归档分类；之后的手机分类调整和删除不会改动已有 Mac 档案。Mac 自录文件位于 `~/Documents/Glimpse/Mac 录音/分类/`。

- 录音和文字仅在局域网传输。二维码承载随机 256 位配对密钥，存于两端钥匙串；TLS 1.2 PSK + AES-GCM 双向认证与加密。未提供明文或关闭校验的后门。不要公开配对二维码；可在 Mac 重置配对。
- Bonjour `_glimpse-sync._tcp` 自动发现，禁用蜂窝和点对点接口；同一 Wi-Fi 的访客隔离、VPN 或防火墙可能影响连接。Mac 需保持 App 运行、电脑唤醒。
- 每次接收先写隐藏临时目录，校验字节数与 SHA-256 后原子提交，落盘后才回复完成。连接中断仅重传未完成文件，已归档音频校验后跳过，不会生成重复副本。
- 录音后续完成识别时，文字会自动补传。Mac 已修改文字不会被手机版本覆盖，手机新版另存 `recording.phone.txt`。这是从手机到 Mac 的归档，不是双向编辑同步。
- 当前每条录音最大 4 GiB、文字最大 4 MiB；超过限制明确报错。单次只接受一个已配对客户端会话。

### 编辑文字与每日总结

在 Mac 选中录音，点击右侧 **编辑文字**，修改后点 **保存文字并更新 TXT**。没有识别结果时也能手动补写；保存会停止该条正在进行的识别，避免迟到结果覆盖人工编辑。切换记录时，未保存草稿在当前运行期间保留。退出前需保存。

每日总结复用手机端的日期分组、缓存和 DeepSeek 处理。Mac 的 API Key 需要在「每日总结 → 连接 DeepSeek」单独填写，存于 Mac 钥匙串；手机密钥不会随档案传输。Mac 开启 AI 后会发送本机已结束日期的文字到 DeepSeek。Mac 休眠或退出时不会执行，运行时每分钟检查并在下次启动补齐。文档位于 `~/Documents/Glimpse/每日总结/`。

### 验证与构建

- 两端签名构建通过。共享转写与每日总结回归测试通过（模拟器跳过真实中文识别）；新增手动编辑优先、外部文字补传重新加载测试通过。
- `Tests/ArchiveIntegrationTests.swift` 覆盖原子归档、中断清理、摘要校验、重复跳过、补传文字、本地编辑冲突、路径校验、重启恢复；真实 TLS 分块传输通过，错误密钥被拒绝。
- 用户 iPhone 向 Mac 的真实局域网归档已完成 1 条，接收文件字节数和 SHA-256 与手机一致。
- Mac 实际 UI 测试在独立虚构资料库完成：打开编辑、修改、保存，检查 TXT 和文字状态文件一致。没有修改用户日记。Mac 实际麦克风录音与真实中文识别尚未单独做真机声学测试。
- 图标统一为酒红珐琅、旧金卷草和细密珠边，原生脚本绘制，未调用图像生成 API；预览 `preview/app-icon.png`。此历史图标已由 1.1 / 1.6.2 纯图形钢笔尖版替代。

```sh
xcodebuild -project QuickRecord.xcodeproj -scheme GlimpseMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM=YOUR_TEAM build
xcrun swiftc -swift-version 5 -parse-as-library Shared/ArchiveCore.swift \
  Shared/LocalTransport.swift Tests/ArchiveIntegrationTests.swift -o /tmp/glimpse-archive-tests
/tmp/glimpse-archive-tests
```

调试目标支持 `GLIMPSE_TEST_ROOT` 隔离资料库，且禁用网络接收；Release 不包含此环境变量入口。源码包不包含密钥、用户录音、配对凭证或构建产物。


## 1.5.3：古董珐琅牌图标

采用象牙白底、酒红椭圆珐琅牌、旧金绳纹镶边与立体手写 G。项目原生 Python 材质脚本绘制，未调用图像生成 API；检查了 180/120/60 像素预览。安装资源为 1024×1024 不透明 RGB PNG。源稿 `scripts/render-icon.py`，图标 `design/AppIcon-glimpse-locket.png`，预览 `preview/app-icon.png`。上一版星芒脚本存档于 `design/render-icon-jewel.py`。

## 1.5.2：酒红珐琅珠宝图标

按用户选定的复古珠宝方向重绘：酒红珐琅底、旧金星芒镶座、石榴红弧面宝石及细雕纹。采用项目原生 Python 材质绘制（Pillow、NumPy、SciPy），未使用图像生成 API。已检查 180/120/60 像素预览，安装资源为 1024×1024 不透明 RGB PNG。源稿 `scripts/render-icon.py`，图标 `design/AppIcon-glimpse-jewel.png`，预览 `preview/app-icon.png`。上一版存档于 `design/AppIcon-green-crest.png`。

## 1.5.1：Glimpse 与新图标

App 更名为 Glimpse，更新桌面名称、首页标题、权限提示、快捷指令说明和文件位置说明。沿用现有应用标识与数据目录，覆盖安装保留录音、总结、钥匙串及操作按钮绑定。

图标重绘为墨绿皮革、旧金 Baskerville G 字徽记、月桂枝与雕花椭圆边框。使用项目原生 Python 绘制脚本与材质渲染，无图像生成 API 调用；检查了 180/120/60 像素预览，最终资源为 1024×1024 不透明 RGB PNG。源稿 `scripts/render-icon.py`，图标 `design/AppIcon-glimpse.png`，预览 `preview/app-icon.png`。

## 1.5：按日期自动 AI 每日总结

首页新增「每日总结」。进入后点「连接 DeepSeek」，在手机上填入自己的 API Key，并点「保存密钥并开启自动 AI 总结」。先通过 DeepSeek 模型列表验证凭证和模型权限，再存入此设备钥匙串；不要将密钥放入源码或发送到聊天。可在同一入口断开并删除本机密钥。

每天结束后，把已转写的日常记录和 idea 交给 DeepSeek 提炼「今日重点 / 生活记录 / idea / 明确待办」，并附当天完整原文。生成的 UTF-8 TXT 位于「文件 → 我的 iPhone → Glimpse → 每日总结 / YYYY-MM-DD 每日总结.txt」，App 内支持按日期查看、复制、分享导出。

- 仅发送文字、分类和来源时间到 `https://api.deepseek.com/chat/completions`，不发送音频。当前模型为官方文档列出的 `deepseek-flash`，非思考模式。按用户 DeepSeek 账户计费；长文本会分段总结再合并，可能产生多次调用。禁止 HTTP 重定向，使用无缓存临时网络会话。
- iOS 决定后台执行时间，不能保证 00:00 准时运行。BGAppRefresh 最早在次日 00:01 申请运行，返回前台会补齐；App 保持前台跨午夜时也会检查。系统拒绝后台刷新、强退、断网或任务到期均可能延后生成。
- 日期按录音开始时间归档，包括跨午夜的长录音。归档时区固定为首次使用总结功能时的设备时区，页面会显示，避免旅行时历史日期漂移。
- 当天不生成最终日报，没有录音的日期不生成空文档。首次启用也处理已有历史日期。旧录音尚未识别时，在允许自动转写且 App 位于前台时加入转写队列；识别失败的录音需要在原录音入口重试。
- 部分文字缺失时，先生成明确标注「AI 总结待生成」的原文文档；全部转写完成后再请求 AI，避免将缺失内容当作完整总结。
- 根据原文指纹缓存模型结果，内容未变化时不重复调用；编辑文字、移动分类或删除录音后重新生成。删除一天全部录音时清理本功能生成的对应文档，不删除该目录中用户自己的其他文件。已分享出去的副本不随之更新。
- API 失败、余额不足、限流、空回复或截断回复不保存为完成状态，显示重试入口。任务取消后不发布半截结果。AI 结果仍可能有误，重要信息须对照文档末尾原文。

新增实现：`DailySummary.swift`（日期分组、文档和状态、AI 缓存及界面）、`DailySummaryAI.swift`（DeepSeek 调用和钥匙串连接）、`DailySummaryScheduler.swift`（系统后台刷新）。

验证：6 项每日总结测试通过，覆盖午夜和夏令时边界、两类记录、待转写状态、缓存/编辑更新、失败重试、取消、文件清理以及分段完整性；3 项 UI 测试通过，覆盖每日文档和连接入口、分享导出、录音回归及文字编辑。模型逻辑测试使用模拟响应；2026-09-29 已在用户 iPhone 15 Pro Max 上完成真实 DeepSeek 模型权限验证与虚构记录总结测试，四个总结章节验证通过。用户授权的密钥已保存至设备钥匙串，一次性传输文件已删除。真机测试不读取用户日记；凭证不包含在源码或安装包中。后台午夜触发受系统调度限制，未宣称已验证准时执行。

复现模拟器 UI 测试前运行 `python3 scripts/seed-daily-summary-test.py` 和 `python3 scripts/seed-transcript-test.py`。它们只在模拟器准备合成数据，不写入手机或读取用户日记。

接口依据：[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion)。

## 1.4.3：石墨与钛金属图标

图标采用哑光石墨面板、凹入圆形底座、拉丝钛金属声波与暗红指示灯。通过高度场法线、方向光、柔和投影、接触阴影和细微表面纹理绘制材质，移除霓虹光环和轨道。检查了桌面小尺寸预览，图标为 1024×1024 不透明 RGB PNG。当前源稿为 `scripts/render-icon.py`，预览为 `preview/app-icon.png`；上一版保存在 `design/AppIcon-neon.png` 和 `design/render-icon-neon.py`。App 内白色主题保持不变。

## 1.4.2：科幻声波核心

桌面图标重绘为深空蓝底、冰蓝声波、青紫渐变光环与倾斜轨道。使用程序绘制光照、柔光与曲面，输出 1024×1024 不透明 PNG；检查了 180/120/60 像素预览。App 内保持白色主题。

当前设计源为 `scripts/render-icon.py`；预览为 `preview/app-icon.png`；安装资源为 `QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。`design/AppIcon-paper.svg` 和 `design/render-icon-paper.py` 保留上一版便签设计，仅作历史存档。

## 1.4.1：声音便签图标

重新设计桌面图标：暖白底色、珊瑚红折角便签、白色声波，采用轻渐变与柔和阴影。应用图标为 1024×1024 不透明 PNG，由 iOS 裁切圆角；附 180/120/60 像素预览检查。

设计源稿：`design/AppIcon.svg`；渲染脚本：`scripts/render-icon.py`（Pillow + NumPy）；安装资源：`QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png`；预览：`preview/app-icon.png`。本次采用程序绘制，未调用图像生成 API。

## 1.4：白色主题

首页移除右上角设置按钮和 App 内设置页。主界面、录音文字及编辑页面统一使用浅色外观：白色背景、浅灰卡片、深色文字和橙红色操作按钮。保持 1.3.1 的紧凑录音卡片，以及分类保存、手机麦克风录音和自动转文字功能。系统麦克风或语音权限异常时，仍可从错误提示进入 iOS 系统设置处理。

下方为历次版本说明；旧版本提到的 App 内设置入口在 1.4 已移除。

## 1.3.1：紧凑录音卡片

缩小录音卡片的计时字号、波形高度与上下间距，整体高度减少约三分之一。录音按钮仍有 76 点点击区域，首页能显示更多录音列表。

## 1.3：日常记录 / idea 分类保存

- 首页移除「长按一下，就开始」设置卡片，右上角仍可查看设置。
- 在「保存到」选择「日常记录」或「idea」。停止录音前可以切换，录音和识别文字保存到对应的真实文件夹。
- App 记住上次的文件夹；使用操作按钮启动录音时也沿用该选择。
- 录音列表只显示当前文件夹。录音右侧「…」可将录音连同 TXT、识别状态移到另一个文件夹。
- 旧版本录音首次启动时归入「日常记录」。迁移保留原文件内容，遇到同名文件时生成新文件名，不覆盖已有文件。
- 在「文件 → 我的 iPhone → Glimpse → Recordings」里可看到「日常记录」和「idea」两个文件夹。

验证：分类迁移、录音与文字一起移动、同名保护测试通过；录音期间切换到 idea、停止保存、回放、重启保留文件夹，以及文字查看编辑导出 UI 测试通过。

## 1.2：固定使用手机麦克风

录音前启用音频会话，显式选择 `.builtInMic`，并检查实际输入路由。录音会话不启用蓝牙 HFP 输入；连接有线或蓝牙耳机时仍选择手机麦克风。录音启动后再检查一次输入，系统音频路由变化时重新选择并校验；不能切回内置麦克风时停止并保存、显示错误，不以耳机麦克风继续录音。

主界面显示「iPhone 内置麦克风」。回放使用系统播放路由，不强制改变耳机回放偏好。系统路由变化通知存在响应延迟，不能承诺在硬件切换的瞬间完全没有音频间隙。

真机输入路由测试通过，实际返回「iPhone麦克风」且端口类型为 `.builtInMic`；模拟器路由测试也通过。尚未逐一验证不同型号蓝牙耳机、有线耳机的插拔场景。

## 1.1：自动转文字与 TXT 导出

- 默认开启「停止录音后自动转文字」，识别普通话。录音保存后在前台排队识别，完成后自动生成 UTF-8 `.txt` 文件。
- 在录音下方点「文字」，可查看、复制、修改识别结果，或通过「导出 TXT」存入文件、发送到其他 App。修改并保存会同步更新 TXT。
- 「文件 → 浏览 → 我的 iPhone → Glimpse → Recordings」中可找到录音和对应 TXT。卸载前请备份重要内容。
- 以前的录音不会擅自批量处理，点「转文字」即可识别。识别失败时保留原录音，可点「重新识别」。
- 在右上角设置里可关闭自动转文字；已排队任务仍会继续。
- iOS 26 及以上优先使用系统 SpeechTranscriber，本机处理长录音，首次可能需下载中文模型。其他受支持系统使用 SFSpeechRecognizer，并强制设备端识别，按 45 秒分段；分段边界可能影响个别词语。不支持本机中文模型时会提示，绝不静默改为上传录音。
- 请在文字生成期间保持 App 在前台。离开 App、锁屏或开始新录音时暂停，返回后从该条录音开头重试。尚未完成的文字不会作为完整 TXT 导出。
- 识别结果可能有误，重要内容请对照原录音核对。目前不包含说话人区分、翻译或摘要。

新增源码：`Transcription.swift`（本机识别、任务排队、状态与 TXT 持久化）、`TranscriptView.swift`（查看、编辑、复制、导出）。

新增验证：3 项转写状态/持久化测试通过；3 项 UI 测试通过（含原录音回归、文字编辑、复制、系统分享）。模拟器界面样本通过 `python3 scripts/seed-transcript-test.py` 准备，样本文字用于 UI 测试，不代表真实识别结果。真机识别测试使用系统合成的固定中文语音，不读取用户录音。

2026-09-29，iPhone 15 Pro Max / iOS 26.6.2 真机识别测试通过。系统 SpeechTranscriber 对约 9 秒固定中文样本返回：「今天天气很好 ，我们下午 3点开会讨论项目进度 ，请记得带上电脑。」该测试验证了本机中文识别引擎，不能据此保证任意口音、噪声或长录音的准确率。

为 iPhone 15 Pro Max 制作的原生 SwiftUI 录音 App，支持 iOS 17 及以上。

**长按操作按钮 → 运行快捷指令 → 打开Glimpse并开始录音。** 首次需要麦克风授权，锁屏启动可能需要先解锁。App 使用公开系统接口，不能接管双击锁屏键、全局音量键或更改操作按钮的系统触发手势。

## 安装到 iPhone

1. 在 Mac 上打开 `QuickRecord.xcodeproj`。
2. 用数据线连接 iPhone，解锁并信任这台 Mac。
3. 在 Xcode 的 Settings → Accounts 中登录自己的 Apple ID。
4. 选择 QuickRecord 项目 → QuickRecord target → Signing & Capabilities，选择自己的 Team。若提示 Bundle Identifier 冲突，将 `com.zinger.quickrecord` 改为自己的唯一标识。
5. 选择这台 iPhone 为运行目标，点击 Run。按系统提示在 iPhone 上开启开发者模式、重启并信任开发者。
6. 打开Glimpse，录一小段并停止，完成麦克风授权。

个人免费开发签名通常需要每 7 天用 Xcode 重新签名安装；长期分发需对应的 Apple 开发者签名方式。源码工程不是可直接点开安装的 IPA。

## 绑定 iPhone 15 Pro Max 的操作按钮

1. 打开手机上的「快捷指令」，新建快捷指令。
2. 添加「Glimpse → 开始录音」，将快捷指令命名为「Glimpse录音」。
3. 打开「设置 → 操作按钮」，滑到「快捷指令」。
4. 点「选取快捷指令」，选择「Glimpse录音」。
5. **长按左侧音量键上方的操作按钮**，按系统要求解锁后开始录音。
6. 开始后可以锁屏继续录制。回到 App 点「停止并保存」结束；再次触发开始指令不会停止或覆盖当前录音。

如果搜索不到 App 动作，先打开Glimpse一次。也可在快捷指令中添加「URL」动作，值为 `quickrecord://record`，后接「打开 URL」动作。

若只需系统录音功能，无须安装本 App：iPhone 的「设置 → 操作按钮 → 语音备忘录」已经支持长按开始录音。

## 已实现

- AAC / M4A 单声道录音、计时和输入音量显示。
- 停止后自动保存，列表按时间倒序排列，支持回放、系统分享导出、确认后删除。
- App Intent「开始录音」和 URL 启动入口。
- 录音开始后允许后台音频，文件配置为打开期间可在锁屏后继续写入。
- 麦克风拒绝授权提示、来电中断保存、编码失败提示。
- 录音和转写在本机保存，无第三方依赖；启用 AI 每日总结后，转写文字会发送到 DeepSeek。设备系统备份可能包含文件；卸载 App 会删除本地录音。

## 验证

2026-09-29 验证结果：模拟器 Debug 构建和真机 Release 构建成功；两项 UI 测试均通过。已使用本机现有个人开发签名安装至用户 iPhone 15 Pro Max（iOS 26.6.2），并通过设备工具成功启动。

当前个人签名有效期至 **2026-10-06 12:59（新加坡时间）**，到期需重新签名安装。麦克风首次授权、手机上的快捷指令选择、操作按钮绑定及实际锁屏行为需要在手机上完成和验证。

Xcode 27 的 Siri 自然语言训练步骤输出 `Could not archive SSU artifacts`，但构建成功且 App Intent 动作元数据已生成。真机快捷指令动作的发现情况尚未确认；如搜索不到，可使用下方文档所述 URL 入口。URL 入口在首次调用时也可能显示系统「打开」确认。

```sh
xcodebuild -project QuickRecord.xcodeproj -scheme QuickRecord \
  -sdk iphonesimulator -configuration Debug -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project QuickRecord.xcodeproj -scheme QuickRecord \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

UI 自动化覆盖录音计时、停止保存、播放、重启后文件仍存在和设置说明。模拟器不能验证实体操作按钮、真实锁屏录音和来电打断，安装真机后还需检查这些行为。

## 代码入口

- `QuickRecordApp.swift`：App 生命周期、快捷指令和 URL 入口。
- `Recorder.swift`：麦克风权限、音频会话、录制、文件管理、回放。
- `ContentView.swift`：中文界面及操作按钮设置引导。
- `Info.plist`：麦克风说明、后台音频、URL scheme。

苹果文档：[操作按钮使用指南](https://support.apple.com/guide/iphone/use-and-customize-the-action-button-iphe89d61d66/ios)、[轻点背面](https://support.apple.com/en-us/111772)。

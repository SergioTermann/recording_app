# Glimpse · A Voice Archive for iPhone and Mac

A native SwiftUI app for recording, on-device Mandarin transcription, Markdown editing, and local-network archiving. Supports iOS 17 or later and macOS 14 or later. Optional AI daily summaries use DeepSeek.

The app interface currently uses Chinese labels. English labels in the instructions below describe their Chinese equivalents; on-disk folder names remain unchanged.

## Mac 1.1 / iPhone 1.6.2: Markdown Workspace and an Icon Without Lettering

The Mac app now centers on writing: a compact category and document list on the left, a spacious Markdown editor in the middle, and recording controls in the toolbar. Select a recording to edit its transcript directly. The editor offers shortcuts and syntax highlighting for headings, bold, italic, lists, tasks, quotes, code blocks, and links, with Edit, Split, and Preview modes. Preview supports common block syntax, tables, and inline formatting. Raw HTML is displayed as text; scripts are not executed and remote images are not loaded. The built-in renderer supports a common Markdown subset, rather than the full CommonMark or GFM specification.

Changes are saved automatically about 0.8 seconds after typing; Cmd-S saves immediately. Markdown syntax is preserved in both a companion `.md` file and the original TXT file, while transcription state and daily-summary source text are updated. Each edit immediately writes a recovery draft, which is cleared after a successful autosave. Switching documents saves changes, and drafts can be recovered after an unexpected exit. In-progress input-method composition is not saved as incomplete text. The export menu supports standalone `.md` files. Existing transcripts open directly, and original audio remains unchanged.

The icon now features deep blue enamel, an antique gold fountain-pen nib, radial engraving, and an Art Deco border. **It contains no text or initials.** Both Mac and iPhone assets have been updated.

Recorded validation: tests passed for Unicode/UTF-16 selections, multiline formatting, code fences, and preview rendering of headings, lists, tasks, code, and tables. Separate Mac persistence tests covered immediate recovery drafts, autosave, consistency across MD/TXT/state files, reopening, and clearing text. Mac UI checks covered typing in the expanded editor, autosave, persistence after relaunch, and split preview. File-move tests included `.md` files and draft copies. Icon checks covered full-size and 180/120/60-pixel previews; signed builds passed on both platforms.

Implementation: `GlimpseMac/MarkdownEditor.swift` and `GlimpseMac/MarkdownSupport.swift`. Tests: `Tests/MarkdownTests.swift` and `Tests/MarkdownPersistenceTests.swift`. Icon source: `scripts/render-icon.py`; current artwork: `design/AppIcon-glimpse-deco.png`.

## Mac 1.0.1 / iPhone 1.6.1: Automatic LAN Archiving and Desktop Transcript Editing

The development installation placed the Mac app at `~/Applications/Glimpse.app`. The Mac interface includes All Recordings, Daily Notes, idea, Phone Archive, and Daily Summaries. It supports recording, playback, transcription, search, text editing, TXT/audio export, and revealing files in Finder. The native macOS target is `GlimpseMac`, supporting macOS 14 or later. macOS 26 uses on-device SpeechTranscriber; earlier supported versions use on-device SFSpeechRecognizer and require system language resources.

### Automatic Archiving

1. Connect both devices to the same local network. On the Mac, open Glimpse → Connect Phone → Show Pairing QR Code.
2. On the iPhone, open Glimpse → Mac Archive → Scan Mac Pairing QR Code. Grant camera and local-network permissions.
3. Once paired, unarchived recordings and completed transcripts are archived automatically while both apps are open. Original files remain on the phone. Transfers may pause in the background or when locked and retry when the app returns to the foreground.
4. If Bonjour discovery is unavailable, use the LAN IP included in the newer QR code, or enter the IP shown on the Mac into the phone's pairing screen. The default port is TCP 49743. If the IP changes and Bonjour is unavailable, scan again or enter the new IP.

Archive layout: `~/Documents/Glimpse/手机归档/YYYY-MM-DD/<category>/<deviceID>_<recordingID>/`, where the category is `日常记录` or `idea`. Each entry contains `recording.m4a`, `recording.txt` when available, a transcript state file, and `archive.json`. The recording's start date, duration, and category at initial archive time are preserved. Later category changes or deletions on the phone do not alter existing Mac archives. Recordings made on the Mac are stored under `~/Documents/Glimpse/Mac 录音/<category>/`.

- Audio and transcripts transfer only over the local network. The QR code carries a random 256-bit pairing key stored in each device's Keychain. TLS 1.2 PSK with AES-GCM provides mutual authentication and encryption. There is no plaintext fallback or verification bypass. Keep pairing QR codes private; pairing can be reset on the Mac.
- Bonjour discovery uses `_glimpse-sync._tcp`; cellular and peer-to-peer interfaces are disabled. Guest-network isolation, VPNs, or firewalls may affect connectivity. The Mac must remain awake with the app running.
- Incoming files are written to a hidden temporary directory, checked for byte count and SHA-256, and committed atomically. Completion is acknowledged only after persistence. After an interruption, only incomplete files are retransmitted; verified audio already in the archive is skipped without creating duplicates.
- Transcripts are transferred automatically when transcription finishes later. Phone updates do not overwrite text edited on the Mac; the incoming version is saved separately as `recording.phone.txt`. This is phone-to-Mac archiving, not bidirectional editing synchronization.
- Each recording is currently limited to 4 GiB of audio and 4 MiB of text. Exceeding a limit produces an explicit error. Only one paired client session is accepted at a time.

### Transcript Editing and Daily Summaries

In this release, select a recording on the Mac, click **Edit Text**, then **Save Text and Update TXT**. Text can also be entered manually when no transcript exists. Saving stops any transcription in progress for that recording so that a late result cannot overwrite manual edits. Unsaved drafts survive switching between recordings within the current session; save before quitting. Mac 1.1 introduces the autosave workflow described above.

Daily summaries reuse the phone's date grouping, cache, and DeepSeek processing. Enter the Mac's API key separately under Daily Summaries → Connect DeepSeek. It is stored in the Mac Keychain; the phone's key is not transferred with archives. When AI is enabled, the Mac sends local transcript text for completed days to DeepSeek. Processing does not run while the Mac is asleep or the app is closed. While running, the app checks once per minute and catches up on the next launch. Documents are stored in `~/Documents/Glimpse/每日总结/`.

### Validation and Build

- Signed builds passed on both platforms. Shared transcription and daily-summary regression tests passed, with real Mandarin recognition skipped on the simulator. Tests for manual-edit precedence and reloading subsequently received transcripts also passed.
- `Tests/ArchiveIntegrationTests.swift` covers atomic archiving, interruption cleanup, digest verification, duplicate skipping, later transcript transfers, local-edit conflicts, path validation, and restart recovery. Real TLS chunked transfer passed; an incorrect key was rejected.
- One real iPhone-to-Mac LAN archive transfer completed, with matching byte counts and SHA-256 hashes on both devices.
- Mac UI testing used an isolated synthetic library to open, edit, and save text and verify consistency between TXT and transcript state. No personal diary was modified. Actual Mac microphone recording and Mandarin recognition have not yet received a separate end-to-end acoustic test on physical hardware.
- This release used a burgundy enamel icon with antique gold scrollwork and a beaded border, rendered by project scripts without an image-generation API. The preview path is `preview/app-icon.png`. The historical design was superseded by the pen-nib icon in Mac 1.1 / iPhone 1.6.2.

```sh
xcodebuild -project QuickRecord.xcodeproj -scheme GlimpseMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM=YOUR_TEAM build
xcrun swiftc -swift-version 5 -parse-as-library Shared/ArchiveCore.swift \
  Shared/LocalTransport.swift Tests/ArchiveIntegrationTests.swift -o /tmp/glimpse-archive-tests
/tmp/glimpse-archive-tests
```

Debug builds support `GLIMPSE_TEST_ROOT` for an isolated library and disable network receiving in that mode. Release builds do not expose this environment-variable override. The source distribution excludes API keys, personal recordings, pairing credentials, and build artifacts.

## 1.5.3: Antique Enamel Medallion Icon

An ivory background, burgundy oval enamel medallion, antique gold rope border, and raised handwritten G. Rendered using the project's Python material scripts without an image-generation API. Previews were checked at 180/120/60 pixels. The installed asset was an opaque 1024×1024 RGB PNG. Render script: `scripts/render-icon.py`; artwork: `design/AppIcon-glimpse-locket.png`; preview: `preview/app-icon.png`. The previous starburst script is archived at `design/render-icon-jewel.py`.

## 1.5.2: Burgundy Enamel Jewelry Icon

Redesigned in the selected vintage-jewelry style: burgundy enamel, an antique gold starburst setting, a garnet cabochon, and fine engraving. Rendered with project Python scripts using Pillow, NumPy, and SciPy, without an image-generation API. Previews were checked at 180/120/60 pixels; the installed asset was an opaque 1024×1024 RGB PNG. Render script: `scripts/render-icon.py`; artwork: `design/AppIcon-glimpse-jewel.png`; preview: `preview/app-icon.png`. The previous design is archived at `design/AppIcon-green-crest.png`.

## 1.5.1: Glimpse Name and New Icon

Renamed the app to Glimpse and updated its home-screen name, main heading, permission prompts, shortcut instructions, and file-location guidance. Existing app identifiers and data directories were retained so that installing over an earlier version preserves recordings, summaries, Keychain entries, and Action button bindings.

The icon was redesigned with dark green leather, an antique gold Baskerville G monogram, laurel branches, and an engraved oval frame. Rendered with project Python scripts and material shading, without an image-generation API. Previews were checked at 180/120/60 pixels; the final asset was an opaque 1024×1024 RGB PNG. Render script: `scripts/render-icon.py`; artwork: `design/AppIcon-glimpse.png`; preview: `preview/app-icon.png`.

## 1.5: Automatic AI Daily Summaries

Added Daily Summaries to the home screen. Open it, select Connect DeepSeek, enter your own API key on the phone, and select Save Key and Enable Automatic AI Summaries. Credentials and model access are first validated through DeepSeek's model-list endpoint, then stored in the device Keychain. Do not put keys in source code or send them in chat. The same screen lets you disconnect and remove the local key.

After a day ends, transcribed Daily Notes and idea entries are sent to DeepSeek to produce Today's Highlights, Life Notes, Ideas, and Explicit To-Dos, followed by the full original text for that day. Generated UTF-8 TXT files appear in Files → On My iPhone → Glimpse → `每日总结/YYYY-MM-DD 每日总结.txt`. The app supports viewing by date, copying, and sharing/exporting.

- Only text, categories, and source timestamps are sent to `https://api.deepseek.com/chat/completions`; audio is not sent. The configured model is `deepseek-flash` in non-thinking mode. Usage is billed to your DeepSeek account. Long text is summarized in chunks and then merged, potentially requiring multiple calls. HTTP redirects are rejected, and requests use an ephemeral session without caching.
- iOS controls background execution, so generation at exactly midnight is not guaranteed. BGAppRefresh requests execution no earlier than 00:01 the next day; returning to the foreground triggers catch-up processing. The app also checks when it stays in the foreground across midnight. Disabled background refresh, force-quitting, loss of connectivity, or task expiration can delay generation.
- Dates are assigned by recording start time, including recordings that cross midnight. The archive time zone is fixed to the device time zone when summaries are first used and is displayed in the interface, preventing historical dates from shifting during travel.
- No final report is generated for the current day, and days without recordings do not produce empty documents. Initial activation also processes existing past days. Older untranscribed recordings join the queue when automatic transcription is allowed and the app is in the foreground. Failed transcription must be retried from the original recording.
- If some transcripts are missing, the app first creates a source-text document explicitly marked AI Summary Pending. It waits for all transcripts before requesting an AI summary, so incomplete content is not presented as a complete report.
- Model results are cached by source-text fingerprint to avoid repeated calls for unchanged content. Editing text, moving categories, or deleting recordings triggers regeneration. Deleting all recordings for a day removes documents generated by this feature for that day, while leaving other user-created files in the directory untouched. Previously shared copies do not update automatically.
- API errors, insufficient balance, rate limits, empty responses, and truncated responses are not marked complete; a retry option is shown. Canceled tasks do not publish partial results. AI output can be incorrect; check important details against the original text appended to the document.

Implementation: `DailySummary.swift` handles date grouping, documents, state, AI caching, and the interface; `DailySummaryAI.swift` handles DeepSeek requests and Keychain access; `DailySummaryScheduler.swift` handles system background refresh.

Recorded validation: six daily-summary tests passed, covering midnight and daylight-saving boundaries, both categories, pending transcription, cache/edit updates, failure retries, cancellation, file cleanup, and chunk completeness. Three UI tests passed, covering daily documents and connection controls, sharing/export, recording regressions, and transcript editing. Model-logic tests used mocked responses. On September 29, 2026, real DeepSeek model access and a synthetic-record summary were tested on an iPhone 15 Pro Max; all four summary sections were verified. The authorized key was stored in the device Keychain and the one-time transfer file was deleted. The physical-device test did not read personal diaries, and credentials are absent from source code and app bundles. Exact midnight execution has not been verified because background timing depends on system scheduling.

Before reproducing simulator UI tests, run `python3 scripts/seed-daily-summary-test.py` and `python3 scripts/seed-transcript-test.py`. These scripts create synthetic data only in the simulator; they do not write to the phone or read personal diaries.

API reference: [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion).

## 1.4.3: Graphite and Titanium Icon

The icon used a matte graphite panel, recessed circular base, brushed titanium waveform, and dark red indicator. Materials were rendered using height-field normals, directional lighting, soft shadows, contact shadows, and subtle surface textures. The neon halo and orbit were removed. Small home-screen previews were checked; the icon was an opaque 1024×1024 RGB PNG. The release used `scripts/render-icon.py` and `preview/app-icon.png`; the previous version is archived at `design/AppIcon-neon.png` and `design/render-icon-neon.py`. The white in-app theme was unchanged.

## 1.4.2: Sci-Fi Waveform Core

Redesigned the home-screen icon with a deep-space blue background, ice-blue waveform, cyan-to-purple halo, and tilted orbit. Lighting, glow, and curved surfaces were rendered programmatically into an opaque 1024×1024 PNG. Previews were checked at 180/120/60 pixels. The app retained its white theme.

The release used `scripts/render-icon.py`, previewed at `preview/app-icon.png`, with the installed asset at `QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. `design/AppIcon-paper.svg` and `design/render-icon-paper.py` preserve the earlier sticky-note design as historical assets.

## 1.4.1: Voice Note Icon

Redesigned the home-screen icon with a warm white background, a coral folded-corner note, and a white waveform, using subtle gradients and soft shadows. The icon was an opaque 1024×1024 PNG, with rounded corners applied by iOS. Previews were checked at 180/120/60 pixels.

The note design is archived at `design/AppIcon-paper.svg` with `design/render-icon-paper.py`. At the time of the release, rendering used `scripts/render-icon.py` with Pillow and NumPy, the installed asset was `QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, and the preview was `preview/app-icon.png`. The artwork was rendered programmatically without an image-generation API.

## 1.4: White Theme

Removed the upper-right settings button and the in-app settings page. The main screen, transcript screen, and editor now share a light appearance: white backgrounds, pale gray cards, dark text, and orange-red action buttons. The compact recording card from 1.3.1, category-based saving, built-in microphone recording, and automatic transcription were retained. Microphone or speech-permission errors still provide a route to iOS Settings.

The sections below describe earlier releases. References to in-app settings in those releases are historical; that screen was removed in 1.4.

## 1.3.1: Compact Recording Card

Reduced the timer font size, waveform height, and vertical spacing, making the recording card about one-third shorter. The record button retained a 76-point touch target, leaving more room for recordings on the home screen.

## 1.3: Daily Notes / idea Categories

- Removed the press-and-hold setup card from the home screen. Settings remained accessible from the upper-right corner in this release.
- Choose Daily Notes (`日常记录`) or `idea` under Save To. You can switch before stopping a recording; audio and transcripts are saved in the corresponding physical folder.
- The app remembers the last folder, including when recording starts through the Action button.
- The list shows only the current folder. The ellipsis menu moves a recording, its TXT file, and transcription state to the other folder.
- On first launch after upgrading, older recordings are migrated to Daily Notes. Migration preserves file contents and assigns a new filename on conflicts instead of overwriting existing files.
- Both `日常记录` and `idea` folders are visible under Files → On My iPhone → Glimpse → Recordings.

Recorded validation: category migration, moving audio with transcripts, and filename-conflict protection passed. UI tests covered switching to idea during recording, stopping and saving, playback, retaining the folder after relaunch, and viewing, editing, and exporting text.

## 1.2: Always Use the iPhone Microphone

Before recording, the app activates its audio session, explicitly selects `.builtInMic`, and checks the actual input route. The recording session does not enable Bluetooth HFP input; the phone microphone remains selected when wired or Bluetooth headphones are connected. Input is checked again after recording starts and reselected and validated when the system audio route changes. If the built-in microphone cannot be restored, the app stops, saves, and displays an error instead of continuing with a headset microphone.

The main screen identifies the input as the iPhone's built-in microphone. Playback follows the system output route without overriding headphone preferences. System route-change notifications have some latency, so uninterrupted audio at the exact moment of a hardware change is not guaranteed.

Physical-device input-route testing passed, returning the iPhone microphone with port type `.builtInMic`; simulator route testing also passed. Connection and disconnection scenarios have not been individually verified for every Bluetooth or wired headset model.

## 1.1: Automatic Transcription and TXT Export

- Automatic transcription after recording is enabled by default for Mandarin. Saved recordings enter a foreground transcription queue; completion automatically creates a UTF-8 `.txt` file.
- Tap Text beneath a recording to view, copy, or edit the transcript. Export TXT saves it to Files or shares it with another app. Saving edits also updates the TXT file.
- Recordings and companion TXT files are available under Files → Browse → On My iPhone → Glimpse → Recordings. Back up important content before uninstalling.
- In this release, older recordings were not automatically processed in bulk; tap Transcribe to process one. Failed recognition preserves the audio and offers Retry Transcription.
- This release allowed automatic transcription to be disabled in the upper-right settings screen; already queued tasks continued.
- On iOS 26 or later, the app prefers system SpeechTranscriber for on-device processing of long recordings. The Chinese model may need to be downloaded on first use. Other supported versions use SFSpeechRecognizer with on-device recognition required and audio split into 45-second segments. Segment boundaries can affect individual words. If an on-device Chinese model is unavailable, the app reports this and never silently uploads audio for recognition.
- Keep the app in the foreground during transcription. Leaving the app, locking the screen, or starting a new recording pauses processing; returning retries that recording from the beginning. Incomplete text is not exported as a finished TXT transcript.
- Recognition may be inaccurate; verify important content against the original audio. This release did not include speaker diarization, translation, or summaries. Optional daily summaries were added in 1.5.

Implementation: `Transcription.swift` handles on-device recognition, queuing, state, and TXT persistence; `TranscriptView.swift` handles viewing, editing, copying, and exporting.

Recorded validation: three transcription state/persistence tests and three UI tests passed, including recording regressions, transcript editing, copying, and system sharing. Simulator samples are prepared with `python3 scripts/seed-transcript-test.py`; their text is UI test data, not a real recognition result. Physical-device recognition tests use a fixed system-synthesized Mandarin sample and do not read personal recordings.

On September 29, 2026, a recognition test passed on an iPhone 15 Pro Max running iOS 26.6.2. System SpeechTranscriber processed a roughly nine-second fixed Mandarin sample about good weather, a 3 p.m. meeting to discuss project progress, and bringing a computer. This verified the on-device Mandarin engine; it does not establish accuracy for arbitrary accents, noise conditions, or long recordings.

The app was originally built for iPhone 15 Pro Max, using native SwiftUI and supporting iOS 17 or later.

**Press and hold the Action button → Run a shortcut → Open Glimpse and start recording.** Microphone permission is required on first use, and launching from the lock screen may require unlocking. The app uses public system APIs; it cannot intercept a double press of the side button, capture global volume-button presses, or change the system Action button gesture.

## Install on iPhone

1. Open `QuickRecord.xcodeproj` on your Mac.
2. Connect the iPhone by cable, unlock it, and trust the Mac.
3. Sign in with your Apple ID under Xcode → Settings → Accounts.
4. Select the QuickRecord project → QuickRecord target → Signing & Capabilities, then choose your Team. If the bundle identifier conflicts, replace `com.zinger.quickrecord` with your own unique identifier.
5. Select the iPhone as the run destination and click Run. Follow system prompts to enable Developer Mode, restart, and trust the developer on the phone.
6. Open Glimpse, grant microphone permission, and make a short recording.

Free personal development signing generally requires rebuilding and reinstalling through Xcode every seven days. Longer-term distribution requires an appropriate Apple developer signing method. This source project is not an IPA that can be installed directly.

## Configure the iPhone 15 Pro Max Action Button

1. Open Shortcuts on the phone and create a shortcut.
2. Add Glimpse → Start Recording and name the shortcut “Glimpse Recording.”
3. Open Settings → Action Button and select Shortcut.
4. Tap Choose a Shortcut and select “Glimpse Recording.”
5. **Press and hold the Action button above the volume buttons on the left side.** Unlock if prompted to begin recording.
6. Once recording begins, it can continue with the screen locked. Return to the app and tap Stop and Save to finish. Running the start shortcut again does not stop or overwrite an active recording.

If the app action does not appear in search, open Glimpse once first. Alternatively, create a shortcut with a URL action set to `quickrecord://record`, followed by Open URLs.

If you only need the system recorder, iPhone Settings → Action Button → Voice Memo already supports press-and-hold recording without installing this app.

## Core Features

- Mono AAC/M4A recording, elapsed-time display, and input-level visualization.
- Automatic saving when recording stops; newest-first listing, playback, system sharing/export, and deletion with confirmation.
- A Start Recording App Intent and a URL launch entry point.
- Background audio after recording starts, with file protection configured to allow an open recording file to remain writable after locking.
- Microphone-permission guidance, saving on call interruptions, and encoding-error messages.
- Local recording and transcript storage with no third-party app dependencies. Enabling AI daily summaries sends transcript text to DeepSeek. Device backups may include files; uninstalling the app deletes local recordings.

## Recorded Validation

The results in this README describe prior development checks, not a fresh test run for each documentation update.

On September 29, 2026, simulator Debug and physical-device Release builds succeeded, and both initial UI tests passed. The app was installed on an iPhone 15 Pro Max running iOS 26.6.2 using the existing personal development signing identity, and launched successfully through device tools.

That development installation's personal signing was valid until **October 6, 2026, at 12:59 Singapore time**, after which rebuilding and reinstalling is required. This date applies only to that installation. Initial microphone permission, shortcut selection, Action button binding, and actual lock-screen behavior must be completed and checked on the phone.

Xcode 27's Siri natural-language training step reported `Could not archive SSU artifacts`, but the build succeeded and App Intent action metadata was generated. Discovery of the shortcut action on the physical device had not been confirmed; if it does not appear, use the URL entry point described above. The first URL invocation may also trigger a system Open confirmation.

```sh
xcodebuild -project QuickRecord.xcodeproj -scheme QuickRecord \
  -sdk iphonesimulator -configuration Debug -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project QuickRecord.xcodeproj -scheme QuickRecord \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

UI automation covered the recording timer, stopping and saving, playback, file persistence after relaunch, and settings instructions in the relevant release. The simulator cannot validate the physical Action button, actual locked-screen recording, or incoming-call interruptions; these still require device checks.

## Code Entry Points

- `QuickRecord/QuickRecordApp.swift`: app lifecycle, Shortcuts, and URL entry points.
- `QuickRecord/Recorder.swift`: microphone permission, audio sessions, recording, file management, and playback.
- `QuickRecord/ContentView.swift`: Chinese interface and Action button setup guidance.
- `QuickRecord/Info.plist`: microphone usage description, background audio, and URL scheme.

Apple documentation: [Use and customize the Action button](https://support.apple.com/guide/iphone/use-and-customize-the-action-button-iphe89d61d66/ios), [Use Back Tap](https://support.apple.com/en-us/111772).

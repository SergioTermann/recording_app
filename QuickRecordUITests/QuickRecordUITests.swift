import XCTest

final class QuickRecordUITests: XCTestCase {
    @MainActor
    func testDailySummaryArchiveConnectionAndExport() throws {
        #if targetEnvironment(simulator)
        let app = XCUIApplication()
        app.launchArguments = ["-automaticTranscription", "NO"]
        app.launch()
        app.buttons["dailySummaries"].tap()
        XCTAssertTrue(app.navigationBars["每日总结"].waitForExistence(timeout: 5))
        app.buttons["连接 DeepSeek，开启 AI 总结"].tap()
        XCTAssertTrue(app.secureTextFields["粘贴 API Key"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存密钥并开启自动 AI 总结"].isEnabled)
        app.buttons["取消"].tap()
        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dailySummary-")).firstMatch
        if !day.isHittable { app.swipeUp() }
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        XCTAssertTrue(app.staticTexts["dailySummaryText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["dailySummaryText"].label.contains("日报测试"))
        XCTAssertTrue(app.staticTexts["dailySummaryText"].label.contains("AI 总结待生成"))
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "每日文档（未连接模型的真实状态）"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["exportDailySummary"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5) || app.buttons["Copy"].exists || app.buttons["拷贝"].exists)
        #else
        throw XCTSkip("固定测试数据仅写入模拟器")
        #endif
    }

    @MainActor
    func testRecordingPlaybackAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-automaticTranscription", "NO"]
        app.launch()
        XCTAssertFalse(app.buttons["设置操作按钮"].exists)
        XCTAssertFalse(app.staticTexts["长按一下，就开始"].exists)
        app.segmentedControls["folderPicker"].buttons["日常记录"].tap()
        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            for title in ["Allow", "允许", "OK", "好"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        // An extra interaction lets XCTest handle the system permission dialog.
        app.staticTexts["Glimpse"].tap()
        let timer = app.staticTexts["recordingTimer"]
        let advancing = NSPredicate(format: "label >= %@", "00:00:03")
        expectation(for: advancing, evaluatedWith: timer)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(record.label, "停止并保存")
        app.segmentedControls["folderPicker"].buttons["idea"].tap()
        record.tap()
        XCTAssertTrue(app.buttons["播放录音"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["播放录音"].firstMatch.tap()
        XCTAssertTrue(app.buttons["停止播放"].firstMatch.waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.segmentedControls["folderPicker"].buttons["idea"].isSelected)
        XCTAssertTrue(app.buttons["播放录音"].firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "已保存的录音"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testTranscriptViewingEditingAndExport() throws {
        #if targetEnvironment(simulator)
        let app = XCUIApplication()
        app.launch()
        app.segmentedControls["folderPicker"].buttons["日常记录"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "transcriptRow", "文字界面测试")).firstMatch
        if !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "先运行脚本准备模拟器文字样本")
        row.tap()
        XCTAssertTrue(app.staticTexts["transcriptText"].label.contains("文字界面测试"))
        app.buttons["复制文字"].tap()
        XCTAssertTrue(app.buttons["已复制"].exists)
        app.buttons["修改文字"].tap()
        app.textViews["transcriptEditor"].tap()
        app.textViews["transcriptEditor"].typeText(" Updated.")
        app.buttons["保存修改并更新 TXT"].tap()
        XCTAssertTrue(app.staticTexts["transcriptText"].label.contains("Updated."))
        app.buttons["exportTranscript"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5) || app.buttons["Copy"].exists || app.buttons["拷贝"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "文字导出"
        shot.lifetime = .keepAlways
        add(shot)
        #else
        throw XCTSkip("固定样本仅写入模拟器")
        #endif
    }
}

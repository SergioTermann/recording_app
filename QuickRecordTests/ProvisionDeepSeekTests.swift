import XCTest
@testable import QuickRecord

/// Opt-in device provisioning. No credential is embedded in the test bundle.
/// The one-time file is delivered directly to this app's private temporary directory.
final class ProvisionDeepSeekTests: XCTestCase {
    @MainActor
    func testImportAndValidateProvidedKey() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("One-time provisioning is for the owner's physical device only.")
        #else
        let temporary = FileManager.default.temporaryDirectory
        let input = temporary.appendingPathComponent("deepseek-key-import")
        let key: String
        if FileManager.default.fileExists(atPath: input.path) {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: input.path)
            key = try String(contentsOf: input, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove staging material before making any network call.
            try FileManager.default.removeItem(at: input)
            // This owner-authorized provisioning key was already validated on the Mac.
            // Persist securely so a denied network prompt does not require restaging it.
            try SummaryKeychain.save(key)
        } else if let saved = SummaryKeychain.read() {
            key = saved
        } else {
            throw XCTSkip("No one-time credential was supplied or securely stored.")
        }
        try await DeepSeekDailySummarizer.validateKey(key)
        let result = try await DeepSeekDailySummarizer().summarize(
            source: "以下为虚构测试记录。10:00 日常记录：在公园散步。18:00 idea：想到一个植物浇水提醒工具，计划明天画草图。",
            day: "测试日期", key: key
        )
        guard ["今日重点", "生活记录", "idea", "待办"].allSatisfy({ result.contains($0) }),
              SummaryKeychain.read() == key else {
            XCTFail("Summary structure or secure credential persistence validation failed.")
            return
        }
        let receipt = ["keyStoredInKeychain": true, "modelValidated": true, "syntheticSummaryValidated": true, "stagingFileDeleted": !FileManager.default.fileExists(atPath: input.path)]
        try JSONEncoder().encode(receipt).write(to: temporary.appendingPathComponent("deepseek-provision-result.json"), options: .atomic)
        #endif
    }
}

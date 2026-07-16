import XCTest
@testable import OhMyUsage

/**
 * [INPUT]: 依赖 SecurityCredentialReader 的 XCTest 环境保护分支。
 * [OUTPUT]: 验证默认测试运行不会读取或写入真实 macOS Keychain。
 * [POS]: OhMyUsageTests 的系统凭据边界回归测试，保护默认 swift test 不弹钥匙串授权。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class SecurityCredentialReaderTests: XCTestCase {
    func testReadGenericPasswordReturnsNilInXCTestWithoutTouchingSystemKeychain() {
        let service = "CraftMeter.SecurityCredentialReaderTests.\(UUID().uuidString)"

        let value = SecurityCredentialReader.readGenericPassword(
            service: service,
            account: "account",
            bypassCache: true
        )

        XCTAssertNil(value)
    }

    func testSaveGenericPasswordIsDisabledInXCTest() {
        let service = "CraftMeter.SecurityCredentialReaderTests.\(UUID().uuidString)"

        let didSave = SecurityCredentialReader.saveGenericPassword(
            service: service,
            account: "account",
            text: "secret-token"
        )

        XCTAssertFalse(didSave)
        XCTAssertNil(
            SecurityCredentialReader.readGenericPassword(
                service: service,
                account: "account",
                bypassCache: true
            )
        )
    }
}

import LocalAuthentication
import Security
import XCTest
@testable import OhMyUsage

/**
 * [INPUT]: 依赖 SecurityCredentialReader 的 XCTest 环境保护分支与可注入 SecureStoreWriter。
 * [OUTPUT]: 验证默认测试不触达真实 Keychain，并覆盖非交互 update-or-add 的成功、缺失与权限失败路径。
 * [POS]: CraftMeterTests 的外部系统凭据边界回归测试，保护后台写入不删除旧项、不调用 shell fallback。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class SecurityCredentialReaderTests: XCTestCase {
    func testNonInteractiveAuthenticationAttributesHardFailAllAuthenticationUI() {
        let attributes = SecurityCredentialReader.nonInteractiveAuthenticationAttributesForTesting()
        let context = attributes[kSecUseAuthenticationContext as String] as? LAContext

        XCTAssertEqual(context?.interactionNotAllowed, true)
        XCTAssertEqual(
            attributes[kSecUseAuthenticationUI as String] as? String,
            kSecUseAuthenticationUIFail as String
        )
    }

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

    func testSaveGenericPasswordUpdatesExistingItemWithoutAdding() {
        var updateCount = 0
        var addCount = 0
        let writer = SecurityCredentialReader.SecureStoreWriter(
            update: { _, _ in
                updateCount += 1
                return errSecSuccess
            },
            add: { _ in
                addCount += 1
                return errSecSuccess
            }
        )

        XCTAssertTrue(SecurityCredentialReader.saveGenericPassword(
            service: "service",
            account: "account",
            text: "secret",
            secureStore: writer,
            allowUnderXCTest: true
        ))
        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(addCount, 0)
    }

    func testSaveGenericPasswordAddsOnlyWhenItemIsMissing() {
        var addCount = 0
        let writer = SecurityCredentialReader.SecureStoreWriter(
            update: { _, _ in errSecItemNotFound },
            add: { attributes in
                addCount += 1
                let dictionary = attributes as NSDictionary
                XCTAssertEqual(dictionary[kSecAttrService as String] as? String, "service")
                XCTAssertEqual(dictionary[kSecAttrAccount as String] as? String, "account")
                XCTAssertNotNil(dictionary[kSecUseAuthenticationContext as String])
                XCTAssertEqual(
                    dictionary[kSecUseAuthenticationUI as String] as? String,
                    kSecUseAuthenticationUIFail as String
                )
                return errSecSuccess
            }
        )

        XCTAssertTrue(SecurityCredentialReader.saveGenericPassword(
            service: "service",
            account: "account",
            text: "secret",
            secureStore: writer,
            allowUnderXCTest: true
        ))
        XCTAssertEqual(addCount, 1)
    }

    func testSaveGenericPasswordDoesNotAddAfterPermissionFailure() {
        var addCount = 0
        let writer = SecurityCredentialReader.SecureStoreWriter(
            update: { _, _ in errSecInteractionNotAllowed },
            add: { _ in
                addCount += 1
                return errSecSuccess
            }
        )

        XCTAssertFalse(SecurityCredentialReader.saveGenericPassword(
            service: "service",
            account: "account",
            text: "secret",
            secureStore: writer,
            allowUnderXCTest: true
        ))
        XCTAssertEqual(addCount, 0)
    }
}

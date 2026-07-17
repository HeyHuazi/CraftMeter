/**
 * [INPUT]: 依赖 RelayCurlImportParser 的白名单 tokenizer 与 NewAPI self 请求约束
 * [OUTPUT]: 验证 cURL 解析兼容性、确定性认证提取及错误信息不泄露秘密
 * [POS]: Tests 的 cURL 秘密输入边界回归测试
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import XCTest
@testable import OhMyUsage

final class RelayCurlImportParserTests: XCTestCase {
    func testParsesChromeMultilineBearerCurl() throws {
        let parsed = try RelayCurlImportParser().parse("""
        curl 'https://relay.example.com/api/user/self?from=profile' \\
          -H 'accept: application/json' \\
          -H 'Authorization: Bearer secret-access-token' \\
          -H 'New-Api-User: 42'
        """)

        XCTAssertEqual(parsed.baseURL, "https://relay.example.com")
        XCTAssertEqual(parsed.host, "relay.example.com")
        XCTAssertEqual(parsed.bearerToken, "secret-access-token")
        XCTAssertNil(parsed.cookieHeader)
        XCTAssertEqual(parsed.userID, "42")
    }

    func testParsesCookieOptionAndURLFlag() throws {
        let parsed = try RelayCurlImportParser().parse(
            "curl --url=\"https://relay.example.com/api/user/self/\" --cookie \"session=abc; theme=dark\""
        )

        XCTAssertEqual(parsed.baseURL, "https://relay.example.com")
        XCTAssertEqual(parsed.cookieHeader, "session=abc; theme=dark")
        XCTAssertNil(parsed.bearerToken)
        XCTAssertNil(parsed.userID)
    }

    func testLastHeaderWinsCaseInsensitively() throws {
        let parsed = try RelayCurlImportParser().parse("""
        curl https://relay.example.com/api/user/self \\
          --header='authorization: Bearer old' \\
          -H "AUTHORIZATION: Bearer newest" \\
          -H "new-api-user: 1001" \\
          -H "Cookie: session=abc"
        """)

        XCTAssertEqual(parsed.bearerToken, "newest")
        XCTAssertEqual(parsed.cookieHeader, "session=abc")
        XCTAssertEqual(parsed.userID, "1001")
    }

    func testParsesRawAuthorizationAccessToken() throws {
        let parsed = try RelayCurlImportParser().parse("""
        curl https://relay.example.com/api/user/self \\
          -H 'Authorization: opaque-access-token' \\
          -H 'New-Api-User: 9'
        """)

        XCTAssertEqual(parsed.bearerToken, "opaque-access-token")
        XCTAssertEqual(parsed.userID, "9")
    }

    func testRejectsUnsupportedInputsWithRedactedErrors() {
        let secret = "do-not-leak-secret"
        let cases: [(String, RelayCurlImportParseError)] = [
            ("", .emptyInput),
            ("wget https://relay.example.com/api/user/self", .notCurlCommand),
            ("curl 'https://relay.example.com/api/user/self", .malformedQuoting),
            ("curl -H 'Authorization: Bearer \(secret)'", .missingURL),
            ("curl ftp://relay.example.com/api/user/self -H 'Authorization: Bearer \(secret)'", .unsupportedURL),
            ("curl https://relay.example.com/api/user/token -H 'Authorization: Bearer \(secret)'", .unsupportedEndpoint),
            ("curl https://relay.example.com/api/user/self", .missingCredential)
        ]

        for (command, expected) in cases {
            XCTAssertThrowsError(try RelayCurlImportParser().parse(command)) { error in
                XCTAssertEqual(error as? RelayCurlImportParseError, expected)
                XCTAssertFalse(String(describing: error).contains(secret))
                XCTAssertFalse((error as? RelayCurlImportParseError)?.userMessage.contains(secret) ?? true)
            }
        }
    }
}

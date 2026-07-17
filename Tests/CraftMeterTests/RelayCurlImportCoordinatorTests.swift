/**
 * [INPUT]: 依赖 RelayCurlImportCoordinator、RelayHTTPClient 与可控 URLProtocol 响应
 * [OUTPUT]: 验证 NewAPI cURL 认证选择、Cookie User ID 补全和失败脱敏
 * [POS]: Tests 的 cURL 网络验证边界回归测试，不访问真实站点或系统 Keychain
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation
import XCTest
@testable import OhMyUsage

final class RelayCurlImportCoordinatorTests: XCTestCase {
    override func tearDown() {
        CurlImportMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testBearerAndUserIDValidateAsSinglePersistableCredential() async throws {
        let session = makeSession()
        CurlImportMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/status" {
                return Self.statusResponse(request)
            }
            XCTAssertEqual(request.url?.path, "/api/user/self")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "42")
            return Self.response(request, json: [
                "success": true,
                "data": ["id": 42, "quota": 500_000, "used_quota": 100_000, "group": "default"]
            ])
        }

        let result = await RelayCurlImportCoordinator(session: session).validate("""
        curl https://relay.example.com/api/user/self \\
          -H 'Authorization: Bearer access-secret' \\
          -H 'New-Api-User: 42'
        """)
        let payload = try XCTUnwrap(result.successValue)

        XCTAssertEqual(payload.baseURL, "https://relay.example.com")
        XCTAssertEqual(payload.userID, "42")
        XCTAssertEqual(payload.credentialKind, .bearer)
        XCTAssertEqual(payload.credential, "access-secret")
        XCTAssertGreaterThan(payload.snapshotPreview.remaining ?? 0, 0)
    }

    func testCookieOnlyDiscoversUserIDThenVerifiesWithSameCookie() async throws {
        let session = makeSession()
        var requests = 0
        CurlImportMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/status" {
                return Self.statusResponse(request)
            }
            requests += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=cookie-secret")
            if requests == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "New-Api-User"))
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "77")
            }
            return Self.response(request, json: [
                "success": true,
                "data": ["id": 77, "quota": 900_000, "used_quota": 100_000, "group": "team"]
            ])
        }

        let result = await RelayCurlImportCoordinator(session: session).validate(
            "curl https://relay.example.com/api/user/self -b 'session=cookie-secret'"
        )
        let payload = try XCTUnwrap(result.successValue)

        XCTAssertEqual(requests, 2)
        XCTAssertEqual(payload.userID, "77")
        XCTAssertEqual(payload.credentialKind, .cookie)
        XCTAssertEqual(payload.credential, "session=cookie-secret")
    }

    func testBearerFailureFallsBackToPersistableCookie() async throws {
        let session = makeSession()
        CurlImportMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/status" {
                return Self.statusResponse(request)
            }
            if request.value(forHTTPHeaderField: "Cookie") == nil {
                return Self.response(request, status: 401, json: ["message": "expired"])
            }
            return Self.response(request, json: [
                "success": true,
                "data": ["id": 8, "quota": 100, "used_quota": 20]
            ])
        }

        let result = await RelayCurlImportCoordinator(session: session).validate("""
        curl https://relay.example.com/api/user/self \\
          -H 'Authorization: Bearer expired-secret' \\
          -H 'Cookie: session=fresh-secret' \\
          -H 'New-Api-User: 8'
        """)
        let payload = try XCTUnwrap(result.successValue)

        XCTAssertEqual(payload.credentialKind, .cookie)
        XCTAssertEqual(payload.credential, "session=fresh-secret")
    }

    func testFailureResultNeverContainsCredential() async throws {
        let secret = "top-secret-value"
        let session = makeSession()
        CurlImportMockURLProtocol.requestHandler = { request in
            Self.response(request, status: 401, json: ["message": "expired"])
        }

        let result = await RelayCurlImportCoordinator(session: session).validate("""
        curl https://relay.example.com/api/user/self \\
          -H 'Authorization: Bearer \(secret)' \\
          -H 'New-Api-User: 42'
        """)
        let failure = try XCTUnwrap(result.failureValue)

        XCTAssertFalse(failure.success)
        XCTAssertFalse(failure.message.contains(secret))
        XCTAssertFalse(String(describing: failure).contains(secret))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CurlImportMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func statusResponse(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        response(request, json: [
            "success": true,
            "data": [
                "quota_per_unit": 500_000,
                "quota_display_type": "USD",
                "display_in_currency": true
            ]
        ])
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        json: [String: Any]
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, try! JSONSerialization.data(withJSONObject: json))
    }
}

private extension Result {
    var successValue: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var failureValue: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}

private final class CurlImportMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

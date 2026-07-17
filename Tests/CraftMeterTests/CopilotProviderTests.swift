import Foundation
import XCTest
@testable import OhMyUsage

final class CopilotProviderTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        CopilotMockURLProtocol.requestHandler = nil
    }

    func testFetchPrefersCopilotGitHubTokenAndSetsAuthSourceLabel() async throws {
        let provider = makeProvider(
            environment: {
                [
                    "COPILOT_GITHUB_TOKEN": "copilot-env-token",
                    "GH_TOKEN": "gh-env-token",
                    "GITHUB_TOKEN": "github-env-token"
                ]
            },
            requestHandler: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token copilot-env-token")
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.successBody.utf8))
            }
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.authSourceLabel, "COPILOT_GITHUB_TOKEN")
        XCTAssertEqual(snapshot.accountLabel, "octocat")
        XCTAssertEqual(snapshot.sourceLabel, "GitHub API")
    }

    func testFetchDoesNotReadExternalKeychainOrRunGitHubCLI() async {
        var keychainReadCount = 0
        var shellRunCount = 0
        let provider = makeProvider(
            keychainReader: { _, _ in
                keychainReadCount += 1
                return "external-secret"
            },
            shellRunner: { _, _, _ in
                shellRunCount += 1
                return (0, "shell-secret", "")
            }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential(let account) = error else {
                return XCTFail("Expected missingCredential, got \(error)")
            }
            XCTAssertTrue(account.contains("explicitly"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(keychainReadCount, 0)
        XCTAssertEqual(shellRunCount, 0)
    }

    func testFetchThrowsHelpfulMissingCredentialWhenAllSourcesMissing() async {
        let provider = makeProvider()

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential(let account) = error else {
                return XCTFail("Expected missingCredential, got \(error)")
            }
            XCTAssertTrue(account.contains("COPILOT_GITHUB_TOKEN"))
            XCTAssertFalse(account.contains("Copilot CLI"))
            XCTAssertFalse(account.contains("GitHub CLI"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchMaps401ToUnauthorizedDetailWithSourceLabel() async {
        let provider = makeProvider(
            environment: { ["GH_TOKEN": "gh-env-token"] },
            requestHandler: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"message":"token expired"}"#.utf8))
            }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("GH_TOKEN"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("refresh"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("token expired"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchMaps403ToUnauthorizedDetailWithEntitlementGuidance() async {
        let provider = makeProvider(
            environment: { ["GITHUB_TOKEN": "github-env-token"] },
            requestHandler: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 403, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"message":"Resource not accessible by integration"}"#.utf8))
            }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("GITHUB_TOKEN"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("entitlement"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("scope"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("resource not accessible"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeProvider(
        environment: @escaping () -> [String: String] = { [:] },
        keychainReader: @escaping (String, String?) -> String? = { _, _ in nil },
        shellRunner: @escaping (String, [String], TimeInterval) -> (status: Int32, stdout: String, stderr: String)? = { _, _, _ in nil },
        requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? = nil
    ) -> CopilotProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CopilotMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        CopilotMockURLProtocol.requestHandler = requestHandler

        var descriptor = ProviderDescriptor.defaultOfficialCopilot()
        descriptor.officialConfig?.sourceMode = .auto

        return CopilotProvider(
            descriptor: descriptor,
            session: session,
            environment: environment,
            keychainReader: keychainReader,
            shellRunner: shellRunner
        )
    }

    private static let successBody = """
    {
      "copilot_plan": "pro",
      "login": "octocat",
      "quota_reset_date": "2026-04-30T00:00:00Z",
      "quota_snapshots": {
        "premium_interactions": { "percent_remaining": 80, "entitlement": 300, "remaining": 240 },
        "chat": { "percent_remaining": 95, "entitlement": 1000, "remaining": 950 }
      }
    }
    """
}

private final class CopilotMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = CopilotMockURLProtocol.requestHandler else {
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

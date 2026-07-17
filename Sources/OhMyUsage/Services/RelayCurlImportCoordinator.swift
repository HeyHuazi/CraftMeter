/**
 * [INPUT]: 依赖 RelayCurlImportParser、Generic NewAPI manifest、RelayHTTPClient 与响应解释器
 * [OUTPUT]: 对内提供验证后的站点 origin、User ID、单一可持久化凭据和脱敏预览
 * [POS]: Services 的 cURL 导入编排边界；先验证再交付秘密，失败不触碰配置或 Keychain
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation
import OhMyUsageDomain

struct RelayCurlImportVerifiedPayload: Sendable {
    let baseURL: String
    let host: String
    let userID: String
    let credentialKind: RelayCurlImportCredentialKind
    let credential: String
    let snapshotPreview: RelayDiagnosticSnapshotPreview
}

struct RelayCurlImportDisplayResult: Error, Equatable, Sendable {
    let success: Bool
    let host: String?
    let credentialKind: RelayCurlImportCredentialKind?
    let message: String
    let providerID: String?

    func attaching(providerID: String) -> RelayCurlImportDisplayResult {
        RelayCurlImportDisplayResult(
            success: success,
            host: host,
            credentialKind: credentialKind,
            message: message,
            providerID: providerID
        )
    }
}

struct RelayCurlImportVerificationError: Error {
    let message: String
}

struct RelayCurlImportCoordinator: Sendable {
    typealias VerifyHandler = @Sendable (ParsedRelayCurlImport) async throws -> RelayCurlImportVerifiedPayload

    private let parser: RelayCurlImportParser
    private let verifyHandler: VerifyHandler

    init(
        parser: RelayCurlImportParser = RelayCurlImportParser(),
        session: URLSession = .shared
    ) {
        self.parser = parser
        self.verifyHandler = { parsed in
            try await Self.verify(parsed, session: session)
        }
    }

    init(
        parser: RelayCurlImportParser = RelayCurlImportParser(),
        verifyHandler: @escaping VerifyHandler
    ) {
        self.parser = parser
        self.verifyHandler = verifyHandler
    }

    func validate(_ command: String) async -> Result<RelayCurlImportVerifiedPayload, RelayCurlImportDisplayResult> {
        let parsed: ParsedRelayCurlImport
        do {
            parsed = try parser.parse(command)
        } catch let error as RelayCurlImportParseError {
            return .failure(RelayCurlImportDisplayResult(
                success: false,
                host: nil,
                credentialKind: nil,
                message: error.userMessage,
                providerID: nil
            ))
        } catch {
            return .failure(RelayCurlImportDisplayResult(
                success: false,
                host: nil,
                credentialKind: nil,
                message: "无法解析 cURL 命令",
                providerID: nil
            ))
        }

        do {
            return .success(try await verifyHandler(parsed))
        } catch let error as RelayCurlImportVerificationError {
            return .failure(RelayCurlImportDisplayResult(
                success: false,
                host: parsed.host,
                credentialKind: nil,
                message: error.message,
                providerID: nil
            ))
        } catch {
            return .failure(RelayCurlImportDisplayResult(
                success: false,
                host: parsed.host,
                credentialKind: nil,
                message: "认证失效或站点响应无法识别",
                providerID: nil
            ))
        }
    }

    private static func verify(
        _ parsed: ParsedRelayCurlImport,
        session: URLSession
    ) async throws -> RelayCurlImportVerifiedPayload {
        let client = RelayHTTPClient(session: session)
        var failures = 0

        if let bearer = parsed.bearerToken, let userID = parsed.userID {
            do {
                return try await verifyCandidate(
                    parsed: parsed,
                    userID: userID,
                    kind: .bearer,
                    credential: bearer,
                    headers: [
                        "Authorization": "Bearer \(bearer)",
                        "New-Api-User": userID
                    ],
                    client: client
                )
            } catch {
                failures += 1
            }
        }

        if let cookie = parsed.cookieHeader {
            do {
                let resolvedUserID: String
                if let userID = parsed.userID {
                    resolvedUserID = userID
                } else {
                    let root = try await client.requestJSON(
                        url: parsed.requestURL,
                        headers: ["Cookie": cookie],
                        method: "GET",
                        bodyJSON: nil
                    )
                    guard let detected = RelayJSONExpressionEvaluator.stringValue(
                        for: "coalesce(data.id,data.user_id,data.userId,id,user_id,userId)",
                        in: root
                    )?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !detected.isEmpty else {
                        throw RelayCurlImportVerificationError(message: "登录态有效，但响应中没有可识别的 User ID")
                    }
                    resolvedUserID = detected
                }

                return try await verifyCandidate(
                    parsed: parsed,
                    userID: resolvedUserID,
                    kind: .cookie,
                    credential: cookie,
                    headers: [
                        "Cookie": cookie,
                        "New-Api-User": resolvedUserID
                    ],
                    client: client
                )
            } catch let error as RelayCurlImportVerificationError {
                throw error
            } catch {
                failures += 1
            }
        }

        if parsed.bearerToken != nil, parsed.userID == nil, parsed.cookieHeader == nil {
            throw RelayCurlImportVerificationError(message: "Access Token 导入需要 cURL 中包含 New-Api-User")
        }
        if failures > 0 {
            throw RelayCurlImportVerificationError(message: "认证失效或站点响应无法识别")
        }
        throw RelayCurlImportVerificationError(message: "没有可验证的 NewAPI 账户凭据")
    }

    private static func verifyCandidate(
        parsed: ParsedRelayCurlImport,
        userID: String,
        kind: RelayCurlImportCredentialKind,
        credential: String,
        headers: [String: String],
        client: RelayHTTPClient
    ) async throws -> RelayCurlImportVerifiedPayload {
        let manifest = RelayAdapterRegistry.genericManifest
        var relayConfig = ProviderDescriptor.makeOpenRelay(
            name: parsed.host,
            baseURL: parsed.baseURL,
            preferredAdapterID: manifest.id
        ).relayConfig!
        relayConfig.manualOverrides = RelayManualOverride(
            authHeader: kind == .cookie ? "Cookie" : "Authorization",
            authScheme: kind == .cookie ? "" : "Bearer",
            userID: userID,
            userIDHeader: "New-Api-User",
            requestMethod: "GET",
            requestBodyJSON: nil,
            endpointPath: "/api/user/self",
            remainingExpression: manifest.extract.remaining,
            usedExpression: manifest.extract.used,
            limitExpression: manifest.extract.limit,
            successExpression: manifest.extract.success,
            unitExpression: manifest.extract.unit,
            accountLabelExpression: manifest.extract.accountLabel,
            staticHeaders: nil
        )
        let request = RelayRequestResolver.resolveBalanceRequest(manifest: manifest, relayConfig: relayConfig)
        let root = try await client.requestJSON(
            url: parsed.requestURL,
            headers: headers,
            method: "GET",
            bodyJSON: nil
        )
        let candidate = RelayCredentialCandidate(
            headers: headers,
            source: kind == .cookie ? "curlCookie" : "curlBearer",
            persistedCredential: credential
        )
        let account = try await RelayResponseInterpreter.extractAccountValues(
            root: root,
            baseURL: URL(string: parsed.baseURL)!,
            request: request,
            manifest: manifest,
            headers: headers,
            candidate: candidate,
            requestJSON: { url, headers, method, bodyJSON in
                try await client.requestJSON(url: url, headers: headers, method: method, bodyJSON: bodyJSON)
            }
        )
        guard let remaining = account.remaining else {
            throw RelayCurlImportVerificationError(message: "响应中没有可识别的账户余额")
        }
        return RelayCurlImportVerifiedPayload(
            baseURL: parsed.baseURL,
            host: parsed.host,
            userID: userID,
            credentialKind: kind,
            credential: credential,
            snapshotPreview: RelayDiagnosticSnapshotPreview(
                remaining: remaining,
                used: account.used,
                limit: account.limit,
                unit: account.unit
            )
        )
    }
}

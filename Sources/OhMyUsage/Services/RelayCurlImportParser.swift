/**
 * [INPUT]: 依赖 Foundation 的 URL 解析与字符扫描能力，接收浏览器 Copy as cURL 文本
 * [OUTPUT]: 对内提供经过白名单约束的 NewAPI self 请求、Bearer/Cookie 与 User ID 候选
 * [POS]: Services 的秘密输入边界；只解析不执行命令，原始 cURL 与凭据不得进入 UI 状态或日志
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation

enum RelayCurlImportCredentialKind: String, Equatable, Sendable {
    case bearer
    case cookie
}

struct ParsedRelayCurlImport: Sendable {
    let requestURL: URL
    let baseURL: String
    let host: String
    let bearerToken: String?
    let cookieHeader: String?
    let userID: String?
}

enum RelayCurlImportParseError: Error, Equatable {
    case emptyInput
    case notCurlCommand
    case malformedQuoting
    case missingURL
    case unsupportedURL
    case unsupportedEndpoint
    case missingCredential

    var userMessage: String {
        switch self {
        case .emptyInput:
            return "剪贴板为空"
        case .notCurlCommand:
            return "剪贴板内容不是 cURL 命令"
        case .malformedQuoting:
            return "cURL 引号或转义不完整"
        case .missingURL:
            return "cURL 中未找到请求地址"
        case .unsupportedURL:
            return "只支持包含有效域名的 HTTP/HTTPS 地址"
        case .unsupportedEndpoint:
            return "请复制 NewAPI 的 /api/user/self 请求"
        case .missingCredential:
            return "cURL 中未找到 Authorization 或 Cookie"
        }
    }
}

struct RelayCurlImportParser: Sendable {
    func parse(_ command: String) throws -> ParsedRelayCurlImport {
        let tokens = try tokenize(command)
        guard !tokens.isEmpty else { throw RelayCurlImportParseError.emptyInput }
        guard tokens[0].lowercased() == "curl" else {
            throw RelayCurlImportParseError.notCurlCommand
        }

        var headers: [(String, String)] = []
        var cookieOption: String?
        var urlText: String?
        var index = 1

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "-H", "--header":
                index += 1
                if index < tokens.count, let header = parseHeader(tokens[index]) {
                    headers.append(header)
                }
            case "-b", "--cookie":
                index += 1
                if index < tokens.count {
                    cookieOption = nonEmpty(tokens[index])
                }
            case "--url":
                index += 1
                if index < tokens.count {
                    urlText = nonEmpty(tokens[index])
                }
            default:
                if token.hasPrefix("--url=") {
                    urlText = nonEmpty(String(token.dropFirst("--url=".count)))
                } else if token.hasPrefix("--header=") {
                    if let header = parseHeader(String(token.dropFirst("--header=".count))) {
                        headers.append(header)
                    }
                } else if token.hasPrefix("--cookie=") {
                    cookieOption = nonEmpty(String(token.dropFirst("--cookie=".count)))
                } else if !token.hasPrefix("-") && looksLikeURL(token) {
                    urlText = token
                }
            }
            index += 1
        }

        guard let urlText else { throw RelayCurlImportParseError.missingURL }
        guard let components = URLComponents(string: urlText),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              let requestURL = components.url else {
            throw RelayCurlImportParseError.unsupportedURL
        }
        let normalizedPath = normalizedEndpointPath(components.path)
        guard normalizedPath == "/api/user/self" else {
            throw RelayCurlImportParseError.unsupportedEndpoint
        }

        let authorization = lastHeaderValue(named: "Authorization", in: headers)
        let bearerToken = authorization.flatMap(normalizeAccessToken)
        let cookieHeader = nonEmpty(lastHeaderValue(named: "Cookie", in: headers)) ?? cookieOption
        let userID = nonEmpty(lastHeaderValue(named: "New-Api-User", in: headers))
        guard bearerToken != nil || cookieHeader != nil else {
            throw RelayCurlImportParseError.missingCredential
        }

        var baseComponents = components
        baseComponents.path = ""
        baseComponents.query = nil
        baseComponents.fragment = nil
        baseComponents.user = nil
        baseComponents.password = nil
        guard let baseURL = baseComponents.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !baseURL.isEmpty else {
            throw RelayCurlImportParseError.unsupportedURL
        }

        return ParsedRelayCurlImport(
            requestURL: requestURL,
            baseURL: baseURL,
            host: host,
            bearerToken: bearerToken,
            cookieHeader: cookieHeader,
            userID: userID
        )
    }

    private func tokenize(_ command: String) throws -> [String] {
        enum Quote { case single, double }
        var tokens: [String] = []
        var current = ""
        var quote: Quote?
        var escaping = false
        var tokenStarted = false

        for character in command {
            if escaping {
                if character == "\n" || character == "\r" {
                    escaping = false
                    continue
                }
                current.append(character)
                tokenStarted = true
                escaping = false
                continue
            }

            if character == "\\" && quote != .single {
                escaping = true
                tokenStarted = true
                continue
            }

            switch quote {
            case .single:
                if character == "'" { quote = nil } else { current.append(character) }
                tokenStarted = true
            case .double:
                if character == "\"" { quote = nil } else { current.append(character) }
                tokenStarted = true
            case nil:
                if character == "'" {
                    quote = .single
                    tokenStarted = true
                } else if character == "\"" {
                    quote = .double
                    tokenStarted = true
                } else if character.isWhitespace {
                    if tokenStarted {
                        tokens.append(current)
                        current = ""
                        tokenStarted = false
                    }
                } else {
                    current.append(character)
                    tokenStarted = true
                }
            }
        }

        guard quote == nil, !escaping else {
            throw RelayCurlImportParseError.malformedQuoting
        }
        if tokenStarted { tokens.append(current) }
        return tokens
    }

    private func parseHeader(_ raw: String) -> (String, String)? {
        guard let separator = raw.firstIndex(of: ":") else { return nil }
        let name = raw[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw[raw.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else { return nil }
        return (name, value)
    }

    private func lastHeaderValue(named name: String, in headers: [(String, String)]) -> String? {
        headers.last(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame })?.1
    }

    private func normalizeAccessToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        if parts.count == 2, parts[0].caseInsensitiveCompare("Bearer") == .orderedSame {
            return nonEmpty(String(parts[1]))
        }
        return trimmed
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeURL(_ value: String) -> Bool {
        value.contains("://")
    }

    private func normalizedEndpointPath(_ path: String) -> String {
        var normalized = path.isEmpty ? "/" : path
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}

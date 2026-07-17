import Foundation

/**
 * [INPUT]: 依赖 Codex auth 文件路径解析与显式外部 Keychain writer。
 * [OUTPUT]: 对外提供磁盘当前认证读取、指纹计算和用户账户切换写事务。
 * [POS]: Services 的 Codex Desktop 认证边界；后台同步仅读文件，显式切换才写外部 Keychain。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum CodexDesktopAuthError: LocalizedError {
    case invalidProfile
    case noWritableAuthPath
    case fileWriteFailed(String)
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return "Invalid Codex auth profile"
        case .noWritableAuthPath:
            return "Unable to locate a writable Codex auth.json path"
        case .fileWriteFailed(let path):
            return "Failed to write Codex auth.json at \(path)"
        case .keychainWriteFailed:
            return "Failed to update Codex Auth keychain entry"
        }
    }
}

final class CodexDesktopAuthService {
    private let fileManager: FileManager
    private let homeDirectory: () -> String
    private let environment: () -> [String: String]
    private let keychainWriter: (String) -> Bool

    init(
        fileManager: FileManager = .default,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        keychainReader: @escaping () -> String? = { nil },
        keychainWriter: @escaping (String) -> Bool = { value in
            SecurityCredentialReader.saveGenericPassword(service: "Codex Auth", text: value)
        }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
        _ = keychainReader
        self.keychainWriter = keychainWriter
    }

    func resolvedAuthPaths() -> [String] {
        CodexAuthPathResolver.resolveAuthPaths(
            homeDirectory: homeDirectory(),
            environment: environment()
        )
    }

    func currentAuthJSON() -> String? {
        for path in resolvedAuthPaths() where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    func currentCredentialFingerprint() -> String? {
        guard let raw = currentAuthJSON(),
              let payload = try? CodexAccountProfileStore.parseAuthJSON(raw) else {
            return nil
        }
        return payload.credentialFingerprint
    }

    func applyProfile(_ profile: CodexAccountProfile) throws {
        guard !profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? CodexAccountProfileStore.parseAuthJSON(profile.authJSON)) != nil else {
            throw CodexDesktopAuthError.invalidProfile
        }

        let existingPaths = resolvedAuthPaths().filter { fileManager.fileExists(atPath: $0) }
        let targets = existingPaths.isEmpty ? Array(resolvedAuthPaths().prefix(1)) : existingPaths
        guard !targets.isEmpty else {
            throw CodexDesktopAuthError.noWritableAuthPath
        }

        for path in targets {
            let url = URL(fileURLWithPath: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = profile.authJSON.data(using: .utf8) else {
                    throw CodexDesktopAuthError.invalidProfile
                }
                try data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                throw CodexDesktopAuthError.fileWriteFailed(path)
            }
        }

        guard keychainWriter(profile.authJSON) else {
            throw CodexDesktopAuthError.keychainWriteFailed
        }
    }
}

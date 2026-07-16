# Tests/OhMyUsageTests/
> L2 | 父级: ../../CLAUDE.md

成员清单（凭据与系统边界）

SecurityCredentialReaderTests.swift: 验证 `SecurityCredentialReader` 在 XCTest 环境默认短路，不读取真实 macOS Keychain，也不通过 Security framework 或 `/usr/bin/security` 写入开发机钥匙串。
TestKeychainHelpers.swift: 为 Provider 与凭据测试提供 file-backed `KeychainService` 临时存储，避免测试依赖系统钥匙串。
KeychainServiceTests.swift: 以注入的 `SecureStoreAdapter` 验证 vault、历史 service 迁移、交互式准备、非交互优先、幂等重复准备与凭据长度元数据，不触达真实 Keychain。
CredentialAccessServiceTests.swift: 验证显示态凭据长度、缺失缓存与后台 lookup 策略，保护设置 UI 不因展示状态触发 secure store 读取。

边界

- 默认 `swift test` 不允许触达真实 macOS Keychain；需要系统钥匙串行为时必须通过 fake adapter 或显式 opt-in 的独立集成测试承载。
- 测试文件新增时优先补充最邻近的 L3 头部契约；涉及系统资源、网络、文件或进程边界的测试必须说明隔离策略。
- 大规模测试成员清单暂按领域分段生长，避免实习生式罗列所有文件；新增分段时保持职责边界清晰。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

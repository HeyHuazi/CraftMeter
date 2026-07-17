# Models/
> L2 | 父级: ../../CLAUDE.md

成员清单

AppConfig+SiteDefaultsMigration.swift: AppConfig 站点默认值迁移入口。
AppConfigModels.swift: 应用配置聚合与持久化数据结构；菜单栏展示使用 `StatusBarDisplayStyle` 四种互斥选择，历史样式另存今日、本周、本月、全部单一周期，旧配置保持原样式与全部周期默认值。
AppConfigSiteDefaultsMigrator.swift: 旧站点配置规范化迁移器。
AuthConfig+CredentialHelpers.swift: 认证配置的凭证辅助能力。
KimiProviderConfigModels.swift: Kimi Provider 专用配置模型。
OfficialAccountProfileModels.swift: 官方账号档案与槽位模型。
OfficialProfileNaming.swift: 官方账号显示名称规则。
OfficialProviderDefaultCatalog.swift: 官方 Provider 默认配置目录。
OfficialRelayMetadataCatalog.swift: 官方 Relay 元数据目录。
OfficialRelayProviderDefaultCatalog.swift: 官方 Relay Provider 默认配置目录。
OfficialSnapshotIdentityMetadata.swift: 官方额度快照的账号身份元数据。
ProviderCapabilityMetadataCatalog.swift: Provider 能力声明目录。
ProviderDefaultCatalog.swift: Provider 默认配置统一入口。
ProviderDescriptor+Defaults.swift: ProviderDescriptor 默认值扩展。
ProviderDescriptor+DisplayPreferences.swift: Provider 显示偏好扩展。
ProviderDescriptor+LegacyDefaults.swift: 历史默认配置兼容扩展。
ProviderDescriptor+LegacyRelayMigration.swift: 历史 Relay 描述迁移扩展。
ProviderDescriptor+Normalization.swift: ProviderDescriptor 规范化扩展。
ProviderDescriptor+OfficialDefaults.swift: 官方 Provider 默认值扩展。
ProviderDescriptor+OfficialRelayMetadata.swift: 官方 Relay 元数据扩展。
ProviderDescriptor+RelayDefaults.swift: Relay 默认值扩展。
ProviderDescriptor+RelayOverrideMigration.swift: Relay 覆盖项迁移扩展。
ProviderDescriptor+RelayViewConfig.swift: Relay 界面配置投影扩展。
ProviderDescriptorNormalizer.swift: Provider 描述规范化器。
ProviderIdentityModels.swift: Provider 与账号身份值对象。
ProviderMetadataCatalog.swift: Provider 基础元数据目录。
ProviderModels.swift: Provider 配置与运行时共享模型。
ProviderPresentationMetadataCatalog.swift: Provider 展示元数据目录。
ProviderPresentationModels.swift: Provider 界面展示值对象。
ProviderSettingsMetadataCatalog.swift: Provider 设置字段元数据目录。
ProviderSettingsSpec.swift: Provider 设置能力规格。
ProviderTypeMetadataCatalog.swift: Provider 类型元数据目录。
RelayIconMetadataCatalog.swift: Relay 图标映射目录。
RelayProviderDefaultCatalog.swift: Relay Provider 默认配置目录。
RelaySettingsDraftSeed.swift: Relay 设置草稿初始化规则。
RelaySnapshotDisplayMetadata.swift: Relay 快照展示元数据。
SettingsDraftModels.swift: 设置导航、权限提示、编辑草稿与弹窗状态边界；New API 草稿只保存脱敏浏览器/cURL 导入状态和验证结果，绝不保存原始 cURL、Cookie 或 Bearer。
UsageSnapshotModels.swift: Relay 连接诊断、额度预览与浏览器导入工作流展示契约，禁止携带原始 Cookie/Bearer。

设计边界

- 模型只表达配置、身份、导航与展示契约，不执行网络、文件 IO 或 SwiftUI 渲染。
- 默认目录与迁移器分离；历史兼容逻辑不得污染新的规范模型。
- SettingsTab 必须与 UI/Settings 的内容路由和侧边栏展示保持穷尽一致。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

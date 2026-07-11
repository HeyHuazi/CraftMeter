# Settings/
> L2 | 父级: ../../../CLAUDE.md

成员清单

GeneralSettingsView.swift: 通用设置页面入口，承载应用基础行为偏好。
LocalDataSettingsView.swift: 本地数据发现与清理页面入口。
MenuBarSettingsView.swift: 菜单栏显示偏好页面入口。
OfficialProviderDetailCardView.swift: 官方 Provider 详情卡片容器。
OfficialProviderSettingsView.swift: 官方 Provider 设置页面入口。
PermissionsSettingsView.swift: 系统权限状态与授权操作页面。
ProviderSettingsRows.swift: Provider 配置的共享行组件。
RelayProviderSettingsView.swift: 中转与第三方 Provider 设置页面入口。
SettingsClockAndActions.swift: 设置页可见时钟与操作派发扩展。
SettingsControlPrimitives.swift: 设置表单控件原语。
SettingsDialogsHostView.swift: 设置弹窗宿主与覆盖层装配。
SettingsGeneralAndMenuBarSections.swift: 通用与菜单栏设置分区实现；展示样式提供四种互斥卡片，历史卡片复用真实菜单栏机器人图标与单值布局，历史样式可单选今日、本周、本月或全历史累计。
SettingsHeaderView.swift: 设置内容区标题组件。
SettingsLocalUsageTrend.swift: 本地用量趋势展示与交互。
SettingsOfficialDetailedData.swift: 官方 Provider 详细数据展示。
SettingsOfficialProfileManagement.swift: 官方账号档案管理交互。
SettingsOfficialProviderConfiguration.swift: 官方 Provider 配置表单与动作。
SettingsOverlayPresenter.swift: 设置覆盖层的纯展示决策。
SettingsOverviewView.swift: 设置工作台概览页面。
SettingsPaneContainersView.swift: 设置详情面板的布局容器。
SettingsPermissionAndLocalData.swift: 权限与本地数据管理分区实现。
SettingsProfileDialogs.swift: 官方账号编辑弹窗实现。
SettingsProviderConfigurationFacade.swift: Provider 配置能力的界面门面；透传脱敏 Relay 浏览器导入结果，不向 SwiftUI 暴露原始 Cookie/Bearer。
SettingsProviderConfigurationPresentation.swift: Provider 配置的纯展示模型。
SettingsProviderDetailPaneView.swift: Provider 详情面板路由。
SettingsProviderDetailSections.swift: Provider 详情分区组件。
SettingsProviderSidebar.swift: Provider 分组与账号侧边栏。
SettingsQuotaDisplayHelpers.swift: 额度展示格式与辅助视图。
SettingsRelayConfigurationForm.swift: Relay 配置编辑与新增表单；新增流程支持浏览器凭据预检、缺失 User ID 提示、真实连接验证，并只允许手工凭据或验证成功结果保存。
SettingsRelayRuntimeStatus.swift: Relay 运行状态与测试反馈展示。
SettingsRelayTemplateSupport.swift: Relay 模板选择与预填支持；负责新增 Provider 的最终提交，并在浏览器验证后的用户确认阶段触发凭据持久化刷新。
SettingsResetDialogView.swift: 本地数据重置确认界面。
SettingsRootView.swift: 设置窗口根布局与覆盖层容器。
SettingsSharedHelpers.swift: 设置界面共享辅助能力。
SettingsSharedTypes.swift: 设置 UI 共享值类型。
SettingsShellView.swift: 工作台侧边栏与内容区壳层。
SettingsSidebarView.swift: 通用设置侧边栏组件。
SettingsTabContentView.swift: SettingsTab 到具体页面的穷尽内容路由器。
SettingsTheme.swift: 设置界面主题值对象。
SettingsThresholdControls.swift: 阈值配置控件。
SettingsViewShell.swift: SettingsView 生命周期、导航与页面装配层。
SettingsViewTheme.swift: SettingsView 的主题解析扩展。
SettingsVisualTokens.swift: 设置界面尺寸、颜色与视觉常量。
SettingsWindowAppearanceController.swift: 设置窗口外观控制器。
SettingsWorkspacePresentation.swift: 设置页头与侧边栏的纯展示模型构建器。
SettingsWorkspaceSidebarView.swift: 工作台侧边栏渲染与底部操作区。
ThirdPartyProviderDetailCardView.swift: 第三方 Provider 详情卡片容器。
UsageAnalyticsFacetViews.swift: typed Craft facet 的覆盖率排行展示；显式允许重叠归因，不将各项强制归一化。
UsageAnalyticsFilterBar.swift: 历史统计的客户端、Provider、项目、模型与 typed Craft facet 组合筛选条；只绑定 filter，不承载聚合策略。
UsageAnalyticsModelBrandPresentation.swift: 使用统计模型品牌的纯展示解析器与紧凑图标组件；优先复用 bundled 资源，Qwen 专属资源来自 MIT 许可的 Lobe Icons，遇到歧义回退通用图标。
UsageAnalyticsSettingsView.swift: 本地历史用量统计页面编排；展示总览、统一筛选口径趋势、客户端/Provider/项目/模型统计与可重叠 Craft 活动覆盖率，并区分上游报告、Models.dev 估算、部分定价下界和完全未知费用。
UsageAnalyticsStatisticsViews.swift: 使用统计的环形图、品牌图例与维度明细表；模型行消费品牌展示元数据，不参与事实归属判断。

设计边界

- 导航标签只描述真实可达页面；删除页面必须同步 SettingsTab、内容路由、侧边栏展示与测试。
- 展示模型保持纯函数，窗口生命周期与业务动作集中在 SettingsViewShell。
- Provider 配置组件复用共享原语，禁止在页面内复制认证、额度或状态逻辑。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

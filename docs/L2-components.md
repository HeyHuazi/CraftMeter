L2 模块地图

# Sources/CraftMeterApp/Components/

## 职责
SwiftUI 纯展示组件集合，构成 380×500 popover 的视觉层。主信息架构为 Overview → Activity → TopBurn：结论、证据、归因。零业务逻辑；drill-down 通过回调上抛，由 StatsView 路由到 SessionDetail overlay。

## 成员清单
- Palette.swift: 多色语义字典 + Detail enum（drill-down 路由目标）；Today 橙 / Total 绿 / Tokens 紫 / 异常 红 / workspace 稳定 djb2 hash → 8 色 palette
- OverviewSection.swift: Today burn hero + Total/Billable metric strip；首屏直接回答"今天烧得是否异常"
- ActivitySection.swift: 30 日 trend + spike count + HeatmapCalendarView；时间证据归一到单一区域
- TopBurnSection.swift: Sessions/Models/Workspaces 三段式 segmented attribution panel；单一区域回答"谁在燃烧"；模型行使用 `ModelTier.hueFraction` 语义色（opus=红/sonnet=黄/haiku=绿/other=蓝）
- SessionDetail.swift: drill-down overlay 终点；单 session 渲染详情，列表型目标通过私有 SessionQuery 统一 all/day/workspace 筛选与 billable 排序
- HeatmapCalendarView.swift: 365 天 GitHub 风格使用热力图（7×53 网格，月/日标签，父宽度自适应 cell/gap，Palette.tokens 四档百分位 opacity，@ViewBuilder 保留 SwiftUI 类型结构，点击 drill-down 到当日 sessions）

## 公开 API
- Palette.{today,total,tokens,anomaly} / Palette.workspace(_:)
- Detail enum（StatsView 持有 @State）
- OverviewSection / ActivitySection / TopBurnSection 接受 `Stats` + drill-down 回调

## 依赖
- SwiftUI
- CraftMeterCore（Format / Stats / SessionRecord / WorkspaceStat / DayBucket）

## 法则
- 永不持有跨视图 @State（hover 类局部 state OK）
- 色彩承担分类信号——色彩语义集中在 Palette，禁止散落 if/else
- 不引入图表库（自绘 RoundedRectangle 即可）
- 首屏遵循"结论 → 证据 → 归因"，避免 Divider 把认知切碎
- 嵌套卡片内组件必须服从父容器宽度；HeatmapCalendarView 不再使用固定 371px 几何假设
- drill-down 通过 closure 上抛，列表型 Detail 在 SessionDetail 内归一为 SessionQuery，避免筛选排序分支扩散

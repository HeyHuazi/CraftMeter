L2 模块地图

# Sources/CraftMeterCore/

## 职责
纯数据层 + 唯一 IO 边界。被 GUI/CLI 两个可执行目标共享，零依赖外部框架（仅 Foundation）。

## 成员清单
- Domain.swift: SessionRecord 解析 + Stats 聚合，单次遍历 O(N)，纯函数无副作用；含 billableTokens 语义（input + output + cacheCreation，剔除 cacheRead）；aggregate() 同步累积三组透视：workspace、model、daily；双 cutoff：29d → dailyBuckets30d，364d → heatmapDays（365 天周日起始网格）
- Store.swift: 文件系统扫描 + cache.json envelope（cacheVersion=4）读写，Store 为不可变 Sendable struct
- Format.swift: 共用格式化工具（tokens / cost / percent），消除 CLI/UI 各自重复

## 公开 API
- `SessionRecord.from(firstLine:)` / `.from(jsonLine:)` — 解析单条 session
- `aggregate(records:now:)` — 生成完整 Stats（含 records 透传 + totalBillableTokens + top5ByBillable + workspaceBreakdown + modelBreakdown + dailyBuckets30d + heatmapDays）
- `Store.refresh(scannedBy:)` — 扫盘 → 聚合 → 落盘 cache，单一入口；scannedBy 默认 "app"，CLI 传 "cli"
- `Store.readCache()` — 启动时秒开；cacheVersion 不匹配返回 nil
- `Store.currentCacheVersion` — 当前 cache schema 版本（=4）
- `Stats.with(malformedCount:scannedBy:)` — 不可变 Stats 的"修改"出口
- `Format.tokens(_:)` / `Format.cost(cents:)` / `Format.percent(_:)` — 共用格式化
- `SessionRecord`/`Stats`/`DayBucket`/`WorkspaceStat` — 公开数据类型

## 依赖
- Foundation（FileManager, JSONDecoder, JSONEncoder）
- 无第三方

## 法则
- 永不引入第三方依赖（消除特殊 case 的根本路径）
- IO 只能在 Store 出现，Domain 必须纯函数
- 货币用 Int cents 聚合，绝不用 Double/F64 累加
- token 排序真相源是 billableTokens，永远排除 cacheReadTokens
- cache schema 演进：CacheEnvelope.cacheVersion 比对，老版本当 nil 触发全量 rescan
- malformed 文件计数但不阻断扫描

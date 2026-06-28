L2 模块地图

# Sources/meter/

## 职责
命令行可执行目标 `meter`。复用 Core 的 Store.refresh() + aggregate()，渲染纯文本或 JSON 到 stdout。支持 filter / 时间窗 / JSON 输出，零参数行为向后兼容。

## 成员清单
- main.swift: 参数解析（手写，无第三方 ArgumentParser）+ filter + render(stats:) + barChart + jsonEncode(stats:)

## 参数
- `--workspace NAME`    按 workspace basename 过滤
- `--model NAME`        按 model id 过滤
- `--label NAME`        按 label tag 过滤
- `--since 7d`          按最近 N 天过滤
- `--since YYYY-MM-DD`  按起始日期过滤
- `--json`              JSON 输出（替代默认文本）
- `-h, --help`          帮助

## 公开 API
- 退出码: 0=成功 1=参数错误 2=无数据
- stdout：默认四段（总账 / Model breakdown / Top 5 / 30 日趋势）；--json 时为结构化 JSON（新增 modelBreakdown 字段）

## 依赖
- Foundation
- CraftMeterCore（Store / aggregate / Format）

## 法则
- 零交互（不接受 stdin 输入）
- 一次性执行（无 timer / 无 daemon）
- 全部参数可选；零参数 = 兼容 v1 行为
- 输出格式与 GUI 同源（同一份 Stats 派生）

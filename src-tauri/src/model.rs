// Shared data structures returned to the frontend.
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct SeriesPoint {
    pub label: String,  // sparse axis label (many empty)
    pub full: String,   // complete label for the hover tooltip (hour / date)
    pub input: f64,     // M tokens (uncached new input)
    pub cache: f64,     // M tokens (cache creation + read)
    pub output: f64,    // M tokens
    pub reasoning: f64, // M tokens (reasoning/thinking output)
}

#[derive(Debug, Clone, Serialize)]
pub struct ModelStat {
    pub name: String,
    pub vendor: String,
    pub tokens: f64, // M tokens (input+output, weighted)
    pub cost: f64,   // USD estimate
    pub color: String,
    pub priced: bool, // false = no pricing data in LiteLLM (cost is unknown, not $0)
}

#[derive(Debug, Clone, Serialize)]
pub struct NamedCount {
    pub name: String,
    pub count: u64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct Metrics {
    #[serde(rename = "totalTokens")]
    pub total_tokens: f64,
    #[serde(rename = "inputTokens")]
    pub input_tokens: f64,
    #[serde(rename = "cacheTokens")]
    pub cache_tokens: f64,
    #[serde(rename = "outputTokens")]
    pub output_tokens: f64,
    #[serde(rename = "reasoningTokens")]
    pub reasoning_tokens: f64,
    pub cost: f64,
    #[serde(rename = "mcpCalls")]
    pub mcp_calls: u64,
    #[serde(rename = "skillCalls")]
    pub skill_calls: u64,
    pub requests: u64,
    pub sessions: u64,
    #[serde(rename = "deltaTokens")]
    pub delta_tokens: f64,
    #[serde(rename = "deltaCost")]
    pub delta_cost: f64,
    pub servers: u64,
    pub skills: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientUsageStat {
    pub id: String,
    pub label: String,
    pub total_tokens: f64,
    pub input_tokens: f64,
    pub cache_tokens: f64,
    pub output_tokens: f64,
    pub reasoning_tokens: f64,
    pub cost: f64,
    pub requests: u64,
    pub sessions: u64,
    pub priced: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CraftToolStat {
    pub name: String,
    pub display_name: String,
    pub category: String,
    pub call_count: u64,
    pub error_count: u64,
    pub completed_count: u64,
    pub executing_count: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CraftSourceStat {
    pub slug: String,
    pub session_count: u64,
    pub total_tokens: f64,
    pub billable_tokens: f64,
    pub cost_cents: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CraftCategoryStat {
    pub category: String,
    pub call_count: u64,
    pub error_count: u64,
    pub completed_count: u64,
    pub executing_count: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CraftStatusStat {
    pub status: String,
    pub call_count: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CraftSessionFacetStat {
    pub value: String,
    pub session_count: u64,
    pub billable_tokens: f64,
    pub cost_cents: u64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ProjectStat {
    pub name: String,
    pub total_tokens: f64,
    pub cost: f64,
    pub requests: u64,
    pub sessions: u64,
    pub priced: bool,
}

#[derive(Debug, Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SessionMetrics {
    pub duration_seconds: u64,
    pub active_seconds: u64,
    pub message_count: u64,
    pub user_message_count: u64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct CraftAgentReport {
    pub tools: Vec<CraftToolStat>,
    pub sources: Vec<CraftSourceStat>,
    pub categories: Vec<CraftCategoryStat>,
    pub status: Vec<CraftStatusStat>,
    pub permission: Vec<CraftSessionFacetStat>,
    pub thinking: Vec<CraftSessionFacetStat>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PeriodWindow {
    pub offset: i32,
    pub label: String,
    pub start: String,
    pub end: String,
    pub is_current: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct PeriodReport {
    pub window: PeriodWindow,
    pub metrics: Metrics,
    pub series: Vec<SeriesPoint>,
    pub models: Vec<ModelStat>,
    pub clients: Vec<ClientUsageStat>,
    pub projects: Vec<ProjectStat>,
    pub mcp: Vec<NamedCount>,
    pub skills: Vec<NamedCount>,
    #[serde(rename = "reqTrend")]
    pub req_trend: Vec<f64>,
    #[serde(rename = "costTrend")]
    pub cost_trend: Vec<f64>,
    pub craft: CraftAgentReport,
    #[serde(rename = "sessionMetrics")]
    pub session_metrics: SessionMetrics,
}

#[derive(Debug, Clone, Serialize)]
pub struct HeatDay {
    pub date: String, // ISO yyyy-mm-dd
    pub tokens: f64,  // M tokens
    pub level: u8,    // 0..4
}

#[derive(Debug, Clone, Serialize)]
pub struct Dashboard {
    pub day: PeriodReport,
    pub week: PeriodReport,
    pub month: PeriodReport,
    pub heatmap: Vec<HeatDay>,
    #[serde(rename = "todayTokens")]
    pub today_tokens: f64, // M tokens, for the tray label
    #[serde(rename = "generatedAt")]
    pub generated_at: String,
}

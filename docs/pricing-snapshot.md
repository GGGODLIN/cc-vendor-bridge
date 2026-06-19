# Pricing Snapshot

Vendor pricing reference for cc-vendor-bridge. **Per-vendor `LAST_VERIFIED` table below — check before quoting any number.** Stale rows kept for structural reference (endpoint URL, tier shape, KYC), but the numbers themselves are not safe to cite until re-verified.

USD conversions for CNY ≈ 7.15 CNY/USD.

## LAST_VERIFIED

| Vendor / Surface | Last verified | Source | Status |
|---|---|---|---|
| DeepSeek V4 family PAYG | 2026-06-19 | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing) | ✅ current |
| GLM-5.2 PAYG + Coding Plan | 2026-06-19 | [docs.z.ai/devpack/overview](https://docs.z.ai/devpack/overview) + [z.ai/subscribe](https://z.ai/subscribe) + [docs.z.ai/devpack/tool/claude](https://docs.z.ai/devpack/tool/claude) | ✅ current |
| MiMo V2.5 family PAYG + Token Plan | 2026-06-19 | [mimo.mi.com/docs/en-US/price/pay-as-you-go](https://mimo.mi.com/docs/en-US/price/pay-as-you-go) + [mimo.mi.com/docs/en-US/price/token-plan](https://mimo.mi.com/docs/en-US/price/token-plan) | ✅ current |
| Kimi K2.6 / K2-thinking | 2026-05-03 | platform.kimi.com docs | ⚠️ stale — re-verify before quoting |
| Qwen3.5 / Qwen3.6 / Qwen3-Coder | 2026-05-03 | alibabacloud.com | ⚠️ stale — re-verify before quoting |
| MiniMax M2.7 | 2026-05-03 | openrouter.ai/minimax (no official PAYG page found) | ⚠️ stale — re-verify before quoting |
| Hunyuan T1 | 2026-05-03 | cloud.tencent.com | ⚠️ stale — re-verify before quoting |
| ERNIE 4.5 Turbo | 2026-05-03 | cloud.baidu.com | ⚠️ stale — re-verify before quoting |
| Doubao Seed | 2026-05-03 | volcengine.com | ⚠️ stale + incomplete — re-verify before quoting |

**Stale-by rule**: any row >30 days from `Last verified` must be re-verified against the linked source before being cited in a decision. See [[feedback_doc_audit_staleness_rule]] (memory).

---

## 1. Per-token pricing — PAYG

### ✅ Verified 2026-06-19

| Model | Context | Input cache miss USD/1M | Input cache hit USD/1M | Output USD/1M | Notes |
|---|---|---|---|---|---|
| **DeepSeek V4-Flash** | 1M / 384K out | $0.14 | $0.0028 | $0.28 | also legacy alias for `deepseek-chat` (non-thinking) + `deepseek-reasoner` (thinking) until 2026-07-24 |
| **DeepSeek V4-Pro** | 1M / 384K out | **$0.435** | **$0.003625** | **$0.87** | flat tier — old UTC 16:30–00:30 off-peak discount **removed**. Concurrency cap 500. |
| **MiMo V2.5-Pro** | 1M / 128K out | **$0.435** | **$0.0036** | **$0.87** | **same as DeepSeek V4-Pro**. RPM 100 / TPM 10M. Off-peak (台灣 00:00-08:00) 0.8× |
| **MiMo V2.5** | 1M / 128K out | $0.14 | $0.0028 | $0.28 | omni/full-modal understanding |
| **GLM-5.2** | 1M (model id `glm-5.2[1m]`) / 131K out | $1.40 | **$0.26** (-81%) | $4.40 | reasoning effort `low/medium/high/max`. Verbosity ~42k tok/task (1.6× of 5.1) |
| **GLM-4.7** | 200K | $0.60 | $0.11 (-82%) | $2.20 | 性價比 sweet spot for routine coding |
| **GLM-4.7-Flash** | 200K | $0.07 | $0.01 (-86%) | $0.40 | cheapest GLM tier |

### ⚠️ Stale 2026-05-03 — re-verify before quoting

| Model | Context | Input USD/1M | Output USD/1M | Cache | Notes | Source |
|---|---|---|---|---|---|---|
| Kimi K2.6 | 256K | ¥6.50 ≈ $0.91 / hit ¥1.10 ≈ $0.15 | ¥27 ≈ $3.78 | auto context cache | OpenRouter shows $0.74/$3.49 (cheaper) | [platform.kimi.com/docs/pricing/chat-k26](https://platform.kimi.com/docs/pricing/chat-k26) |
| Kimi K2-thinking | 256K | ¥4 / hit ¥1 | ¥16 | hit rate | EOL 2026-05-25 (likely gone) | [platform.kimi.com/docs/pricing/chat-k2](https://platform.kimi.com/docs/pricing/chat-k2) |
| Qwen3.5-Plus | 1M | $0.40 | $2.40 | tiered | | [alibabacloud.com](https://www.alibabacloud.com/help/en/model-studio/models) |
| Qwen3.5-Flash | 1M | $0.10 | $0.40 | tiered | | same |
| Qwen3-Max | 262K | $1.20 | $6.00 | std | thinking 唯一支援系列 | same |
| Qwen3-Coder-Plus | 1M | $1.00 | $5.00 | 10–20% | | same |
| MiniMax M2.7 | n/a | $0.30 | $1.20 | n/a | 官方 LLM token 價拿不到，OR 唯一來源 | [openrouter.ai/minimax](https://openrouter.ai/minimax) |
| Hunyuan T1 | std | ¥1 ≈ $0.14 | ¥4 ≈ $0.56 | n/a | | [cloud.tencent.com](https://cloud.tencent.com/document/product/1729/97731) |
| ERNIE 4.5 Turbo | — | ¥0.80 ≈ $0.11 | ¥3.20 ≈ $0.45 | hit ¥0.20 | | [cloud.baidu.com](https://cloud.baidu.com/doc/qianfan/s/wmh4sv6ya) |
| Doubao Seed | — | — | — | — | 官方 docs JS render，需手動查 console | [volcengine](https://www.volcengine.com/docs/82379/1099320) |

---

## 2. Subscription / Coding plans

### ✅ Verified 2026-06-19

#### Zhipu z.ai — GLM Coding Plan

| Tier | Monthly | Yearly (-30%) | 5h limit | Weekly limit | Concurrency |
|---|---|---|---|---|---|
| Lite | $18 | $151.2/yr ($12.6/mo) | ~80 prompts | ~400 prompts | (lowest, tier-relative) |
| Pro | **$72** | $604.8/yr ($50.4/mo) | ~400 prompts | ~2,000 prompts | mid |
| Max | **$160** | $1,344/yr ($112/mo) | ~1,600 prompts | ~8,000 prompts | highest |

- Quarterly toggle shows both `-10%` and `-20%` indicators; need to click toggle to confirm — not verified.
- All tiers include GLM-5.2 / GLM-5-Turbo / GLM-4.7 (no tier-rationed model access).
- **Peak multiplier (UTC+8 14:00-18:00)**: GLM-5.2 / GLM-5-Turbo 3× ; GLM-4.7 1× (no multiplier).
- **Off-peak multiplier**: 2× standard, **1× during promo period until end of September** (year not explicit on page).
- 1 "prompt" = one user message; each prompt internally invokes model 15–20 times (tool calls all included).
- Hard tool whitelist: CC / Cline / OpenCode only; other SDKs charged to wallet, not subscription quota.
- Quota exhaustion behavior: undocumented for main model (MCP tools explicitly hard-stop until next cycle).
- Cancellation: 3 days before billing date. **No refund policy stated.**

#### Xiaomi MiMo — Token Plan

| Tier | Monthly | Yearly (-12%) | Monthly Credits |
|---|---|---|---|
| Lite | $6 | $63.36/yr | 4.1B |
| Standard | $16 | $168.96/yr | 11B |
| Pro | $50 | $528/yr | 38B |
| Max | $100 | $1,056/yr | 82B |

**Credits per token** (V2.5-Pro):
- Cache hit input: 2.5 credits
- Cache miss input: 300 credits
- Output: 600 credits

**Credits per token** (V2.5):
- Cache hit: 2 / Cache miss: 100 / Output: 200

**Off-peak discount**: 0.8× consumption during Beijing 00:00-08:00 (台灣同時段). For Taiwan users, only useful if running overnight batches.

**Endpoint clusters** (Anthropic-compat):
- CN: `https://token-plan-cn.xiaomimimo.com/anthropic`
- **SGP**: `https://token-plan-sgp.xiaomimimo.com/anthropic` ← what cc-vendor-bridge ccp-mimo uses
- AMS: `https://token-plan-ams.xiaomimimo.com/anthropic`

**Quota exhaustion**: hard stop. Token Plan keys (`tp-xxxxx`) and PAYG keys (`sk-xxxxx`) are isolated — no auto fallback. Manual switch to PAYG key required.

**Refund**: **none** once subscription activated. Auto-renewal opt-in only, cancel anytime.

**100T Token Incentive Plan**: **ended 2026-05-28** (no replacement promo as of 2026-06-19).

**First-purchase 12% off**: monthly tier only, once per account, doesn't apply to annual.

#### DeepSeek

No subscription. PAYG only. **No new-user free credit visible on pricing page** (page mentions a "granted balance" concept exists but doesn't describe acquisition).

### ⚠️ Stale 2026-05-03 — re-verify before quoting

| Vendor | Plan | Price | Quota | Notes |
|---|---|---|---|---|
| Alibaba | Qwen Coding Plan | n/a (separate URL) | 獨立 quota pool | endpoint = `coding-intl.dashscope.aliyuncs.com` |
| Kimi | Kimi Code subscription | n/a | n/a | endpoint = `api.kimi.com/coding/`，model 名不釘 |
| MiniMax | Token Plan Starter/Plus/Max | $10 / $20 / $50 /mo | n/a | Highspeed variants at higher prices |
| Volcengine | Doubao Coding Plan | ¥40 / ¥200 /mo | n/a | Chinese KYC required; **no international sign-up path** |

---

## 3. Endpoint reference (Anthropic-compatible)

| Vendor | Endpoint | Status |
|---|---|---|
| DeepSeek (all V4) | `https://api.deepseek.com/anthropic` | ✅ 2026-06-19 |
| GLM Coding Plan (CC) | `https://api.z.ai/api/anthropic` | ✅ 2026-06-19 |
| MiMo PAYG (overseas) | `https://api.xiaomimimo.com/anthropic` | ✅ 2026-06-19 |
| MiMo Token Plan CN | `https://token-plan-cn.xiaomimimo.com/anthropic` | ✅ 2026-06-19 |
| MiMo Token Plan SGP | `https://token-plan-sgp.xiaomimimo.com/anthropic` | ✅ 2026-06-19 |
| MiMo Token Plan AMS | `https://token-plan-ams.xiaomimimo.com/anthropic` | ✅ 2026-06-19 |
| Kimi PAYG | `https://api.moonshot.ai/anthropic` | ⚠️ stale 2026-05-03 |
| Kimi Subscription | `https://api.kimi.com/coding/` | ⚠️ stale 2026-05-03 |
| MiniMax | `https://api.minimax.io/anthropic` | ⚠️ stale 2026-05-03 |
| Volcengine | `https://ark.cn-beijing.volces.com/api/coding` | ⚠️ stale 2026-05-03 |

---

## 4. CC Context Window Alignment (CC defaults 200K — needs override per vendor)

| Model | Real Context | Activation in CC | Workaround |
|---|---|---|---|
| GLM-5.2 | 1M | model id suffix `glm-5.2[1m]` | + `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000` |
| GLM-4.7 / 5.1 | 200K | default | none needed |
| MiniMax M2.7 | 200K | default | none needed |
| Kimi K2.5/2.6 | 256K | TBD | likely `CLAUDE_CODE_MAX_CONTEXT_TOKENS=256000` |
| MiMo V2.5-Pro | 1M (corrected from earlier 1.1M) | env var | `DISABLE_COMPACT=1` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000` |
| DeepSeek V4-Pro | 1M | env var | `DISABLE_COMPACT=1` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000` |

See `docs/caveats.md#caveat-6` for shared workaround. **Note two distinct activation mechanisms** — GLM uses model name suffix `[1m]`; everyone else uses env vars. This is caveat #13.

---

## 5. Benchmark 對照（agent / coding） — ⚠️ STALE 2026-05-03

[V] = vendor-claim 自報；[3P] = 第三方榜驗證. Numbers below have not been re-verified since 2026-05-03. GLM-5.2 (released 2026-06-13) is **not in this table** — for current GLM-5.2 benchmarks see `docs/research-2026-06-19-glm-5.2/` or workflow output `wf_8550cb5b-3be`.

| Model | SWE-V | SWE-Pro | Terminal-Bench 2 | MCPAtlas | Notes |
|---|---|---|---|---|---|
| Claude Opus 4.7 | **87.6%** | **64.3%** | 69.4% | **77.3%** | 對標基準，CN 模型沒過 80 SWE-V |
| Claude Opus 4.6 | 80.8% | 53.4% | 65.4% | 76.8% | |
| GPT-5.4 | n/a | 57.7% | (self) | 68.1% | |
| Kimi K2.6 | **80.2%** [V] | **58.6%** [V] | **66.7%** [V] | n/a | SWE-Pro 贏 GPT-5.4 |
| GLM-5.1 | (5.0 = 77.8) | **58.4%** [V] | 55%+ [V] | **75.6%** [3P] | SWE-Pro 也贏 GPT-5.4，**MCPAtlas 第三方驗證唯一 CN 上榜** |
| DeepSeek V4-Pro | 80.6% [V] | n/a | n/a | n/a | swebench.com timeout 沒交叉驗證 |
| Qwen3.6-27B / Plus | 77.2% / **78.8%** [V] | n/a | 61.6% [V] | n/a | |
| MiniMax M2.7 | (78%) [V] | **56.22%** [V] | **57.0%** [V] | n/a | |
| Doubao Seed 2.0 Pro | **76.5%** [V] | n/a | n/a | n/a | |
| Hunyuan Hy3-preview | 74.4% [V] | n/a | 54.4% [V] | n/a | |

---

## 6. Sources

### Verified 2026-06-19
- DeepSeek 官方 pricing：[api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing)
- z.ai Coding Plan: [docs.z.ai/devpack/overview](https://docs.z.ai/devpack/overview) + [z.ai/subscribe](https://z.ai/subscribe)
- z.ai Claude Code recipe: [docs.z.ai/devpack/tool/claude](https://docs.z.ai/devpack/tool/claude)
- MiMo PAYG: [mimo.mi.com/docs/en-US/price/pay-as-you-go](https://mimo.mi.com/docs/en-US/price/pay-as-you-go)
- MiMo Token Plan: [mimo.mi.com/docs/en-US/price/token-plan](https://mimo.mi.com/docs/en-US/price/token-plan)
- MiMo models: [mimo.mi.com/docs/en-US/quick-start/summary/model](https://mimo.mi.com/docs/en-US/quick-start/summary/model)
- MiMo endpoints: [mimo.mi.com/docs/en-US/quick-start/summary/first-api-call](https://mimo.mi.com/docs/en-US/quick-start/summary/first-api-call)

### Verified 2026-05-03 (stale)
- Kimi K2.6 release：[Moonshot blog](https://www.kimi.com/blog/kimi-k2-6) (verified GPQA 90.5, LiveCodeBench v6 89.6, SWE-V 80.2, SWE-Pro 58.6, Terminal-Bench 66.7)
- GLM-5.1 SWE-Pro: [ModemGuides](https://www.modemguides.com/blogs/ai-news/glm-5-1-open-source-benchmarks-local-ai)
- Scale Labs MCP-Atlas leaderboard: [labs.scale.com/leaderboard/mcp_atlas](https://labs.scale.com/leaderboard/mcp_atlas) (Muse Spark 82.2 / Opus 4.7 79.1 / GLM-5.1 75.6 / Kimi K2.5 64.4 / GLM-4.7 58.1)
- DeepSeek V4-Pro 第三方分析: [Artificial Analysis](https://artificialanalysis.ai/articles/deepseek-is-back-among-the-leading-open-weights-models-with-v4-pro-and-v4-flash)
- Qwen3.6-27B: [MarkTechPost](https://www.marktechpost.com/2026/04/22/alibaba-qwen-team-releases-qwen3-6-27b-a-dense-open-weight-model-outperforming-397b-moe-on-agentic-coding-benchmarks/)
- MiniMax M2.7: [official news](https://www.minimax.io/news/minimax-m27-en) / [MarkTechPost](https://www.marktechpost.com/2026/04/12/minimax-just-open-sourced-minimax-m2-7-a-self-evolving-agent-model-that-scores-56-22-on-swe-pro-and-57-0-on-terminal-bench-2/)
- Hunyuan: [Tencent-Hunyuan/Hy3-preview GitHub](https://github.com/Tencent-Hunyuan/Hy3-preview)
- Vellum Opus 4.7 benchmarks: [vellum.ai](https://www.vellum.ai/blog/claude-opus-4-7-benchmarks-explained)

---

## 7. ⚠️ 已知 verification gaps (2026-05-03)

- swebench.com leaderboard fetch timed out 2026-05-03 → V4-Pro / Hy3 / M2.7 / Doubao 數字仍是 vendor-claimed only
- aider.chat leaderboard 也 timeout
- MCP-Atlas 榜更新到 2026-04-08 → Kimi K2.6 / DeepSeek V4 / MiniMax M2.7 / Doubao Seed 2.0 Pro / Hunyuan Hy3 還沒進榜
- GLM-5.1 Z.ai 自報 ModemGuides flagged "independent verification still pending"
- GLM-5.2 benchmarks 待補（release 2026-06-13，第三方獨立 SWE-Bench 數字尚未上榜）

---

## 8. Changelog

- **2026-06-19**: deleted `pricing-audit.md` (contained $1.50/$4.50 抄錯數字 + redundant with this file). Refreshed DeepSeek V4 (numbers still valid, cache hit slightly cheaper at $0.003625), MiMo V2.5-Pro (降價 2026-05-27 對齊 DeepSeek，1M ctx 而非 1.1M), GLM-5.2 (replaced 5.1 旗艦標籤), MiMo Token Plan tiers. Added LAST_VERIFIED table + per-vendor staleness markers.
- **2026-05-03**: initial snapshot.

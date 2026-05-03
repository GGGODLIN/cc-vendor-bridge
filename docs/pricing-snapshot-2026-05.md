# Pricing Snapshot — 2026-05-03

**Stale-by 2026-08-03.** CN models update pricing monthly. Re-verify before quoting these numbers.

USD conversions for CNY ≈ 7.15 CNY/USD.

## Per-token pricing (官方來源)

| Model | Context | Input USD/1M | Output USD/1M | Cache | Notes | Source |
|---|---|---|---|---|---|---|
| **DeepSeek V4-Flash** | 1M | $0.14 | $0.28 | hit = 1/10 ($0.014) | cheap tier | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing) |
| **DeepSeek V4-Pro** | 1M / 384K out | $0.435 | $0.87 | hit = 1/10 | ⏰ **75% off promo to 2026-05-31** | same |
| **Kimi K2.6** | 256K | ¥6.50 ≈ $0.91 / hit ¥1.10 ≈ $0.15 | ¥27 ≈ $3.78 | auto context cache | OR 上 $0.74/$3.49 較便宜 | [platform.kimi.com/docs/pricing/chat-k26](https://platform.kimi.com/docs/pricing/chat-k26) |
| **Kimi K2-thinking** | 256K | ¥4 / hit ¥1 | ¥16 | hit rate | EOL 2026-05-25 | [platform.kimi.com/docs/pricing/chat-k2](https://platform.kimi.com/docs/pricing/chat-k2) |
| **GLM-5.1** | 200K | $1.40 | $4.40 | 81% off → $0.26 | OR 上 $1.05/$3.50 較便宜 | [docs.z.ai/guides/overview/pricing](https://docs.z.ai/guides/overview/pricing) |
| **GLM-4.7** | 200K | $0.60 | $2.20 | 82% off → $0.11 | 性價比殺手 | same |
| **GLM-4.7-Flash** | 200K | $0.07 | $0.40 | 86% off | 最便宜 | same |
| **GLM-4.6** | 200K | $0.60 | $2.20 | 82% off | 舊版 | same |
| **Qwen3.5-Plus** | 1M | $0.40 | $2.40 | tiered | | [alibabacloud.com](https://www.alibabacloud.com/help/en/model-studio/models) |
| **Qwen3.5-Flash** | 1M | $0.10 | $0.40 | tiered | | same |
| **Qwen3-Max** | 262K | $1.20 | $6.00 | std | thinking 唯一支援系列 | same |
| **Qwen3-Coder-Plus** | 1M | $1.00 | $5.00 | 10–20% | | same |
| **MiniMax M2.7** | n/a | $0.30 | $1.20 | n/a | 官方 LLM token 價拿不到，OR 唯一來源 | [openrouter.ai/minimax](https://openrouter.ai/minimax) |
| **Hunyuan T1** | std | ¥1 ≈ $0.14 | ¥4 ≈ $0.56 | n/a | | [cloud.tencent.com](https://cloud.tencent.com/document/product/1729/97731) |
| **ERNIE 4.5 Turbo** | — | ¥0.80 ≈ $0.11 | ¥3.20 ≈ $0.45 | hit ¥0.20 | | [cloud.baidu.com](https://cloud.baidu.com/doc/qianfan/s/wmh4sv6ya) |
| **Doubao Seed** | — | — | — | — | 官方 docs JS render，需手動查 console | [volcengine](https://www.volcengine.com/docs/82379/1099320) |

## Subscription / Coding plans

| Vendor | Plan | Price | Quota | Notes |
|---|---|---|---|---|
| **Zhipu z.ai** | Coding Plan Lite | < $18/月 | ~80 prompts / 5h | GLM-5.1 + GLM-5-Turbo + GLM-4.7 + GLM-4.5-Air 全支援 |
| **Zhipu z.ai** | Coding Plan Pro | $18/月 起 | ~400 prompts / 5h | premium model 3× peak / 2× off-peak |
| **Zhipu z.ai** | Coding Plan Max | n/a | ~1,600 prompts / 5h | |
| **Alibaba** | Qwen Coding Plan | n/a (separate URL) | 獨立 quota pool | endpoint = `coding-intl.dashscope.aliyuncs.com` |
| **Kimi** | Kimi Code subscription | n/a | n/a | endpoint = `api.kimi.com/coding/`，model 名不釘 |
| **DeepSeek** | — | 無訂閱 | per-token only | 全 PAYG |

## Benchmark 對照（agent / coding）

[V] = vendor-claim 自報；[3P] = 第三方榜驗證

| Model | SWE-V | SWE-Pro | Terminal-Bench 2 | MCPAtlas | Notes |
|---|---|---|---|---|---|
| **Claude Opus 4.7** | **87.6%** | **64.3%** | 69.4% | **77.3%** | 對標基準，CN 模型沒過 80 SWE-V |
| Claude Opus 4.6 | 80.8% | 53.4% | 65.4% | 76.8% | |
| GPT-5.4 | n/a | 57.7% | (self) | 68.1% | |
| **Kimi K2.6** | **80.2%** [V] | **58.6%** [V] | **66.7%** [V] | n/a | SWE-Pro 贏 GPT-5.4 |
| **GLM-5.1** | (5.0 = 77.8) | **58.4%** [V] | 55%+ [V] | **75.6%** [3P] | SWE-Pro 也贏 GPT-5.4，**MCPAtlas 第三方驗證唯一 CN 上榜** |
| **DeepSeek V4-Pro** | 80.6% [V] | n/a | n/a | n/a | swebench.com timeout 沒交叉驗證 |
| **Qwen3.6-27B / Plus** | 77.2% / **78.8%** [V] | n/a | 61.6% [V] | n/a | |
| **MiniMax M2.7** | (78%) [V] | **56.22%** [V] | **57.0%** [V] | n/a | |
| **Doubao Seed 2.0 Pro** | **76.5%** [V] | n/a | n/a | n/a | |
| **Hunyuan Hy3-preview** | 74.4% [V] | n/a | 54.4% [V] | n/a | |

## Sources

- DeepSeek 官方 pricing：[api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing)
- Kimi K2.6 release：[Moonshot blog](https://www.kimi.com/blog/kimi-k2-6) (verified GPQA 90.5, LiveCodeBench v6 89.6, SWE-V 80.2, SWE-Pro 58.6, Terminal-Bench 66.7)
- GLM-5.1 SWE-Pro: [ModemGuides](https://www.modemguides.com/blogs/ai-news/glm-5-1-open-source-benchmarks-local-ai)
- Scale Labs MCP-Atlas leaderboard: [labs.scale.com/leaderboard/mcp_atlas](https://labs.scale.com/leaderboard/mcp_atlas) (Muse Spark 82.2 / Opus 4.7 79.1 / GLM-5.1 75.6 / Kimi K2.5 64.4 / GLM-4.7 58.1)
- DeepSeek V4-Pro 第三方分析: [Artificial Analysis](https://artificialanalysis.ai/articles/deepseek-is-back-among-the-leading-open-weights-models-with-v4-pro-and-v4-flash)
- Qwen3.6-27B: [MarkTechPost](https://www.marktechpost.com/2026/04/22/alibaba-qwen-team-releases-qwen3-6-27b-a-dense-open-weight-model-outperforming-397b-moe-on-agentic-coding-benchmarks/)
- MiniMax M2.7: [official news](https://www.minimax.io/news/minimax-m27-en) / [MarkTechPost](https://www.marktechpost.com/2026/04/12/minimax-just-open-sourced-minimax-m2-7-a-self-evolving-agent-model-that-scores-56-22-on-swe-pro-and-57-0-on-terminal-bench-2/)
- Hunyuan: [Tencent-Hunyuan/Hy3-preview GitHub](https://github.com/Tencent-Hunyuan/Hy3-preview)
- Vellum Opus 4.7 benchmarks: [vellum.ai](https://www.vellum.ai/blog/claude-opus-4-7-benchmarks-explained)

## ⚠️ 已知 verification gaps

- swebench.com leaderboard fetch timed out 2026-05-03 → V4-Pro / Hy3 / M2.7 / Doubao 數字仍是 vendor-claimed only
- aider.chat leaderboard 也 timeout
- MCP-Atlas 榜更新到 2026-04-08 → Kimi K2.6 / DeepSeek V4 / MiniMax M2.7 / Doubao Seed 2.0 Pro / Hunyuan Hy3 還沒進榜
- GLM-5.1 Z.ai 自報 ModemGuides flagged "independent verification still pending"

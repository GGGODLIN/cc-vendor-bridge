# Vendor Pricing Audit

> Audited 2026-05-03 | **stale-by 2026-08-03**

Anthropic-native endpoint + pricing audit across 5 CN model vendors. Sources: official pages (WebFetch verified) unless marked `[search]`.

## Endpoint + Pricing Matrix

| Vendor | Anthropic Endpoint | Frontier Model | PAYG (in/out per MTok) | Context | Subscription (min) | Free Tier |
|--------|-------------------|---------------|----------------------|---------|-------------------|-----------|
| **DeepSeek** | `api.deepseek.com/anthropic` | V4-Pro | $1.50 / $4.50 | 1M | — | ❌ |
| **GLM (z.ai)** | `api.z.ai/api/anthropic` | GLM-5.1 | $1.40 / $4.40 | 200K | $18/mo (Lite) | ✅ GLM-4.7/4.5/4.6V-Flash free |
| **Kimi (Moonshot)** | `api.moonshot.ai/anthropic` | K2.6 | $0.95 / $4.00 | 256K | ~$19/mo (Kimi Code) [search] | ❌ |
| **MiniMax** | `api.minimax.io/anthropic` | M2.7 | $0.30 / $1.20 | 200K | $10/mo (Starter) | ❌ |
| **MiMo (Xiaomi)** | `token-plan-cn.xiaomimimo.com/anthropic` | V2.5-Pro | $1.00 / $3.00 | 1.1M | ~$6/mo (Lite) [search] | ✅ 100T Token plan (ends 2026-05-28) |
| **Volcengine (Doubao)** | `ark.cn-beijing.volces.com/api/coding` | Seed-Code | — | — | ¥40/mo (~$5.5) [search] | ❌ |

## Per-Vendor Details

### GLM (z.ai)

- **Source:** [Pricing](https://docs.z.ai/guides/overview/pricing) / [Subscribe](https://z.ai/subscribe) / [Devpack Overview](https://docs.z.ai/devpack/overview)
- **Coding Plan tiers:** Lite $18/mo (80 req/5h), Pro $72/mo (400 req/5h), Max $160/mo (1,600 req/5h). Quarterly -10%, yearly -20%.
- **Included models (subscription):** GLM-5.1, GLM-5-Turbo, GLM-4.7, GLM-4.5-Air
- **Premium multiplier:** GLM-5.1/5-Turbo at 3× peak (UTC+8 14:00-18:00) / 2× off-peak. Limited promo: 1× off-peak until end of June 2026.
- **Subscription-only MCPs:** Vision Analysis (8 tools), Web Reader, Zread (GitHub analysis)
- **Registration:** Email + password or Google/GitHub OAuth. No KYC.

### Kimi (Moonshot)

- **Source:** [Agent Support](https://platform.kimi.ai/docs/guide/agent-support) / [Kimi Code](https://www.kimi.com/code/docs/en/third-party-tools/other-coding-agents.html)
- **Two endpoints:** PAYG `api.moonshot.ai/anthropic`, Subscription `api.kimi.com/coding/`
- **Subscription:** Kimi Code bundled with Kimi membership. Pricing tiers not verified via official page [search result only].
- **No free credits.** K2.6 launch top-up rebate ended 2026-05-03.

### MiniMax

- **Source:** [PAYG pricing](https://platform.minimax.io/docs/guides/pricing-paygo) / [Token Plan](https://platform.minimax.io/docs/guides/pricing-token-plan)
- **Token Plan tiers:** Starter $10/mo, Plus $20/mo, Max $50/mo. Highspeed variants at higher prices.
- **Lowest PAYG pricing** among all audited vendors ($0.30/$1.20).
- **No free tier** for text models.

### MiMo (Xiaomi)

- **Source:** [Platform](https://platform.xiaomimimo.com/) / [100T Token Plan](https://100t.xiaomimimo.com/) / [CloudPrice](https://cloudprice.net/models/xiaomi-mimo-2-5)
- **100T Token Incentive Plan:** Apply at 100t.xiaomimimo.com, approval ~3 business days, open to global developers.
- **Token Plan:** Credit-based (not req/5h), no rolling window limit. MiMo-V2.5-Pro at 2× credits.
- **Registration:** Xiaomi account. No Chinese ID KYC.

### Volcengine (Doubao)

- **Source:** [Docs](https://www.volcengine.com/docs/82379/2160841?lang=zh) / [Coding Plan](https://www.volcengine.com/docs/82379/1925114)
- **Coding Plan:** ¥40/mo Lite, ¥200/mo Pro. Bundles Doubao + GLM + Kimi + DeepSeek + MiniMax.
- **KYC:** Chinese ID card + Chinese bank account required. **No international sign-up path.**
- **New user promo paused** since 2026-03-17.

## CC Context Window Alignment

| Vendor | Real Context | CC Fallback | Efficiency |
|--------|-------------|-------------|------------|
| GLM-4.7/5.1 | 200K | 200K | 100% |
| MiniMax M2.7 | 200K | 200K | 100% |
| Kimi K2.5/2.6 | 256K | 200K | 73% |
| MiMo V2.5-Pro | 1.1M | 200K | 18% |
| DeepSeek V4-Pro | 1M | 200K | 18.7% |

See `docs/caveats.md#caveat-6` for workaround.

## Recommendation (as of 2026-05-03)

1. **GLM** — best combo: free Flash tier + Coding Plan $18/mo + Vision MCP + correct 200K context alignment
2. **MiMo** — lowest subscription ($6/mo) + largest context (1.1M) + 100T free plan, but brand new (V2.5 released 2026-04-22)
3. **MiniMax** — lowest PAYG ($0.30/$1.20) + $10/mo Starter, but no free tier
4. **Kimi** — subscription pricing not verified
5. **Volcengine** — best model variety + price, but Chinese KYC blocks foreign users

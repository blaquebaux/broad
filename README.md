# Blaque Baux Broad

**Broad-market and thematic ETF exposure — including leverage — steered by rule, bounded by governance.**

Broad is a member of the Blaque Baux family. The [core repo](https://github.com/blaquebaux/base)
is the **engine and blueprint**. Broad points that engine at index and thematic ETFs —
`IVES` (AI), `GRNY` (Granny Shots), `QQQ` (Nasdaq-100), and `TQQQ` (3x Nasdaq-100) — trading
broad exposures and the occasional leveraged wrapper, with the engine's governance on the
order path. Leverage here is a sizing choice the safety gate bounds, never a bypass.

> **Not investment advice.** Educational/research software. Leveraged/decay products (e.g.
> TQQQ) can lose value even in a flat market and compound losses in chop. Nothing here is
> validated. See [LICENSE](LICENSE).

```bash
git clone --recursive https://github.com/blaquebaux/broad.git
julia --project=engine -e 'using Pkg; Pkg.instantiate()'   # one-time engine setup
```

## The thesis

Broad ETFs are the cleanest place to express a trend/vol-target rule (deep liquidity, tight
spreads). The catch is leverage: the base's leverage work is explicit that levering a book
past its Kelly point *lowers* growth while deepening drawdown, and daily-reset products like
TQQQ add volatility drag on top. So Broad's job is to hold broad/thematic exposure with a
vol-target that treats a 3x product as 3x risk, not 3x free return.

## Research plan (Path A — not yet built)

- **Trend / vol-target on broad ETFs** — QQQ/broad indices, each vol-targeted; the honest baseline.
- **Leverage decay, measured** — quantify TQQQ's path-dependence vs 3× QQQ (the base's
  `leverage_decision` analysis applied to a daily-reset product); when is the wrapper worth it?
- **Thematic rotation** — IVES / GRNY and peers: cross-thematic momentum, tested beta-neutral
  so it is real rotation and not just market beta (and mindful of their short live histories).

## Research — first pass done

Full detail in [`research/README.md`](research/README.md). The scorecard:

| # | Question | Verdict |
|---|----------|---------|
| 1 | Is the TQQQ leverage wrapper worth it? | ❌ **no** — at equal vol it costs ~3% CAGR / 0.12 Sharpe; buy&hold triples the drawdown, not the Sharpe |
| 2 | The keeper? | ✅ trend+vol-target on **unlevered QQQ**: +0.95 Sharpe, −16% DD (vs −35% buy&hold) |
| 3 | Thematic ETFs (IVES/GRNY)? | ❌ weak — IVES lagged QQQ (+0.32 vs +1.00); GRNY too short |

**The synthesis:** the distinctive Broad finding is that **TQQQ is not free leverage.** Decay
is regime-dependent (it *compounded* in the bull, beating naive 3×), but its Sharpe is lower
(0.82 vs 0.93) and its drawdown catastrophic (−82%); and the decisive equal-vol test shows the
wrapper costs ~3% CAGR / 0.12 Sharpe at matched risk. The value in broad ETFs is **managing
exposure, not the wrapper**: trend + vol-target on unlevered QQQ gets Sharpe +0.95 at −16% DD,
and routing it through TQQQ is worse everywhere. Actionable law (extending the base's
leverage_decision): *for a governed book, size the unlevered index; never buy-and-hold the
daily-reset wrapper.* Caveat: the keeper is a managed-equity-beta sleeve (~corr 1 to equities),
not a diversifier.

### Bonds-regime overlay — cross-sleeve sizing (validated, on by default)

BROAD consumes the regime read published by [Bonds](https://github.com/blaquebaux/bonds)
(`~/.config/blaquebaux/bonds_regime.txt`). When the stock-bond correlation is **positive** (bond hedge
dead — no diversification cushion) BROAD **de-risks its managed gross by ×0.75**; **negative** (hedge
live) → full managed exposure. Graceful: missing/stale (>7d)/off → full gross; the overlay only ever
*reduces* risk. Toggle `BB_BONDS_OVERLAY=0`, tune `BB_REGIME_DERISK`.

**Validated** ([`live/broad_regime_validation.jl`](live/broad_regime_validation.jl)) — causal daily
walk-forward, net of cost, reusing the real book + the same 63d SPY–IEF regime the bonds driver
publishes, on the **full 2016–2026 SIP history**:

| book | Sharpe | CAGR | vol | maxDD |
|------|--------|------|-----|-------|
| FULL (managed gross) | +0.94 | 10.7% | 11.5% | −14% |
| **OVERLAY (regime de-risk)** | **+0.96** | 10.2% | 10.7% | **−14%** |

Slightly better Sharpe (+0.02), marginally shallower drawdown, 95% of the return retained (de-risked
32% of days). BROAD is the **only** equity consumer where the overlay survives a full-cycle re-test —
because it already self-de-risks through its trend signal and vol-target, so the small further trim is
consistent rather than window-dependent (unlike [Boom](https://github.com/blaquebaux/boom), whose
apparent benefit was a 2022 artifact). Marginal, but it earns its place: a guardrail, not an alpha boost.

## Status
**Research: first pass complete; managed-exposure keeper — standalone driver built + bonds-regime
sizing overlay wired in and validated** (`research/` + `live/`). `live/broad_live.jl` runs it standalone
through the engine's governed order path + Layer-3 safety gate: multi-horizon trend (30/60/120d,
long-only) × vol-target on **unlevered QQQ**, capped at 1× (the leverage law), then scaled by the bonds
regime. **Dry-run by default**; graduates to paper with its own isolated keys. A managed-equity-beta
sleeve; not validated to the spine's bar.
```bash
BB_DRYRUN=1 julia --project=engine live/broad_live.jl              # prints the managed exposure
julia --project=engine live/broad_regime_validation.jl            # the overlay-earns-its-place test
```

## About Blaque Baux

**Blaque Baux** is a quantitative research initiative and a subsidiary of **[Carter Warrens](https://carterwarrens.com)**.
[**BlaqueBaux.com**](https://blaquebaux.com) is the home for the work; the code lives here on GitHub — open to
study, test, and build bespoke strategies on top of.

Anyone can point an AI at a market. The edge is **understanding what the data actually says — and turning it
into something you can act on.** We test relentlessly and put most of it *on the record as rejected, with the
reason*; what survives is built, governed, and validated before it is ever called real. That combination —
honest research, reproducible evidence, and execution you can trust — is why Carter Warrens leads on
**strategy and implementation**, not merely uses the tools everyone now has.

## The Blaque Baux family
This repo is one sleeve of the **Blaque Baux** family — a single governed engine steered in
many directions. The [core repo](https://github.com/blaquebaux/base) is the
base/blueprint and holds the [full family roster](https://github.com/blaquebaux/base#the-blaquebaux-family).

## Layout
```
engine/     the Blaque Baux platform (git submodule → blaquebaux/base)
research/   three Path-A sketches (leverage decay, managed-leverage keeper, thematic) + scorecard
live/       broad_live.jl (managed QQQ, bonds-regime sizing overlay) + broad_regime_validation.jl + wrapper + plist
```

## License
[MIT](LICENSE). © 2026 Carter Warrens.

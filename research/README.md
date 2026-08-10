# Blaque Baux Broad — research

First-pass Path-A research on the broad-market / thematic ETF sleeve, focused on the
distinctive angle: **leverage**. Extends the base's `leverage_decision` to a daily-reset
product (TQQQ). All sketches read Alpaca SIP daily bars, are read-only, print their own
results. 2016–2026.

```bash
export $(grep -v '^#' ~/.config/blaquebaux/alpaca.env | xargs)   # or source it
python research/broad_1_leverage_decay.py     # is the leverage wrapper worth it?
python research/broad_2_managed_leverage.py    # the keeper
```

## Scorecard

| # | Question | Result | Verdict |
|---|----------|--------|---------|
| 1a | Does TQQQ decay vs 3×QQQ? | regime-dependent — it *compounded* in the bull ($30.41 vs naive $18.38) | ⚖️ nuanced |
| 1b | Is buy&hold leverage worth it? | UPRO/TQQQ Sharpe (0.75/0.82) **< SPY/QQQ** (0.88/0.93), ~2.3× DD | ❌ triples ruin, not Sharpe |
| 1c | At equal risk, does the wrapper cost? | QQQ→20% vol +0.91/+18.6% vs TQQQ→20% +0.79/+15.5% | ❌ **~3% CAGR / 0.12 Sharpe cost** |
| 2 | The keeper? | trend+vol-target on **unlevered QQQ**: +0.95 Sharpe, −16% DD | ✅ manage exposure, not the wrapper |
| 3 | Thematic ETFs (IVES/GRNY)? | IVES +0.32 vs QQQ +1.00; GRNY too short | ❌ weak / inconclusive |

## The synthesis

**The distinctive Broad finding: TQQQ is not free leverage — and the value is in managing
exposure, not in the wrapper.**

- **Decay is regime-dependent** (#1a). The cliché "leveraged ETFs always decay" is wrong: in
  a sustained bull, daily-reset 3× *compounds*, and over 2016–2026 TQQQ ($30.41 per $1) beat
  naive 3×(QQQ) ($18.38). But annualized it delivered <3× at a **lower Sharpe** (0.82 vs 0.93)
  and a **−82%** drawdown.

- **Buy&hold leverage triples the ruin, not the Sharpe** (#1b) — confirming the base's
  leverage_decision. UPRO/TQQQ have higher CAGR but lower Sharpe and ~2.3× the drawdown.

- **The decisive test is equal-vol** (#1c). Match the risk — vol-target QQQ and TQQQ both to
  20% — and the wrapper is **strictly worse**: TQQQ delivers ~3% less CAGR and 0.12 less
  Sharpe. The daily reset + embedded financing cost money. For any target risk, lever the
  *unlevered* index modestly, don't hold the daily-reset wrapper.

- **The keeper** (#2) is governed exposure: trend (30/60/120 sign, long-only) + vol-target on
  **unlevered QQQ** — Sharpe **+0.95, maxDD −16%** (vs −35% buy&hold), stable across halves
  (+1.02 / +0.88). Routing the same strategy through TQQQ is worse everywhere. Managing the
  exposure (getting out in downtrends) is the edge; the leverage wrapper subtracts.

- **Thematic** (#3) is weak: the AI wrapper IVES lagged plain QQQ at high correlation (+0.32
  vs +1.00 Sharpe); GRNY is too new to test.

**Honest caveat:** the keeper is a **managed-equity-beta** sleeve (~long QQQ or flat), not a
diversifier — it correlates ~1 to equities. Its value is drawdown control on beta, and the
actionable leverage law: *for a governed book, size the unlevered index; never buy-and-hold
the daily-reset wrapper.*

## Files
- `_broad_common.py` — shared helpers (align, metrics, vol-target, trend+vol-target).
- `broad_1_leverage_decay.py` — decay, buy&hold ruin, and the equal-vol wrapper cost.
- `broad_2_managed_leverage.py` — the keeper: trend+vol-target on unlevered QQQ.
- `broad_3_thematic.py` — thematic ETFs (weak / short history).

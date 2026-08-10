#!/usr/bin/python3
# =============================================================================
# broad_2_managed_leverage.py — BLAQUE BAUX BROAD #2 (the keeper).
#
# The value in broad ETFs is not the leverage wrapper — it is MANAGING the exposure.
# Multi-horizon trend (30/60/120 sign, long-only) times a vol-target on QQQ cuts the
# buy&hold drawdown from -35% to ~-16% while keeping the return (and slightly beating
# buy&hold Sharpe). Doing the same THROUGH TQQQ is worse everywhere — the wrapper still
# subtracts. So the keeper is governed, vol-targeted trend on the UNLEVERED index.
#
# RESULTS AS TESTED (2016-2026):
#   QQQ  trend+vol-target (unlevered):      Sharpe +0.95  CAGR +14.0%  maxDD -16%
#   TQQQ trend+vol-target (managed leverage): Sharpe +0.85  CAGR +12.3%  maxDD -17%
#   reference: QQQ buy&hold +0.93/-35%, TQQQ buy&hold +0.82/-82%
# NOTE: this is a managed-equity-beta sleeve (~long QQQ or flat), not a diversifier.
# Read-only.
# =============================================================================
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _broad_common import align, metrics, trend_vt

ds, P = align(["QQQ", "TQQQ"]); r = {s: P[s][1:] / P[s][:-1] - 1 for s in P}
print("=" * 72, "\nBROAD #2 — managed leverage: govern the exposure, not the wrapper\n" + "=" * 72)
for lab, base, trade in [("QQQ trend+vol-target (unlevered)", "QQQ", "QQQ"),
                         ("TQQQ trend+vol-target (managed lev)", "QQQ", "TQQQ")]:
    x = metrics(trend_vt(r[base], r[trade]))
    print(f"  {lab:<36} Sharpe {x['sh']:+.2f}  CAGR {x['cagr']*100:+.1f}%  maxDD {x['dd']*100:.0f}%")
# sub-period of the keeper
p = trend_vt(r["QQQ"], r["QQQ"]); p = p[np.isfinite(p)]; h = len(p) // 2
print(f"  keeper sub-periods: first half {metrics(p[:h])['sh']:+.2f}  second half {metrics(p[h:])['sh']:+.2f}")
print(f"  reference: QQQ buy&hold {metrics(r['QQQ'])['sh']:+.2f}/{metrics(r['QQQ'])['dd']*100:.0f}%DD, "
      f"TQQQ buy&hold {metrics(r['TQQQ'])['sh']:+.2f}/{metrics(r['TQQQ'])['dd']*100:.0f}%DD")
print("\nVERDICT: the keeper is trend+vol-targeted UNLEVERED QQQ (+0.95 Sharpe, -16% DD vs")
print("-35% buy&hold). Routing it through TQQQ is worse. Value = managing exposure; the")
print("leverage wrapper is a cost. A managed-equity-beta sleeve, not a diversifier.")
